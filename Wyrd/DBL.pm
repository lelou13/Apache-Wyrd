use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::DBL;
our $VERSION = '0.87';
use DBI;
use Apache;
use Apache::Wyrd::Request;
use Apache::Wyrd::User;
use Apache::URI;

=pod

=head1 NAME

Apache::Wyrd::DBL - Object for Wyrds to access "Das Blinkenlights" (Apache internals, etc.)

=head1 SYNOPSIS

	my $hostname = $wyrd->dbl->req->hostname;
	my $database_handle = $wyrd->dbl->dbh;
	my $value = $wyrd->dbl->param('value');

=head1 DESCRIPTION

"Das Blinkenlights" is a convenient placeholder for all session information a
wyrd might need in order to do work.  It holds references to the session's
current apreq, DBI, and Apache objects, as well as the current session log and
other vital information.  It is meant to be called from within an Apache::Wyrd
object through it's C<dbl> method, as in the SYNOPSIS.

Debugging is always turned on if port 81 is used.  Note that apache must be set
up to listen at this port as well.  See the Listen and BindAddress Apache directives.

=head1 METHODS

=over

=item (DBL) C<new> (hashref, hashref)

initialize and return the DBL with a set of startup params and a set of global
variables (for the WO to access) in the form of two hashrefs.  The first hashref
should include at least the 'req' key, which is an Apache request object.

The startup params can have several keys set.  These may be:

=over

=item apr

the param/cookie subsystem (CGI or Apache::Request object initialized by a Apache::Wyrd::Request object);

=item dba

database application.  Should be the name of a DBI::DBD driver.

=item database

database name (to connect to)

=item db_password

database password

=item db_username

database user name

=item debug

debugging level

=item globals

pointer to globals hashref

=item req (B<required>)

the request itself (Apache request object)

=item self_url

full URL of current request (depreciated)

=item strict

should strict procedures be followed (not used by default)

=item user

the current user (not used by default)

=back

=cut

sub new {
	my ($class, $init) = @_;
	if ((ref($init) ne 'HASH') and $init) {
		complain("invalid init data given to Das Blinkenlights -- Ignored");
		$init = {};
	}
	$ENV{PATH} = undef unless ($$init{flags} =~ /allow_unsafe_path/);
	if ((ref($$init{'globals'}) ne 'HASH') and $$init{'globals'}) {
		complain("invalid global data given to Das Blinkenlights -- Ignored");
		$$init{'globals'} = {};
	}
	my @standard_params = qw(
		dba
		database
		db_password
		db_username
		debug
		globals
		logfile
		mtime
		req
		self_path
		size
		strict
		user
	);
	my $data = {
		dbl_log		=>	[],
		dbh_ok		=>	0,
		dbh			=>	undef,
		response	=>	undef
	};
	foreach my $param (@standard_params) {
		$$data{$param} = ($$init{$param} || undef);
	}
	bless $data, $class;
	if (UNIVERSAL::isa($$init{'req'}, 'Apache')) {
		$data->{'req'} = $$init{'req'};
		$data->{'mod_perl'} = 1;
		my $server = $$init{'req'}->server;
		$data->{'debug'} = 1 if ($server->port == 81);
		$data->{'self_path'} ||= $$init{'req'}->parsed_uri->rpath;
		my $apr = Apache::Wyrd::Request->instance($$init{'req'});
		$data->{'apr'} = $apr;
	};
	if (UNIVERSAL::isa($$init{'database'}, 'DBI::db')) {
		if ($$init{'database'}->can('ping') && $$init{'database'}->ping) {
			$data->{'dbh'} = $$init{'database'};
			$data->{'dbh_ok'} = 1;
		} else {
			$data->log_bug('DBI-type Database apparently passed to Das Blinkenlights, but was not valid')
		}
	}
	return $data;
}

=pod

=item verify_dbl_compatibility

Used by Apache::Wyrd to confirm it's been passed the right sort of object for a
DBL.

=cut

sub verify_dbl_compatibility {
	return 1;
}

