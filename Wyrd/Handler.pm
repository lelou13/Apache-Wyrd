use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Handler;
our $VERSION = '0.8';
use Apache::Wyrd::DBL;
use Apache::Wyrd;
use Apache::Wyrd::Services::SAK qw(slurp_file);
use Apache;
use Apache::Constants qw(:common);

=pod

=head1 NAME

Apache::Wyrd::Handler

=head1 SYNOPSIS

	PerlWarn off
	<Directory /var/www/sites/BASENAME>
		SetHandler perl-script
		PerlHandler BASENAME::Handler
	</Directory>

=head1 DESCRIPTION

Handler for Apache::Wyrd documents.  For more information on mod_perl and
handlers, see L<http://perl.apache.org/docs/index.html>

This module has been developed for and only been tested in Apache E<lt> 2.0 /
mod_perl E<lt> 1.99.  In this environment, the SYNOPSIS shows a typical set of
appropriate Apache directives.  Global Perl warnings are turned off, as they are
more granularly handled within the package.  Note that the Handler that is usedour $VERSION = '0.8';
is an B<instance> of this handler.  It is named, in this example,
C<BASNAME::Handler> and is found in a BASNAME directory which in @INC of a local
mod_perl installation.  Traditionally, this is in C<E<lt>apache configuration
directoryE<gt>/lib/perl/>.  If the perl module BASENAME::Handler has a C<use
base qw(Apache::Wyrd::Handler)> pragma, the C<handler> method should properly
determine the base class for the BASENAME set of Wyrds and the handler should
interpret only those tags beginning E<lt>BASENAME::...  A rudimentary sample of
this usage is available in the t/lib directory of this package and is used forour $VERSION = '0.8';
testing.

This way, several sites using Wyrds can be built, each subclassing Apache::Wyrd
objects in their own idiom without interfering in the interpretation of the same
objects in another BASENAME class.  (However, nothing prevents a second BASENAME
from including the first BASENAME in its C<use base> pragma array).  This is a
feature(tm) of Apache::Wyrd and is intended to promote code re-use.

The Handler also dumps out the error log, if needed from the DBL, where
it accumulates from it's own internal calls and calls by Wyrds to the
error-level functions (_warn, _error, etc.).  If the "init" hashref has
a non-null key called "error_page", this log will be reverse-dumped in a
standard-looking error page with a backtrace of events.

=head2 METHODS

=over

=item new

Accept and bless a new object.  Provided for tradition's sake, since the handler
method does the real work.

=cut

sub new {
	my ($class, $data) = @_;
	bless $data, $class;
	return $data;
}

=pod

=item handler

Handle the request.  This handler uses the 2 argument function prototype so that
it can be instantiated in another name-space.

In the example Apache directive above, the arguments supplied by the Apache
directive give it the class name "BASENAME".  It uses this BASENAME to determine
what is the base class of all Wyrds it handles.  Consequently, it will only
parse Wyrds which begin with E<lt>BASENAME::...

The handler assembles the Apache request object itself, the initialization hash
for the generation of Apache::Wyrd objects, and the globals used by Apache::DBL.
 It then calls C<process> and C<respond> in sequence.  If all goes well, the
'output' attribute has been set by the response method, and this is returned
with the appropriate headers set.

=cut

sub handler ($$) {
	my ($class, $req) = @_;
	unless ($class =~ /^([a-zA-Z][a-zA-Z0-9_:]*)::Handler/) {
		die "Must instantiate Apache::Wyrd::Handler as a XXXXX::Handler Object  where XXXXX is the base class of the Wyrd-derived objects.";
	}
	my $client = $1;
	my $self = new($class, {
		'req' => $req,
		'client' => $client,
		'output' => ''
	});
	$self->{'init'} = $self->init;
	$self->{'init'}->{'globals'} = $self->globals;
	my $response = $self->get_file;
	return $response if ($response);
	$response = $self->process;
	return $response if ($response);
	$response = $self->respond;
	if ($response eq OK) {
		$self->add_headers;
		$req->send_http_header('text/html');
		$req->print($self->{'output'});
	}
	return $response;
}

=pod

=item add_headers

Called by handler on a successful responses from C<process> and C<respond>. Adds
some standard headers to the response or can be overridden.  By default, it adds
headers to help with compatibility with AOL's famously broken proxies and other
similar problems.

=cut

sub add_headers {
	my ($self) = @_;
	my $req = $self->{'req'};
	$req->no_cache(1);
	$req->headers_out->set('Vary', '*');
	return undef;
}

=pod

=item get_file

Based on the request, locates the file to be used and sets the file attribute to
that path.  It declines non-html (*.html) files and passes the mtime and size of
the file to the init hashref for use by the Apache::Wyrd object.

=cut

