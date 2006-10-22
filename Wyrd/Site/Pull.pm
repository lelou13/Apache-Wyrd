package Apache::Wyrd::Site::Pull;
use strict;
use base qw(Apache::Wyrd::Interfaces::IndexUser Apache::Wyrd::Interfaces::Setter Apache::Wyrd::Interfaces::Dater Apache::Wyrd);
use Apache::Wyrd::Services::SAK qw(token_parse);
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub _process_docs {
	my ($self, @docs) = @_;
	my @out = ();
	foreach my $doc (@docs) {
		foreach my $key (keys(%$doc)) {
			#warn $$doc{$key} . join(':', caller) if (grep {$_ eq $key} $self->_date_fields);
			$$doc{$key} = $self->_date_string(split(/[,-]/, $$doc{$key})) if (grep {$_ eq $key} $self->_date_fields);
			delete $$doc{$key} unless ($$doc{$key});#undefine missing bits for setter
		}
		push @out, $doc;
	}
	return @out;
}

sub _date_fields {
	return qw(published);
}

sub _skip_fields {
	return qw(data timestamp digest);
}

sub _search_params {
	my ($self) = @_;
	my %params = ();
	if ($self->can('_skip_fields')) {
		my @skip = $self->_skip_fields;
		$params{'skip'} = \@skip;
	}
	if ($self->can('_require_fields')) {
		my @require = $self->_require_fields;
		$params{'require'} = \@require;
	}
	return \%params;
}

sub _generate_output {
	my ($self) = @_;
	$self->{'index'} = undef;
	return $self->{'_data'};
}

sub _process_eventdate {
	my ($self, @docs) = @_;
	my $eventdate = $self->{'eventdate'};
	my @localtime = localtime;
	$localtime[4]++;
	my ($year, $month, $day) = ($localtime[5], $localtime[4], $localtime[3]);
	my $today = $self->_num_today;
	my $yesterday = $self->_num_yesterday;
	my $tomorrow = $self->_num_tomorrow;
	$eventdate =~ s/yesterday/$yesterday/g;
	$eventdate =~ s/today/$today/g;
	$eventdate =~ s/tomorrow/$tomorrow/g;
	if ($eventdate =~ /^([+-])\d+$/) {
		my $begin = $self->_num_today;
		my ($nyear, $nmonth, $nday) = Add_Delta_Days($year, $month, $day, $eventdate);
		my $end = $self->_num_year($nyear, $nmonth, $nday);
		$eventdate = "$begin,$end";
	}
	#warn $eventdate;
	unless ($eventdate =~ /^(\d{8})?,(\d{8})?$/) {
		$self->_error("Illegal value for eventdate: $eventdate");
		return @docs;
	}
	my ($begin, $end) = split ',', $eventdate;
	$begin += 0;
	$end += 0;
	@docs = grep {$_->{'eventdate'}} @docs;
	foreach my $doc (@docs) {
		($doc->{'eventbegin'}, $doc->{'eventend'}) = split ',', $doc->{'eventdate'};
		$doc->{'eventend'} ||= $doc->{'eventbegin'};
	}
	#map {warn $_->{'eventbegin'} . '-' . $_->{'eventend'}} @docs;
	@docs = grep {$_->{'eventend'} >= $begin} @docs if ($begin);
	@docs = grep {$_->{'eventbegin'} <= $end} @docs if ($end);
	return @docs;
}

1;