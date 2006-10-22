package Apache::Wyrd::Site::TagPull;
use strict;
use base qw(Apache::Wyrd::Site::Pull);
use Apache::Wyrd::Services::SearchParser;
use Apache::Wyrd::Services::SAK qw(:hash);
use Apache::Wyrd::Interfaces::Dater;
use Date::Calc qw(Add_Delta_Days);
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub _set_defaults {
	my ($self) = @_;
	$self->{list} ||= '<ul type="square">$:items</ul>';
	$self->{item} ||= '<li class="spaced">?:published{$:published &#151; }<a href="$:name">$:title</a>?:description{<BR>$:description}</li>';
	$self->{selected} ||= '<li class="spaced">?:published{$:published&#151;}<b>$:title</b>?:description{<BR>$:description}</li>';
	$self->{header} ||= '<p><b>$:tagname</b></p>';
}

sub _format_output {
	my ($self) = @_;
	my $pull_results = 0;
	$self->_set_defaults;
	my $out = undef;
	my @sort = token_parse($self->{'sort'});
	my @docs = $self->_get_docs;

	#optional filters
	@docs = $self->_doc_filter(@docs) if ($self->can('_doc_filter'));
	@docs = grep {$_->{'published'} < $self->{'before'}} @docs if ($self->{'before'});
	@docs = grep {$_->{'published'} > $self->{'after'}} @docs if ($self->{'after'});
	@docs = grep {$_->{'name'} ne $self->dbl->self_path} @docs unless($self->_flags->metoo);
	@docs = $self->_process_eventdate(@docs) if ($self->{'eventdate'});
	if (@sort) {
		for (my $i = 0; $i < @sort; $i++) {
			#date keys are reverse by default
			$sort[$i] = "-$sort[$i]" if (grep {$sort[$i] eq $_} $self->_date_fields);
		}
		@docs = sort {sort_by_ikey($a, $b, @sort)} @docs;
	}
	@docs = reverse(@docs) if ($self->_flags->reverse);
	@docs = $self->_process_limit(@docs) if ($self->{'limit'});

	@docs = $self->_process_docs(@docs);
	$out = $self->_format_list(@docs);
	$pull_results = scalar(@docs);
	if ($self->_flags->autohide and !$pull_results) {
		$self->_data('');
		return;
	}
	if ($self->_data =~ /\$:/) {
		my $set = $self->_template_hash;
		$set->{'list'} = $out;
		$out = $self->_clear_set($set);
	}
	#add to the total for the parent, in case there are other pull results
	$self->{_parent}->{_pull_results} += $pull_results;
	$self->_data($out);
}

sub _get_docs {
	my ($self) = @_;
	my $all = $self->{'all'};
	my $any = $self->{'any'};
	my $tags = $self->{'search'};
	#list, item, selected, header are templates
	my (@docs) = ();
	if ($tags) {
		my @phrases = split ',', $tags;
		foreach my $phrase (@phrases) {
			push @docs, $self->logic_search($phrase);
		}
		@docs = uniquify_by_key('id', @docs);
	} elsif ($any) {
		my @tags = parse_token($tags);
		foreach my $tag (@tags) {
			#pile on any matching document
			push @docs, $self->search($tag);
		}
		#eliminate duplicates
		@docs = uniquify_by_key('id', @docs);
	} else {
		my %docs = ();
		my @tags = token_parse($tags);
		my $tag = pop @tags;
		@docs = $self->search($tag);
		while ($tag = pop(@tags)) {
			#map next tag onto a hash
			%docs = map {$_->{'id'}, 1} $self->search($tag);
			#filter out any docs that aren't already there
			@docs = grep {$docs{$_->{'id'}}} @docs;
		}
	}
	#warn join qq'\n======\n', map {$_->{id}} @docs;
	return @docs;
}

sub logic_search {
	my ($self, $phrase) = @_;
	my $parser = Apache::Wyrd::Services::SearchParser->new($self);
	return $parser->parse($phrase);
}

sub search {
	my ($self, $phrase) = @_;
	return $self->{'index'}->word_search($phrase,'tags', $self->_search_params);
};

sub _process_limit {
	my ($self, @docs) = @_;
	my $limit = $self->{'limit'};
	return @docs unless($limit);
	$limit = ",$limit" if ($limit =~ /^\d+$/);
	unless ($limit =~ /^\d*,\d*$/) {
		$self->_error("Illegal value for limit: $limit");
		return @docs;
	}
	my ($begin, $end) = split ',', $limit;
	$begin += 0;
	$begin ||= 1;
	$end += 0;
	$end ||= scalar(@docs);
	if ($end < $begin) {
		($begin, $end) = ($end, $begin);
	}
	my $offset = $begin - 1;
	$offset = 0 if ($offset < 0);
	my $length = $end - $offset;
	$length = 0 if ($length < 0);
	@docs = splice (@docs, $offset, $length);
	return @docs;
}

sub _format_list {
	my ($self, @docs) = @_;
	my $out = '';
	foreach my $doc (@docs) {
		if ($doc->{'id'} eq $self->dbl->self_path) {
			$out .= $self->_clear_set($doc, $self->{selected});
		} else {
			$out .= $self->_clear_set($doc, $self->{item});
		}
	}
	$out = $self->_set({items => $out}, $self->{list});
	return $out;
}

1;