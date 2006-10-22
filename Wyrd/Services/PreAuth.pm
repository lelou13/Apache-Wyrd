use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Services::PreAuth;
our $VERSION = '0.94';
use base qw(Apache::Wyrd::Services::Auth);
use Apache::Constants qw(OK);
use LWP::UserAgent;
use HTTP::Request::Common;

sub handler : method {
	my ($class, $req) = @_;
	my $self = {};
	bless ($self, $class);
	my $apr = Apache::Wyrd::Request->instance($req);
	$self->{'ticketfile'} = $req->dir_config('KeyDBFile') || '/tmp/keyfile';
	my $debug = $req->dir_config('Debug');
	my $scheme = 'http';
	$scheme = 'https' if ($req->server->port == 443);
	my $port = '';
	$port = ':' . $req->server->port unless ($req->server->port == 80);

	#Get an encryption key and a ticket number
	my ($key, $ticket) = $self->generate_ticket;

	#Send that pair to the Login Server
	my $key_url = $req->dir_config('LSKeyURL') || $apr->param('url')
		|| die "Either provide the url param or define the LSKeyURL directory configuration";
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

	if ($status !~ /200|OK/) {
		my $failed_url = $req->dir_config('LSDownURL');
		$failed_url = $scheme . '://' . $req->hostname . $port . $failed_url unless ($failed_url =~ /^http/i);
		print $failed_url;
	} else {
		print $ticket;
	}
	return OK;
}

1;