sub get_file {
	my ($self) = @_;
	my $file = $self->{'req'}->filename;
	$file =~ s#/$##;
	if (-d $file){
		$file .= '/index.html';
		$self->{'send_header'} = 1;
	}
	return DECLINED unless ($file =~ /\.html?$/);
	unless (-r _) {
		if (-f _) {
			return FORBIDDEN
		} else {
			return NOT_FOUND
		}
	}
	$self->{'file'} = $file;
	my @stats = stat _;
	$self->{'init'}->{'mtime'} = $stats[9];
	$self->{'init'}->{'size'} = $stats[7];
	return undef;
}


=pod

=item globals

defines the hashref which will be kept by the DBL object.  Empty by default.

=cut

sub globals {
	return {};
}

=pod

=item init

defines the hashref which will be used to initialize the Apache::Wyrd objects. 
It B<must> return the request object under the key 'req', which is stored under
the C<Apache::Wyrd::Handler> attribute 'req' by the C<handler> method.  Any
other keys are optional.

By default, if the hash key 'error_page' is set (non-null), the installation
will use an error page with a debugging log.  See the C<errorpage> method.

=cut

sub init {
	my ($self) = @_;
	return {
		req => $self->{'req'}
	};
}


=pod

=item process

"Hook" method for introducing other handling checks to the request.  It should
return an Apache::Constants value if it wants to override the response of the
C<respond> method.  If it does this override, then it is responsible for setting
it's own headers.

=cut

sub process {
	my ($self) = @_;
	return undef;
};

=pod

=item respond

Does the work of setting up the found page as an Apache::Wyrd object and calling
it's C<output> method.  Should probably not be overridden, unless there are
tweaks that cannot be accomplished in C<add_headers> and C<process>.

=cut

sub respond {
	my ($self) = @_;
	my $client = $self->{'client'};
	my $dbl_create = 'Apache::Wyrd::DBL->new($self->{"init"});';
	my $wo_create = 'Apache::Wyrd->new($dbl, {_data => $$data});';
	if ($self->{'client'}) {
		eval ("use " . $client . "::DBL");
		die ("$@:\nA base class $client\::DBL needs to be defined before using Apache::Wyrd") if ($@);
		eval ("use $client\::Wyrd");
		die ("$@\:\nA base class $client\::Wyrd needs to be defined before using Apache::Wyrd") if ($@);
		$dbl_create =~ s/^Apache::Wyrd/$self->{client}/;
		$wo_create =~ s/^Apache/$self->{client}/;
	}
	my ($dbl, $object) = ();
	eval("\$dbl=$dbl_create");
	die ($@) if ($@);
	my $data = slurp_file($self->{'file'});
	eval("\$object = $wo_create");
	my $response = OK;
	if ($self->{'init'}->{'error_page'}) {
		my $output = undef;
		eval{$output = $object->output()};
		if ($@ or not($output)) {
			my $log = undef;
			$log = ${$dbl->dump_log} if ($dbl->debug);
			$self->{'req'}->custom_response(SERVER_ERROR, $self->errorpage($@, $log));
			$response = SERVER_ERROR;
		}
		#$dbl->get_response && return $dbl->get_response;
		$self->{'output'} = $output;
	} else {
		#$dbl->get_response && return $dbl->get_response;
		$self->{'output'} = $object->output();
	}
	$dbl->{'logfile'} && $dbl->close_logfile;
	$dbl->{'dbh'} && $dbl->close_db;
	return $response;
}

=pod

=item req

return the Apache request object.  This object has been initialized in
C<handler>

=cut

sub req {
	my ($self) = @_;
	return $self->{'req'};
}

=pod

=item errorpage

Simply a formatting method.  Given the error and the log in scalar form, outputs
an Error Page with "Internal Server Error" at the top.  Called by C<respond>
when the debugging flags are on.

=cut

sub errorpage {
	my ($self, $error, $log) = @_;
	return <<__PAGE_END__;
<H1>500: Internal Server Error</H1>
<HR>
Specific Error: $@
<HR>
$log
__PAGE_END__
}

=pod

=back

=head1 BUGS/CAVEATS

=head2 FREE SOFTWARE

Standard warning about GNU GPL software.  See LICENSE under the documentation
for Apache::Wyrd

=head2 UNSTABLE

The basic Wyrd API should remain stable barring unforseen events, but until some
time after initial release, this software should be considered unstable.

This software has only tested under Linux and Darwin, but should work for any
*nix-style system.  This software is not intended for use on windows or other
easily-damaged glass objects.

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item Apache::Wyrd

General-purpose HTML-embeddable perl object

=item Apache::Wyrd::DBL

"Das Blinkenlights", a more-or-less mandatory module for centralization of calls
to the Apache process or an associated DBI-type database.

=item The Eagle Book

"Writing Apache Modules iwth Perl and C" by Stein E<amp> MacEachern,  Copyright
1999 O'Reilly E<amp> Associates, Inc., ISBN: 1-56592-567-X.

=back

=head1 LICENSE

Copyright 2002-2004 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

1;