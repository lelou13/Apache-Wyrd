#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details
use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Interfaces::GetUser;
our $VERSION = '0.83';
use Apache::Cookie;

=pod

=head1 NAME

Apache::Wyrd::Interfaces::GetUser - Get User data from Auth service/Auth Cookies

=head1 SYNOPSIS

[in a subclass of Apache::Wyrd::Handler]

    sub process {
      my ($self) =@_;
      $self->{init}->{user} = $self->user('BASENAME::User');
      return FORBIDDEN
        unless ($self->check_auth($self->{init}->{user}));
      return undef;
    }

=head1 DESCRIPTION

Provides a User method that will check both the Apache notes table and the
available cookies for a User created by the C<Apache::Wyrd::Services::Auth>
module.  This is needed by any handler which will need to be informed as to the
findings of a stacked C<Apache::Wyrd::Services::Auth> handler.

But this method is not limited only to stacked Auth handlers.  When the AuthPath
SetPerlVar directive of the C<Apache::Wyrd::Services::Auth> module is beyond the
scope of the area where the authorization was checked (in other words, the
cookie is returned to areas of the site where authorization is not required),
this interface is useful for finding what user is browsing the site.

The SYNOPSIS shows the typical use of this interface in a subclass of
C<Apache::Wyrd::Handler>.

=head1 METHODS

I<(format: (returns) name (arguments after self))>

=over

=item (Apache::Wyrd::User) C<user> (scalar)

Given a User object classname (such as BASENAME::User), this method revives any
User object found by an Auth handler and either placed into the Apache notes
table of the current session or in a cookie provided by the browser.

=cut

sub user {
	my ($self, $user_object) = @_;
	my $user = undef;
	#user may have been found in an earlier handler and left in the notes
	my $user_info = $self->req->notes('User');
	if ($user_info) {
		eval('$user=' . $user_object . '->revive($user_info)');
		if ($@) {
			$self->_warn("User could not be made from notes because of: $@.  Using a blank User.");
		}
		return $user;
	}
	my %cookie = Apache::Cookie->fetch;
	my $auth_cookie = $cookie{'auth_cookie'};
	if ($auth_cookie) {
		$auth_cookie = $cookie{'auth_cookie'}->value;
		return undef unless ($auth_cookie);
		use Apache::Wyrd::Services::CodeRing;
		my $cr = Apache::Wyrd::Services::CodeRing->new;
		$user = ${$cr->decrypt(\$auth_cookie)};
		eval('$user=' . $user_object . '->revive($user)');
		if ($@) {
			if ($self->can('_error')) {
				$self->_error("User could not be made from cookie because of: $@");
			} else {
				warn("User could not be made from cookie because of: $@");
			}
		}
		return $user;
	}
	eval('$user=' . $user_object . '->new');
	return $user;
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