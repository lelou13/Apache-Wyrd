use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized redefine);

package Apache::Wyrd::Request;
our $VERSION = '0.84';
use base qw (Apache::Request);

=pod

=head1 NAME

Apache::Wyrd::Request - Object for unifying libapreq configurations across Wyrds

=head1 SYNOPSIS

in Apache config:

	PerlSetVar RequestParms DISABLE_UPLOADS
	PerlAddVar RequestParms 1
	PerlAddVar RequestParms POST_MAX
	PerlAddVar RequestParms 1024

=head1 DESCRIPTION

Wrapper for Apache::Request as a singleton.  The wrapper is for the
convenience of allowing a consistent set of parameters to be used in
initializing the Apache::Request object between stacked/different
handlers.

These parameters are handed to the object via the RequestParms directory
config variable.  As this is a hash, items must be added in pairs using
PerlSetVar and PerlAddVar as shown in the SYNOPSIS.

=head1 METHODS

I<(format: (returns) name (arguments after self))>

=over

=item (Apache::Wyrd::Request) C<instance> (void)

See C<Apache::Request-E<gt>instance()>.  The only difference is the
configuration via PerlSetVar/PerlAddVar directives.

=cut

sub instance {
	my ($self, $req) = @_;
	my @parms = $req->dir_config->get('RequestParms');
	@parms = () unless ($parms[0]);
	die "Uneven number of RequestParms in configuration.  See Apache::Wyrd::Request documentation."
		if (scalar(@parms) % 2);
	return $self->SUPER::instance($req, @parms);
}

=pod

=back

=head1 BUGS/CAVEATS/RESERVED METHODS

UNKNOWN

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item Apache::Wyrd

General-purpose HTML-embeddable perl object

=back

=head1 LICENSE

Copyright 2002-2004 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

1;