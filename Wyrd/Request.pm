use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized redefine);

package Apache::Wyrd::Request;
our $VERSION = '0.96';
my $have_apr = 1;
eval ('use Apache::Request');
if ($@) {
	eval ('use CGI qw(param)');
	die "$@" if ($@);
	$have_apr=0;
}

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

Wrapper for C<Apache::Request> or C<CGI> object with C<Apache::Request>-type
assurances that this is the first and only invocation for this
PerlResponseHandler.  The wrapper is for the convenience of allowing a
consistent set of parameters to be used in initializing the
C<Apache::Request> object between stacked/different handlers.

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
	my ($class, $req) = @_;
	my $previous_req = undef;
	do {
		#attempt to recover the instance from the initial request if this
		#is not the initial request.
		my $instance = $req->pnotes($class . '_req_object');
		return $instance if ($instance);
		$previous_req = $req->prev;
		$req = $previous_req if ($previous_req);
	} while ($previous_req);
	my @parms = $req->dir_config->get('RequestParms');
	@parms = () unless ($parms[0]);
	die "Uneven number of RequestParms in configuration.  See Apache::Wyrd::Request documentation."
		if (scalar(@parms) % 2);
	$req->warn("Ignoring RequestParms because Apache::Request is not available and CGI is being substituted.  Install libapreq/Apache::Request to use RequestParms.") if (@parms and not($have_apr));
	my $req_object = undef;
	if ($have_apr) {
		$req_object = Apache::Request->new($req, @parms);
		bless $req_object, 'Apache::Request';
	} else {
		$req_object = CGI->new;
		bless $req_object, 'CGI';
	}
	$req->pnotes($class . '_req_object' => $req_object);
	return $req_object;
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

Copyright 2002-2007 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

1;