package Apache::Wyrd::Site::NavPull;
use strict;
use base qw(Apache::Wyrd::Site::Pull);
use Apache::Wyrd::Services::SAK qw(:hash token_parse);
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub _format_output {
	my ($self) = @_;
	my $root = $self->{'root'};
	$self->{'sort'} ||= 'rank,shorttitle';
	my $id = undef;
	#list, item, nearest, selected = default templates
	$self->{list} ||= '<ul>$:items</ul>';
	$self->{item} ||= '<li><a href="$:name">$:shorttitle</a></li>';
	$self->{leaf} ||= $self->{item};
	$self->{selected} ||= '<li><b>$:shorttitle</b></li>';
	$self->{nearest} ||= $self->{selected};
	my $index = $self->{'index'};
	if (not($root)) {
		$id =  $self->_get_section_root;
		$self->_debug("$$id{name} is the root of this section");
		unless ($id->{name}) {
			$self->_data("<!-- no root exists for this section -->");
		}
		$id = $id->{name};
	} elsif ($root eq 'self') {
		$id = $self->dbl->self_path;
	} else {
		#assume the user knows what they're doing.  Make no checks on suitability.
		$id = $root;
	}
	my $out = $self->_format_list($id, 0, $self->_get_path);#root to use, 0 depth, array of parents of current document
	$self->_data($out);
}

sub _format_list {
	my ($self, $id, $depth, @path) = @_;
	my ($out) = ();
	return if ($depth + 1 > ($self->{'maxdepth'} || 2) and not($self->_flags->onlynodes));#This +1 relates to how the maxdepth is always 1 more than is wanted
	my @children = @{$self->index->get_children($id, $self->_search_params)};
	@children = $self->_doc_filter(@children) if ($self->can('_doc_filter'));

	#Sitemap means no leaf nodes, so if there are no children, return.
	if ($self->_flags->onlynodes) {
		return 'abort' unless (@children);
		#but also check for max depth, since we skipped it above.
		return if ($depth + 1 > ($self->{'maxdepth'} || 2));
	}

	#if you don't provide a sort, the sort will be random and change between apache instances.  This means
	#there will be different sha1 hashes for the material, causing unnecessary Widget Index updates.
	my @sort = token_parse($self->{'sort'});
	if (@sort) {
		for (my $i = 0; $i < @sort; $i++) {
			#date keys are reverse by default
			$sort[$i] = "-$sort[$i]" if (grep {$sort[$i] eq $_} $self->_date_fields);
		}
		@children = sort {sort_by_ikey($a, $b, @sort)} @children;
	}
	@children = reverse @children if ($self->_flags->reverse);
	#warn 'children: ' . (join ', ', map {$_->{name}} @$children);
	foreach my $child ($self->_process_docs(@children)) {
		if ($self->_flags->tree) {
			#warn $child->{name};
			my $next = $self->_format_list($child->{name}, $depth + 1, @path);

			#For 'onlynodes', an abort can skip this child.
			next if ($next eq 'abort');

			my $template = (
				  ($depth > ($self->{'maxdepth'} || 2)) 
				? $self->_get_template('leaf', $depth) : ($child->{name} eq $self->dbl->self_path)
				? $self->_get_template('selected', $depth)	: $self->_get_template('item', $depth)
			);
			$out .= $self->_clear_set($child, $template);
			$out .= $next;
		}
		else {
			my ($match) = grep {$child->{name} eq $_} @path;
			my $next = $self->_format_list($match, $depth + 1, @path);

			#For 'onlynodes', an abort can skip this child.
			next if ($next eq 'abort');

			#if this item is not a match for this page, either highlight it as nearest if there are no deeper
			#levels and it is a match for the parentage-path, otherwise treat it like a normal item.
			my $template = (
				  ($child->{name} eq $self->dbl->self_path)
				? $self->_get_template('selected', $depth)	: (($match and not($next))
				? $self->_get_template('nearest', $depth)	: ($self->_flags->light_path and $match) 
				? $self->_get_template('nearest', $depth)	: $self->_get_template('item', $depth))
			);
			$out .= $self->_clear_set($child, $template);
			$out .= $next if ($match);
		}
	}
	$self->{_parent}->{_pull_results} += scalar(@children);
	return $self->_clear_set({items => $out}, $self->_get_template('list', $depth));
}

sub _get_template {
	my ($self, $type, $depth) = @_;
	$depth = '' unless ($depth + 0);
	my $template = $self->{"$type$depth"};
	unless ($template) {
		if ($depth) {
			$self->{"$type$depth"} = $self->_get_template($type, $depth - 1);
		} else {
			warn "no $type$depth";
			return $self->{$type}
		}
	}
}

sub _get_path {
	#returns the parents of this node.
	my ($self, $this_node, $found, @path) = @_;
	my $first = 0;
	unless (ref($found) eq 'HASH') {
		$found = {};
		$this_node ||= $self->dbl->self_path;
		$first = 1;
	}
	if ($this_node eq 'root') {
		$self->_debug('parental path is:' . join(':', @path));
		return @path;
	}
	if ($found->{$this_node}++) {
		$self->_error(
			"Circular geneology for "
			. $path[0]
			. " detected between: "
			. join(', ', sort keys %$found)
			. ".  Backing out..."
		);
		return ();
	}
	my $parents_exist = 0;
	foreach my $parent ($self->_next_parents($this_node)) {
		if (!$parent and !$parents_exist) {
			$self->_error(
				"No further path could be found for "
				. ($path[0] || $this_node)
				. " at $this_node.  Assuming search is finished."
			);
			return @path;
		}
		$parents_exist = 1;
		#Null parents should be filtered out because they would cause an infinite loop.
		#might be better written as _raise_exception
		if (!$parent) {
			$self->_error("Null parent.  Skipping.");
			next;
		}
		push @path, $this_node unless ($first);#don't include self
		@path = $self->_get_path($parent, $found, @path);
		return @path if (@path);
	}
	$self->_warn(
		"Could not resolve a geneology of $this_node."
	) if ($first);
	return ();
}

sub _get_section_root {
	my ($self) = @_;
	my $section = $self->_get_section;
	my $children = $self->index->get_children('root', $self->_search_params);
	foreach my $child (@$children) {
		$self->_verbose("$$child{name} is in section $$child{section}");
		return $child if ($child->{section} eq $section);
	}
	return {};
}

sub _get_section {
	my ($self) = @_;
	my ($path) = $self->_next_parents;
	my $section = $self->index->lookup($path, 'section');
	$self->_verbose("section is $section");
	return $section || $self->{'section'};
}

sub _next_parents {
	my ($self, $item) = @_;
	$item ||= $self->dbl->self_path;
	my $parent = $self->index->lookup($item, 'parent');
	my @parents = map {$_ =~ s/:.+//; $_} token_parse($parent);
	if (scalar(@parents) > 1) {
		#re-order preference if the referrer is a parent.
		$parent = $parents[0];
		my $referrer = $self->dbl->req->header_in('Referer');
		#use regexp to catch the actual parent out of the referrer while
		#simultaneously identifying the referrer as a parent.
		my ($newparent) = grep {$referrer =~ /$_/} @parents;
		if ($newparent) {
			$self->_verbose("referrer is $newparent");
			$parent = $newparent;
			@parents = ($parent, grep {$_ ne $parent} @parents);
		}
	}
	return @parents;
}

1;