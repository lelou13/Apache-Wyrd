use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Lattice::Header;
our $VERSION = '0.93';
use base qw(Apache::Wyrd);

sub _format_output {
	my ($self) = @_;
	$self->_raise_exception($self->base_class . " may only be used within a Apache::Wyrd::Lattice context")
		unless ($self->_parent->can('register_header'));
	$self->{'_parent'}->register_header($self->_data);
	$self->_data(undef);
	return undef;
}

1;