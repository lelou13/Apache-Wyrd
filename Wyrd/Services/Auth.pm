use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Services::Auth;
our $VERSION = '0.98';
use Apache::Wyrd::Services::CodeRing;
use Apache::Wyrd::Services::TicketPad;
use Digest::SHA qw(sha256_hex);
use Apache::Wyrd::Request;
use Apache::Constants qw(AUTH_REQUIRED HTTP_SERVICE_UNAVAILABLE REDIRECT DECLINED);
use Apache::Wyrd::Cookie;
use Apache::URI;
use MIME::Base64;
use LWP::UserAgent;
use HTTP::Request::Common;

=pod

=head1 NAME

Apache::Wyrd::Services::Auth - Cookie-based authorization handler

=head1 SYNOPSIS

    <Directory /var/www/restricted/>
      SetHandler perl-script
      PerlHandler Apache::Wyrd::Services::Auth BASENAME::Handler
      PerlSetVar  LoginFormURL   /login.html
      PerlSetVar  NoCookieURL    /cookies.html
      PerlSetVar  LSKeyURL       https://login.someserver.com/login.html
      PerlSetVar  LSLoginURL     https://login.someserver.com/login.html
      PerlSetVar  LSDownURL      /lsdown.html
      PerlSetVar  AuthPath       /
      PerlSetVar  UserObject     BASENAME::User
      PerlSetVar  ReturnError    error_message
      PerlSetVar  AuthLevel      restricted
      PerlSetVar  Debug          0
      PerlSetVar  TieAddr        1
    </Directory>

=head1 DESCRIPTION

Auth provides a secure cookies-based login system for a Wyrd-enabled server
that might not itself be equipped with SSL.  It can do so if provided a
connection to an SSL-enabled Apache server with an
C<Apache::Wyrd::Services::LoginServer> available on a secure port.  It uses
a standard SSL channel to circumvent an unauthorized party from obtaining
login credentials (username/password) by packet-sniffing.

To do so, it maintains a cookie-based authorization scheme which is
implemented using stacked handlers.  It handles authorization by login
and/or cookie, and passes the user information to handlers down the
stack via mod_perl's C<notes> table.  The Auth module should be the
first handler in a chain of handlers.

The Auth Module first checks for a "challenge" variable under CGI which
it expects to contain a username/password pair encrypted via it's own
private encryption key (see the use of the
C<Apache::Wyrd::Services::Key> object in relation to the
C<Apache::Wyrd::Services::CodeRing> object).  This challenge is
generated by a LoginServer (see below), and is part of the regular login
sequence.  If this variable is provided, it will attempt to create a
user object from it and set a cookie on the browser (B<auth_cookie>)
which keeps this user object stored for later use.

If the challenge is not found, it checks for a cookie called
auth_cookie, and decrypts it, passing it on in an XML notes item called
"user" if it finds it.  (The user note is in perl code, stored and
retrieved by the next handler via C<XML::Dumper>.)

If the cookie is not found, it checks first to see if cookies are
enabled on the browser, and if not, sends the browser to a url to
explain the need for cookies.  It does this check by reloading the page
with a test cookie defined and checking for that cookie in the following
request.

If cookies are enabled, it will attempt to set up a login.  First, it
will establish an encrypted session with a login server via SSL in which
it will give the login server it's internal key, encrypted with a random
key and that key.  If this session fails, it will direct the browser to
a page explaining that the login server is down and authorization cannot
proceed.

If the session succeeds, it will encode the URL the browser originally
requested so that it may be redirected to that URL on successful login. 
This encoded URL, an authorization URL, and the encrypted key it gave
the login server is given to the browser as a GET-request redirection to
a login page.  On the login page, the encoded URL and the encrypted key
are to be used as hidden fields to pass to the login url which is given
as the action attribute of the login form.  The login form has, at a
minimum, a username and password.  These are all submitted to the login
server via SSL.

The login server will then decrypt the encrypted key, use that key to
encrypt the login information, and send that information to the
originally-requested URL via the challenge CGI variable.  As the Auth
object will again be in the stack, it will receive the challenge per the
first paragraph of this description.

Under SSL, instead, the Auth module checks for a user with appropriate
clearance.  Not finding one, it will expect to find the username and password
under CGI variables of those names.  If found, it will attempt athentication.
If this fails, as above, the browser will be redirected to the login URL.
Instead of a LoginServer, however, the login form will be expected to attempt
the URL it was refused in the first place, and will return the browser
to the login page on each subsequent failure until a login succeeds.

