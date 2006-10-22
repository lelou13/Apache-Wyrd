package Apache::Wyrd::Site::WidgetControl;
use base qw(Apache::Wyrd::Interfaces::Setter Apache::Wyrd);
use Apache::Wyrd::Services::SAK qw(env_4_get);
use strict;
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub _setup {
	my ($self) = @_;
	$self->{'_on'} = 0;
	$self->_fatal('Must have an attribute') unless ($self->{'attribute'});
	$self->{'value'} = ($self->{'value'} || $self->_data || $self->_parent->{$self->{'attribute'}});
	if ($self->_flags->signal) {
		$self->{'value'} = $self->_parent->{$self->{'value'}};
	}
	$self->{'_original'} = $self->_data;
	$self->_data('$:' . $self->_parent->register_child($self));
}

sub final_output {
	my ($self) = @_;
	my $string = $self->{'_original'};
	return '' unless ($string);
	if ($self->{'_on'}) {
		$string = $self->inactive($string);
	} else {
		$string = $self->active($string);
	}
	#take only the pre-colon part of the switch to identify the widget with via anchor name
	my ($anchor) = split /:/, $self->{'_switch'};
	$anchor = 'widget_' .$anchor;
	return $self->_set(
		{
			switch => $self->{'_switch'},
			anchor => $anchor,
			class => $self->{'class'},
		}, $string);
}

sub url {
	my ($self) = @_;
	my $url = $self->dbl->self_path;
	my $args = $self->env_4_get('_page_state');
	$args = '&' . $args if ($args);
	$url . '?_page_state=#!#_wyrd_site_page_state#!#:$:switch' . $args . '#$:anchor';
}

sub inactive {
	my ($self, $string) = @_;
	if (defined($self->{'on'})) {
		return $self->{'on'};
	} else {
		return '<b>' . $string . '</b>';
	}
}

sub active {
	my ($self, $string) = @_;
	if (defined($self->{'off'})) {
		return $self->{'off'}
	} else {
		return '<a name="$:anchor" href="' . $self->url . '"?:class{ class="$:class"}>' . $string . '</a>';
	}
}

1;