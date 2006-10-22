use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Site::Login;
use base qw(Apache::Wyrd::Interfaces::Setter Apache::Wyrd);
use Apache::Constants qw(OK);
use MIME::Base64;
use LWP::UserAgent;
use HTTP::Request::Common;
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub _format_output {
	my ($self) = @_;
	my $req = $self->dbl->req;

	#first check to see if there is a pending login.
	my $challenge_param = $self->{'challenge_param'} = $req->dir_config('ChallengeParam') || 'challenge';
	if ($self->dbl->param($challenge_param)) {
		$self->abort('request authorization');
	}

	my %params = ();
	my $use_error = $params{'use_error'} = $self->{'use_error'} = $req->dir_config('ReturnError') || 'err_message';

	#then check for a login error;
	my $error_message = $params{'error'} = $self->dbl->param($use_error);
	if ($error_message) {
		$self->_data($self->_set(\%params, $self->error));
		return;
	}

	#then check for a logged-in user
	my $username = $params{'username'} = $self->dbl->user->{'username'};
	if ($username) {
		map {$params{$_} = $self->dbl->user->{$_}} qw(username password salutation firstname lastname organisation);
		$self->_data($self->_set(\%params, $self->username));
		return;
	}

	#Not logged in at all, set up a preauth login
	$params{'debug'} = $self->{'debug'} = $req->dir_config('Debug') || 0;
	$params{'ticketfile'} = $self->{'ticketfile'} = $req->dir_config('KeyDBFile') || '/tmp/keyfile';
	$params{'challenge_param'} = $self->{'challenge_param'} = $req->dir_config('ChallengeParam') || 'challenge';
	$params{'key_url'} = $self->{'key_url'} = $req->dir_config('LSKeyURL') || die "Must define LSKeyURL";
	$params{'preauth_url'} = $self->{'preauth_url'} = $req->dir_config('PreAuthURL') || die "Must define PreAuthURL";
	$params{'on_success'} = $self->{'on_success'} = encode_base64($self->dbl->self_url);
	$params{'data'} = $self->{'login'};

	$self->_data($self->_set(\%params, $self->_form_template));
	return;
}

sub _form_template {
	my ($self) = @_;
	return $self->{'form'} || q(
<form action="$:key_url" method="post">
<input type="hidden" name="ticket" value="$:preauth_url">
<input type="hidden" name="on_success" value="$:on_success">
<input type="hidden" name="use_error" value="$:use_error">
$:data
</form>
);
}

1;