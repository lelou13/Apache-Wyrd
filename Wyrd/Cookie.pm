use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized redefine);

package Apache::Wyrd::Cookie;
our $VERSION = '0.95';
use vars qw(@ISA);

my $have_apr = 1;
eval('use Apache::Cookie');
if ($@) {
	eval('use CGI::Cookie');
	die "$@" if ($@);
	$have_apr=0;
	push @ISA, 'CGI::Cookie';
} else {
	push @ISA, 'Apache::Cookie';
}

=pod

=head1 NAME

Apache::Wyrd::Cookie - Consistency wrapper for Apache::Cookie and CGI::Cookie

=head1 SYNOPSIS

	use Apache::Wyrd::Cookie;
	#$req is Apache request object
	my $cookie = Apache::Wyrd::Cookie->new(
		$req,
		-name=>'check_cookie',
		-value=>'checking',
		-domain=>$req->hostname,
		-path=>($auth_path || '/')
	);
	$cookie->bake;

	my %cookie = Apache::Wyrd::Cookie->fetch;
	my $g_value = $cookie{'gingerbread'};


=head1 DESCRIPTION

Wrapper for C<Apache::Cookie> or C<CGI:Cookie> cookies. This class is
provided for no other reason than to make the C<new> and C<bake> methods
consistent in their requirements, which they are not normally.
Otherwise, C<Apache::Wyrd::Cookie> behaves entirely like C<Apache::Cookie>
and takes the same arguments to its methods. Please refer to the
documentation for that module.

=cut

sub new {
	my $class = shift;
	my @caller = caller;
	return CGI::Cookie->new(@_) if ($caller[0] eq 'CGI::Cookie');
	my $req = shift;
	my $data = {};
	if ($have_apr) {
		$data = Apache::Cookie->new($req, @_);
	} else {
		$data = CGI::Cookie->new(@_);
		$data->{'_wyrd_req'} = $req;
	}
	bless $data, $class;
	return $data;
}

sub bake {
	my $self = shift;
	return $self->SUPER::bake if ($have_apr);
	my $req = $self->{'_wyrd_req'};
	die('Cannot determine the Apache object.  Perhaps you are attempting to bake a fetched cookie?')
		unless (UNIVERSAL::isa($req, 'Apache'));
	$req->err_headers_out->add("Set-Cookie" => ($self->as_string));
	$req->headers_out->add("Set-Cookie" => ($self->as_string));
}

=pod

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