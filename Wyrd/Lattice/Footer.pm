use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Lattice::Footer;
our $VERSION = '0.80';
use base qw(Apache::Wyrd);

sub _format_output {
	my ($self) = @_;
	$self->_raise_exception($self->base_class . " may only be used within a Apache::Wyrd::Lattice context")
		unless ($self->_parent->can('register_footer'));
	$self->_parent->register_footer($self->_data);
	$self->_data('');
	return undef;
}

1;