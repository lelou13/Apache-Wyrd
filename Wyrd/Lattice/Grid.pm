use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Lattice::Grid;
our $VERSION = '0.91';
use base qw(Apache::Wyrd);

sub _format_output {
	my ($self) = @_;
	$self->_raise_exception($self->base_class . " may only be used within a Apache::Wyrd::Lattice context")
		unless ($self->_parent->can('register_grid'));
	$self->_parent->register_grid($self->_data);
	$self->_data('');
	return undef;
}

1;