Note that under SSL, since CGI variables are scanned for authentication
information, any CGI variables being passed prior to authentication will be
lost in the subsequent re-direction which checks for browser cookie acceptance.
If you wish to avoid this behavior, set the LSForce PerlVar directive to 1.

=head2 METHODS

I<(format: (returns) name (arguments after self))>

=over

=item (RESPONSE) C<handler> (Apache)

All the processes above are handled by the C<handler> subroutine.

=cut

sub handler : method {
	my ($class, $req) = @_;
	if (scalar(@_) == 1) {
		$req = $class;
		$class = 'Apache::Wyrd::Services::Auth';
	}
	my $self = {};
	bless ($self, $class);
	my $scheme = 'http';
	$scheme = 'https' if ($ENV{'HTTPS'} eq 'on');
	my $port = '';
	$port = ':' . $req->server->port unless ($req->server->port == 80);
	my $challenge_failed = '';
	my $debug = $self->{'debug'} = $req->dir_config('Debug');
	my $user_object = $self->{'user_object'} = $req->dir_config('UserObject');
	my $auth_path = $self->{'ticketfile'} = $req->dir_config('AuthPath');
	my $ticketfile = $self->{'ticketfile'} = $req->dir_config('KeyDBFile') || '/tmp/keyfile';
	my $challenge_param = $self->{'challenge_param'} = $req->dir_config('ChallengeParam') || 'challenge';
	my $key_url = $self->{'key_url'} = $req->dir_config('LSKeyURL');
	my $force_login_server = $req->dir_config('LSForce');
	if (!$key_url and ($scheme eq 'http' or $force_login_server)) {
		die "Must define LSKeyURL in Apache Config to use Apache::Wyrd::Services::Auth on an insecure port.";
	}
	unless ($user_object) {
		die "Must define UserObject in Apache Config to use Apache::Wyrd::Services::Auth.";
	}
	my $cr = Apache::Wyrd::Services::CodeRing->new;
	my %cookie = Apache::Wyrd::Cookie->fetch;
	my $user_info = undef;
	my $auth_cookie = $cookie{'auth_cookie'};
	my $user = undef;
	my $ip = undef;

	#if the auth_cookie exists, decrypt it and see if it makes sense
	if ($auth_cookie) {
		($ip, $auth_cookie) = split(':', eval{$cookie{'auth_cookie'}->value});
		$debug && warn("IP before decrypt: " . $ip);
		$ip = ${$cr->decrypt(\$ip)};
		my $ip_ok = 1;
		if ($req->dir_config('TieAddr')) {
			my $remote_ip = $req->connection->remote_ip;
			if ($remote_ip ne $ip) {
				$debug && warn ("Remote ip $remote_ip does not match cookie IP $ip, failing authentication");
				$ip_ok = 0;
			} else {
				$debug && warn ("Remote ip $remote_ip matches cookie IP $ip");
			}
		}
		$debug && warn("Cookie value before decrypt: " . $auth_cookie);
		$user_info = ${$cr->decrypt(\$auth_cookie)};
		$debug && warn("Cookie value: " . $user_info);
		$user=$self->revive($user_info);
		if (($user_info and not($user->check_credentials)) or ($auth_cookie and not($user_info)) or ($auth_cookie and not($ip_ok))) {
			my $cookie = Apache::Wyrd::Cookie->new(
				$req,
				-name=>'auth_cookie',
				-value=> '',
				-domain=>$req->hostname,
				-path=> ($auth_path || '/')
			);
			$cookie->bake;
			#TO DO: Make this error message configurable
			$challenge_failed = "Your session has expired due to system maintenance.  Please log in again.";
			$user_info = undef;
		}
	}

	#if the user info is found, pass it to the next handler via the Notes interface to Apache
	if ($user_info) {
		$req->notes->add('User' => $user_info);
		return DECLINED;
	}

	#This won't be declined, now, so we can parse any GET/POST requests
	my $apr = Apache::Wyrd::Request->instance($req);

	#is there a failed challenge?
	$challenge_failed = ($apr->param('ls_error') || '');

	#is there a challenge variable from the Login Server?
	my $challenge = $apr->param($challenge_param);
	$apr->param($challenge_param, '');
	if ($challenge) {
		$debug && warn('challenge ' . "'$challenge'" . ' decrypts to ' . join(':', $self->decrypt_challenge($challenge)));
		my ($username, $password) = $self->decrypt_challenge($challenge);
		if ($username) {
			my $user = $self->initialize({username => $username, password => $password});
			if ($user->login_ok) {
				$self->authorize_user($req, $user);
				my $uri = $req->uri;
				$uri = Apache::URI->parse($uri);
				#remove the challenge portion of the query string
				my $query_string = $uri->query;
				$query_string =~ s/challenge=[0123456789abcdefABCDEF:]+\&?//g;
				$query_string =~ s/\&$//;
				$query_string = '?' . $query_string if ($query_string);
				my $self = $scheme . '://' . $req->hostname . $port . $req->uri . $query_string;
				$req->custom_response(REDIRECT, $self);
				return REDIRECT;
			} else {
				$debug && warn('challenge was bad, trying regular login again.');
				$challenge_failed = ($user->auth_error || 'Incorrect Username/Password.  Please log in again.');
			}
		} else {
			$debug && warn('challenge could not be decrypted, trying regular login again.');
			$challenge_failed = ($user->auth_error || 'Could not process the login because of system maintenance.  Please try again.');
		}
	}

	#no auth cookie or challenge.  Can the browser accept cookies?

	#if this req represents a cookie check, tell the user they must turn on cookies
	#if the test cookie is not present.
	if ($apr->param('check_cookie')) {
		unless ($cookie{'check_cookie'}) {
			my $no_cookie_url = $req->dir_config('NoCookieURL');
			$no_cookie_url = $scheme . '://' . $req->hostname . $port . $no_cookie_url unless ($no_cookie_url =~ /^http/i);
			$req->custom_response(REDIRECT, $no_cookie_url);
			return REDIRECT;
		}

	#if we have no knowledge of whether the browser can accept cookies at this point,
	#put it to the test by setting the cookie and forcing the browser to reload this page,
	#with the cookie_check variable set.
	} elsif($scheme ne 'https') {
		unless ($cookie{'check_cookie'}) {
			my $cookie = Apache::Wyrd::Cookie->new(
				$req,
				-name=>'check_cookie',
				-value=>'checking',
				-domain=>$req->hostname,
				-path=>($auth_path || '/')
			);
			$cookie->bake;
			my $query_char = '?';
			my $uri = $req->uri;
			$uri = Apache::URI->parse($uri);
			my $query_string = $uri->query;
			if ($query_string) {
				$query_char = '&';
				$query_string = '?' . $query_string;
			}
			my $scheme = $scheme;
			$req->custom_response(REDIRECT, $scheme . '://' . $req->hostname . $port . $req->uri . $query_string . $query_char . 'check_cookie=yes');
			return REDIRECT;
		}
	}
	
	#We have determined at this point that the user has no prior authorization, but that
	#cookies are enabled and they could be authorized.

	#require an SSL login server if this is an insecure port (currently always).
	#in future, 1 will be replaced with a test for SSL encryption.
	if (($ENV{'HTTPS'} ne 'on') or $force_login_server) {

		#Get an encryption key and a ticket number
		my ($key, $ticket) = $self->generate_ticket;

		#Send that pair to the Login Server
		$key_url = 'https://' . $req->hostname . $key_url unless ($key_url =~ /^https?:\/\//i);
		if ($key_url =~ /^https:\/\//i) {
			eval('use IO::Socket::SSL');
			die "LWP::UserAgent needs to support SSL to use a login server over https.  Install IO::Socket::SSL and make sure it works."
				if ($@);
		}
		my $ua = LWP::UserAgent->new;
		$ua->timeout(60);
		my $response = $ua->request(POST $key_url,
			[
				key		=>	$key,
				ticket	=>	$ticket
			]
		);
		my $status = $response->status_line;

		#If the key can't be saved on the login server, send regrets and close
		if ($status !~ /200|OK/) {
			if ($status =~ /Invalid argument/i) {
				$debug && warn ("You may need to Update IO::Socket::SSL");
			} else {
				$debug && warn ("Login Server status was $status");
			}
			my $failed_url = $req->dir_config('LSDownURL');
			$failed_url = $scheme . '://' . $req->hostname . $port . $failed_url unless ($failed_url =~ /^http/i);
			if ($failed_url) {
				$req->custom_response(REDIRECT, $failed_url);
				return REDIRECT;
			} else {
				return HTTP_SERVICE_UNAVAILABLE;
			}

		#Send the encrypted data as a lookup key to the login form to add
		#to its hidden fields.  If a challenge failed earlier in the script
		#and ReturnError is defined, use it.
		} else {
			my $use_error = $req->dir_config('ReturnError');
			my $login_url = $req->dir_config('LoginFormURL');
			$login_url = $scheme . '://' . $req->hostname . $port . $login_url unless ($login_url =~ /^http/i);
			my $ls_url = $req->dir_config('LSLoginURL');
			$ls_url = $scheme . '://' . $req->hostname . $port . $ls_url unless ($ls_url =~ /^http/i);
			if ($login_url) {
				my $uri = $req->uri;
				$uri = Apache::URI->parse($uri);
				my $query_string = $uri->query;
				$query_string =~ s/\&?check_cookie=yes\&?//;
				$query_string =~ s/challenge=[0123456789abcdefABCDEF:]+\&?//g;
				$query_string = '?' . $query_string if ($query_string);
				my $on_success = Apache::Util::escape_uri(encode_base64($scheme . '://' . $req->hostname . $port . $req->uri . $query_string));
				my $redirect = $login_url .
					'?ls=' . $ls_url .
					'&ticket=' . $ticket .
					'&on_success=' . $on_success .
					'&use_error=' . $use_error .
					($challenge_failed ? '&'. $use_error . '=' . $challenge_failed : '');
				$debug && warn('Need a login, with redirect going to ' . $redirect);
				$req->custom_response(REDIRECT, $redirect);
				return REDIRECT;
			} else {
				die "Must define LoginFormURL in Apache Config to use Apache::Wyrd::Services::Auth";
			}
		}

	#Since we are using SSL, we can accept login information as normal CGI params.
	} else {
		my $username = $apr->param('username');
		my $password = $apr->param('password');
		my $login_failed = '';
		if ($username) {
			my $user = $self->initialize({username => $username, password => $password});
			if ($user->login_ok) {
				$self->authorize_user($req, $user);
				my $uri = $req->uri;
				$uri = Apache::URI->parse($uri);
				my $redirect = $scheme . '://' . $req->hostname . $port . $req->uri . '?check_cookie=yes';
				$debug && warn('Setting a cookie, with redirect going to ' . $redirect);
				$req->custom_response(REDIRECT, $redirect);
				return REDIRECT;
			}
			$login_failed = 'Login failed.  Please check your username and password.';
			$debug && warn('Login failed.');
		} else {
			$debug && warn('Login was not provided.');
		}
		my $use_error = $req->dir_config('ReturnError');
		my $login_url = $req->dir_config('LoginFormURL');
		$login_url = $scheme . '://' . $req->hostname . $port . $login_url unless ($login_url =~ /^http/i);
		my $ls_url = $scheme . '://' . $req->hostname . $port . $req->uri;
		if ($login_url) {
			my $uri = $req->uri;
			$uri = Apache::URI->parse($uri);
			my $on_success = Apache::Util::escape_uri(encode_base64($scheme . '://' . $req->hostname . $port . $req->uri));
			my $redirect = $login_url .
				'?ls=' . $ls_url .
				'&on_success=' . $on_success .
				'&use_error=' . $use_error.
				($login_failed ? '&'. $use_error . '=' . $login_failed : '');
			$debug && warn('Need a login, with redirect going to ' . $redirect);
			$req->custom_response(REDIRECT, $redirect);
			return REDIRECT;
		} else {
			die "Must define LoginFormURL in Apache Config to use Apache::Wyrd::Services::Auth";
		}
	}
}

sub revive {
	my ($self, $user_info) = @_;
	my $user = undef;
	my $user_object = $self->{'user_object'};
	my $debug =  $self->{'debug'};
	eval "use $user_object";
	$debug && $@ && die("$user_object failed to be initialized: $@");
	#TO DO: place this into a safe of some sort
	eval('$user = ' . $user_object . '->revive($user_info)');
	return $user;

}

sub initialize {
	my ($self, $init) = @_;
	my $user = undef;
	my $username=$init->{'username'};
	my $password=$init->{'password'};
	my $user_object = $self->{'user_object'};
	eval "use $user_object;";
	eval('$user = ' . $user_object . '->new({username => $username, password => $password})');
	die $@ if ($@);
	return $user;
}

sub generate_ticket {
	my ($self) = @_;

	my $debug = $self->{'debug'};
	my $ticketfile = $self->{'ticketfile'};

	# 1) Generate a random 56-byte key.  NB: values are 1-255, not 0-255 as it will be stored in A DB file, so null byte terminates string in C.  Avoid it.
	my $key = '';
	for (my $i=0; $i<56; $i++) {
		$key .= chr(int(rand(255)) + 1);
	}
	
	# 2) Make a ticket serial number by using sha256
	my $ticket = sha256_hex($key);
	$key = Apache::Util::escape_uri($key);

	$debug && warn ("Storing key under ID $ticket");
	my $pad = Apache::Wyrd::Services::TicketPad->new($ticketfile);
	$pad->add_ticket($ticket, $key);

	return ($key, $ticket);
}

sub decrypt_challenge {
	my ($self, $challenge) = @_;

	my $debug = $self->{'debug'};
	my $ticketfile = $self->{'ticketfile'};

	#separate the ticket from the data
	my ($ticket, $data) = split ':', $challenge;

	#find the key for decrypting the data;
	$debug && warn('finding ' . $ticket);
	my $pad = Apache::Wyrd::Services::TicketPad->new($ticketfile);
	my $key = $pad->find($ticket);

	$debug && warn "found key $key";
	$key = Apache::Util::unescape_uri($key);
	my $cr = Apache::Wyrd::Services::CodeRing->new({key => $key});
	my ($username, $password) = split ("\t", ${$cr->decrypt(\$data)});

	return ($username, $password);
}

sub authorize_user {
	my ($self, $req, $user) = @_;

	my $debug = $self->{'debug'};
	my $cr = Apache::Wyrd::Services::CodeRing->new;
	my $auth_path = $req->dir_config('AuthPath');

	$debug && warn ("User has been authenticated. Authorizing User and creating Cookie");

	my $user_info = $user->store;
	$debug && warn ("User info is:\n$user_info");
	$req->notes->add('User' => $user_info);
	$user_info = $cr->encrypt(\$user_info);
	my $ip_addr = $req->connection->remote_ip;
	$ip_addr = $cr->encrypt(\$ip_addr);
	my $cookie = Apache::Wyrd::Cookie->new(
		$req,
		-name=>'auth_cookie',
		-value=>$$ip_addr . ':' . $$user_info,
		-domain=>$req->hostname,
		-path=> ($auth_path || '/')
	);
	$cookie->bake;
}

=pod

=back

=head2 PERLSETVAR DIRECTIVES

=over

=item LoginFormURL

Form URL (required)

=item UserObject

Module for the User object which performs authorization (required).  See
the C<Apache::Wyrd::User> module.

=item NoCookieURL

URL to send cookie-less browsers to (required)

=item ReturnError

Send error back to the Login URL via the given variable (optional)

=item LSKeyURL

Login Server URL for key (required when a Login Server is being used)

=item LSLoginURL

Login Server URL for login (when a Login Server is being used)

=item LSForce

Force the use of a Login Server on an HTTPS connection rather than attempting
to authenticate directly through the username and password CGI variables.

=item LSDownURL

URL to redirect to when Login Server is down. (optional, but
recommended)

=item Debug

Dump debugging information to the Error Log (0 for default no, 1 for yes). 
Note that if the log is not secure, this may compromise the users'
credentials.

=item TieAddr

Require a fixed client address for the session (less compatible with some
ISPs) (0 for default no, 1 for yes)

=item UserObject

The (text) name of the perl object which represents the user for this
authentication (see C<Apache::Wyrd::User>).

=back

=head1 BUGS/CAVEATS/RESERVED METHODS

As with many such schemes, man-in-the-middle attacks are always possible, if
rather problematic to implement.  Additionally, unless TieAddr is set, a
"stolen cookie", i.e. one obtained via packet sniffing or similar technique
can be used to gain access until the server's key is regenerated on server
restart.

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item Apache::Wyrd::Interfaces::GetUser

Methods for getting User/authorization information from the
authorization cookie for use when no Auth method is in the handler
stack.

=item Apache::Wyrd::Services::Key

Shared-memory encryption key and cypher.

=item Apache::Wyrd::Services::LoginServer

Perl Handler for login services.

=back

=head1 LICENSE

Copyright 2002-2007 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

1;
