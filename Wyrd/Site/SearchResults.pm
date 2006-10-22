package Apache::Wyrd::Site::SearchResults;
use strict;
use base qw(Apache::Wyrd::Interfaces::IndexUser Apache::Wyrd::Site::Pull Apache::Wyrd::Interfaces::Dater Apache::Wyrd::Interfaces::Setter Apache::Wyrd);
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

# searchparam - name of parameter containing the search string, default 'searchstring'
# item - list item template
# failed - template of error message for failed search
# decimal - decimals of percentile

sub _set_defaults {
	my ($self) = @_;
	my %default = (
		max => 0,
		string => '',
		previous => '',
		'sort' => ($self->_flags->weighted ? 'relevance' : 'score'),
		decimals => 0,
		beginning => 1,
		within => 0,
		override => '',
	);
	foreach my $param (keys %default) {
		$self->{$param} = $self->dbl->param("search$param") || $self->{$param} || $default{$param};
	}
}

sub _format_output {
	my ($self) = @_;

	my $index = $self->_init_index;
	$self->_set_defaults;

	my $max_results = $self->max;
	my $beginning = $self->beginning;
	my $sort_param = $self->sort;
	my $override = $self->override;
	#if the sort param begins with rev_, change the sort param to the base param, but set the reverse flag.
	if ($sort_param =~ s/^rev_//) {
		$self->_flags->reverse(1);
	}
	my $string = $self->string;
	my $previous = $self->previous;
	my $within = $self->within;

	if ($override) {
		$string = $override;
	} elsif ($within and $string and $previous) {
		$string = "($previous) AND ($string)";
	}

	if ($string =~ /\({5}/) {
		$string = $previous;
		$self->dbl->param('searchstring', $previous);
		$self->_data($self->_clear_set({'message' => 'This search has become too complicated to parse as-is.  Please re-phrase your search and try again.'}, $self->{'error'}));
		return;
	}

	if ($string) {
		my @objects = $index->parsed_search($string);
		my $template = ($self->{'item'} || $self->_data);
		my $max_score = 1;
		my $average_count = 0;
		foreach my $object (@objects) {
			$max_score = $object->{'score'} if ($object->{'score'} > $max_score);
			$average_count += $object->{'count'};
			foreach my $attr (keys %$object) {
				delete $object->{$attr} unless ($object->{$attr});
			}
		}
		$average_count = $average_count/scalar(@objects) if (@objects);
		$average_count ||= 50; #if all else fails, assume 50 words.
		my $max_relevance = 0;
		foreach my $object (@objects) {
			$object->{'count'} ||= $average_count; #use an average count for undefined counts
			$object->{'relevance'} = $object->{'score'} / $object->{'wordcount'};
			$max_relevance = $object->{'relevance'} if ($object->{'relevance'} > $max_relevance);
		}
		my ($out, $counter) = ();
		my @processed_objects = ();
		foreach my $object (sort {$b->{$sort_param} <=> $a->{$sort_param}} @objects) {
			$counter++;
			$object->{'rank'} = (int(($object->{'score'} * 100 * (10 ** $self->{'decimals'})/$max_score) + .5) / (10 ** ($self->{'decimals'}))) . '%';
			$object->{'weighted_rank'} = (int(($object->{'relevance'} * 100 * (10 ** $self->{'decimals'})/$max_relevance) + .5) / (10 ** ($self->{'decimals'}))) . '%';
			$object->{'counter'} = $counter;
			push @processed_objects, $object;
		}
		@processed_objects = $self->_process_docs(@processed_objects);

		@objects = $self->_doc_filter(@processed_objects);

		#so did any objects survive the filters?
		my $total = @objects;
		unless ($total) {
			$self->_data($self->{'failed'} || "<i>Sorry, no pages matched your query</i>");
			return;
		}

		#reverse the sort order if the reverse flag is set.
		@objects = reverse @objects if ($self->_flags->reverse);

		my $next_beginning = 0;
		my $previous_beginning = 0;
		#apply limits if they exist
		if ($max_results) {
			my $start = $beginning - 1;
			$start = 0 if ($start < 0);
			@objects = splice @objects, $start, $max_results;
			my $new = $beginning + $max_results;
			#don't add a new beginning if it overpasses the total
			$next_beginning =  $new if ($new < $total);
			$previous_beginning = $beginning - $max_results;
			$previous_beginning = 0 if ($previous_beginning < 1);
		}

		#template them up and post them out
		foreach my $object (@objects) {
			$out .= $self->_text_set($object, $template);
		}
		$self->_data($self->_set({
				items=> $out,
				total => $total,
				remaining => $total - $max_results,
				previous => $previous_beginning,
				next => $next_beginning,
				current => $string,
			}, $self->_data));
	} else {
		#no search, show some instructions instead
		$self->_data($self->{'instructions'});
	}
}

sub _doc_filter {
	my ($self) = shift;
	return @_;
}

1;