=item (scalar) C<strict> (void)

Optional read-only method for "strict" conditions.  Not used by the default install.

=cut

sub strict {
	my ($self) = @_;
	return $self->{'strict'};
}

=pod

=item (scalar) C<debug> (void)

Optional read-only method for "debug" conditions.  Not used by the default install.

=cut

sub debug {
	my ($self) = @_;
	return $self->{'debug'};
}

=pod

=item (void) C<log_bug> (scalar)

insert a debugging message in the session log.

=cut

sub log_bug {
	return unless (ref($_[0]) and ($_[0]->{'debug'}));
	my ($self, $value) = @_;
	my @caller = caller();
	$caller[0] =~ s/.+://;
	$caller[2] =~ s/.+://;
	my $id = "($caller[0]:$caller[2])";
	$value = join(':', $id, $value);
	push @{$self->{'dbl_log'}}, $value;
	warn $value;
}

=pod

=item (void) C<set_logfile> (filehandle typeglob)

give DBL a file in which to store it's events. The filehandle is then kept in
the logfile attribute.

=cut

sub set_logfile {
	my ($self, $fh) = @_;
	$| = 1;
	$self->{'logfile'} = $fh;
}

=pod

=item (void) C<close_logfile> (void)

flush logfile to disk.  Necessary in mod_perl situation, it seems.

=cut

sub close_logfile {
	my ($self, $fh) = @_;
	$self->{'logfile'} = $fh;
	close ($fh) if ($fh);
	eval("system('/bin/sync')");
}

=pod

=item (void) C<log_event> (scalar)

same as log_bug, but don't send the output to STDERR. Instead, make it HTML escaped and store it for later dumping.

=cut

sub log_event {
	my ($self, $value) = @_;
	$self->{'dbl_log'} = [@{$self->{'dbl_log'}}, $value];
	my $fh = $self->{'logfile'};
	if ($fh) {
		print $fh (Apache::Util::escape_html($value) . "<br>\n");
	}
}

=pod

=item (hashref) C<globals> (void)

return a reference to the globals hashref  Has a useful debugging message on unfound globals.

=cut

sub globals {
	my ($self) = @_;
	return $self->{'globals'};
}

=pod

=item (scalar) C<mtime> (void)

the modification time of the file currently being served.  Derived from
Apache::Wyrd::Handler, by default compatible with the C<stat()> builtin
function.

=cut

sub mtime {
	my ($self) = @_;
	return $self->{'mtime'};
}

=item (scalar) C<size> (void)

the file size of the file currently being served.  Derived from
Apache::Wyrd::Handler, by default compatible with the C<stat()> builtin
function.

=cut

sub size {
	my ($self) = @_;
	return $self->{'size'};
}

=pod

=item (variable) C<get_global> (scalar)

retrieve a global by name.

=cut

sub get_global {
	my ($self, $name) = @_;
	unless (exists($self->{'globals'}->{$name})) {
		$self->log_bug("Asked to get global value $name which doesn't exist. Returning undef.");
		return undef;
	}
	return $self->{'globals'}->{$name};
}

=pod

=item (void) set_global(scalar, scalar)

find the global by name and set it.  Has a helpful debugging message on
undefined globals.

=cut

sub set_global {
	my ($self, $name, $value) = @_;
	unless (exists($self->{'globals'}->{$name})) {
		$self->log_bug("Asked to set global value $name which doesn't exist.  Creating it and setting it.");
	}
	$self->{'globals'}->{$name} = $value;
	return undef;
}

=pod

=item (scalar) C<get_response> (void)

Return the response.  Should be an Apache::Constants response code.

=cut

sub get_response {
	my ($self) = @_;
	return $self->{'response'};
}

=pod

=item (scalar) C<set_response> (void)

Set the response.  Should be an Apache::Constants response code.

=cut

sub set_response {
	my ($self, $response) = @_;
	$self->{'response'} = $response;
	return undef;
}

=pod

=item (DBI::DBD::handle) C<dbh> (void)

Database handle object.  Will initialize a database connection on the first
call, so as to avoid opening a database connection if the Wyrds in the file
being serviced don't require one.

=cut

sub dbh {
	my ($self) = shift;
	return $self->{'dbh'} if ($self->{'dbh_ok'});
	my $dba = $self->{'dba'};
	my $db = $self->{'database'};
	my $uname = $self->{'db_username'};
	my $pw = $self->{'db_password'};
	$self->_init_db($dba, $db, $uname, $pw);
	return $self->{'dbh'} if ($self->{'dbh_ok'});
	$self->log_bug('dbh was requested from DBL but no database could be initialized');
}

=pod

=item (Apache) C<req> (void)

Apache request object

=cut

sub req {
	my ($self) = shift;
	return $self->{'req'} if $self->{'mod_perl'};
	$self->log_bug('Apache Request Object requested from DBL, but none supplied at initialization.');
}

=pod

=item (scalar) C<user> (void)

Optional read-only method for an C<Apache::Wyrd::User> object.  Not used by the
default install.

=cut

sub user {
	my ($self) = shift;
	$self->log_bug("User not Defined") unless ($self->{'user'});
	return $self->{'user'};
}

=pod

=item (CGI/Apache::Request) C<apr> (void)

Apache::Wyrd::Request object (handle to either a CGI or Apache::Request object)

=cut

sub apr {
	my ($self) = shift;
	return $self->{'apr'};
}

=pod

=item (scalar/arrayref) C<param> ([scalar])

Like CGI->param().

=cut

sub param {
	my ($self, $value, $set) = @_;
	return $self->apr->param($value, $set) if (scalar(@_) > 2);
	return $self->apr->param($value) if ($value);
	return $self->apr->param;
}

=pod

=item (scalar) C<param_exists> (scalar)

Returns a non-null value if the CGI variable indicated by the scalar argument
was actually returned by the client.

=cut

sub param_exists {
	my ($self, $value) = @_;
	return grep {$_ eq $value} $self->apr->param;
}

=pod

=item (scalar) C<self_path> (void)

return the absolute path on the server to the file being served.

=cut

sub self_path {
	my ($self) = shift;
	return $self->{'self_path'} if $self->{'self_path'};
	$self->log_bug('self_path was requested from DBL, but could not be determined.');
}

=pod

=item (internal) C<_init_db> (scalar, scalar, scalar, scalar);

open the DB connection.  Accepts a database type, a database name, a username,
and a password.  Defaults to a mysql database.  Sets the dbh parameter and the
dbh_ok parameter if the database connection was successful.  Meant to be called
from C<dbh>.

=cut

sub _init_db {
	my ($self, $dba, $database, $db_uname, $db_passwd) = @_;
	my $dbh = undef;
	$dba ||= 'mysql';
	eval{$dbh = DBI->connect("DBI:$dba:$database", $db_uname, $db_passwd)};
	$self->log_bug("Database init failed: $@") if ($@);
	if (UNIVERSAL::isa($dbh, 'DBI::db') && $dbh->ping) {
		$self->{'dbh_ok'} = 1;
		$self->{'dbh'} = $dbh if ($self->{'dbh_ok'});
	}
	return undef;
}

=pod

=item (internal) C<close_db> (void);

close the C<dbh> connection if it was opened.

=cut

sub close_db {
	my ($self) = @_;
	return undef unless ($self->{'dbh_ok'});
	$self->{'dbh'}->finish;
	$self->{'dbh'}->disconnect;
	return undef;
}

=item (scalarref) C<dump_log> (void)

return a scalarref to a html-formatted dump of the log.

=cut

sub dump_log {
	require Apache::Util;
	my ($self) = @_;
	my $out ="<code><small><b>Log Backtrace:</b><br>";
	foreach my $i (reverse(@{$self->{'dbl_log'}})) {
		$out .= Apache::Util::escape_html($i) . "<br>\n";
	}
	$out .= "</small></code>";
	return \$out;
}

=head1 BUGS

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
