require 5.6.1;
use ExtUtils::MakeMaker;
use lib qw(../blib/lib lib );
use Cwd;

my $this_version = '0.86';
push @ARGV, '-maxclients', '2';

my $have_atest = 1;
my $atest_version = 0;
eval {'use Apache::Test qw(VERSION)'};
unless ($@) {
	use Apache::Test;
	$atest_version = $Apache::Test::VERSION;
}

eval ('use Apache::TestMM qw(test clean)') if ($atest_version >= 1.08);
if ($@ or ($atest_version < 1.08)) {
	$have_atest = 0;
	print <<__MSG__;

The test suite for this module requires Apache::Test version > 1.08,
which is apparently not available.  It is highly recommended that you
run the test suite, but it is not absolutely required.  If you choose to
continue, you may install Apache::Wyrd, but it may be unuseable.  Do you
want to continue?

__MSG__
	my $ok = prompt('Continue (y/n)?', 'n');
	if (lc($ok) ne 'y') {
		print "OK, aborting...\n\n";
		exit 0;
	} else {
		print <<__MSG__;

OK. However, if you run into problems, please install Apache::Test and
run the test suite (make test) before contacting the author for support.

__MSG__
		sleep 5;
		open (BLOCKER, '> t/no_test');
		print BLOCKER 'this file is here to block testing.  remove it if you want to allow the tests';
		close (BLOCKER);
	}
} else {
	#for test re-runs
	-f 't/no_test' && unlink('t/no_test');
}

my $blowfish = 'Crypt::Blowfish';
print "\nWyrds require Blowfish Crypto, which comes in xs or pure perl.\n";
print "Checking for (faster, preferred) xs version...\n";
eval ('use Crypt::Blowfish');
if ($@) {
	print "Falling back on pure perl version.\n";
	eval('use Crypt::Blowfish_PP');
	$blowfish .= '_PP' unless ($@);
	print "No Blowfish Crypto found!\n" if ($@);
} else {
	print "Good. You have Crypt::Blowfish\n";
}

my $cgi = 'Apache::Request';
print "\nWyrds require a CGI interpreter, either libapreq or CGI.\n";
print "Checking for (faster, preferred) libapreq...\n";
eval ('use Apache::Request');
if ($@) {
	print "Falling back on CGI.\n";
	eval('use CGI');
	$cgi = 'CGI' unless ($@);
	print "But I can't find either!\n" if ($@);
} else {
	print "Good. You have Apache::Request\n";
}

my $cookie = 'Apache::Cookie';
print "\nWyrds require a Cookie module.\n";
print "Checking for (faster, preferred) Apache::Cookie...\n";
eval ('use Apache::Cookie');
if ($@) {
	print "Falling back on CGI::Cookie.\n";
	eval('use CGI::Cookie');
	$cookie = 'CGI::Cookie' unless ($@);
	print "But I can't find either!\n" if ($@);
} else {
	print "Good. You have Apache::Cookie\n";
}

if ($have_atest) {
	print "\nOK... Generating Makefile and TEST...\n";
	Apache::TestMM::filter_args();
	Apache::TestMM::generate_script('t/TEST');
} else {
	use Config;
	print "\nOK... Generating Makefile...\n";
};

WriteMakefile(
	'NAME'		=> 'Apache::Wyrd',
	'VERSION_FROM'	=> 'Wyrd.pm',
	'PREREQ_FATAL'	=> 1,
	'PREREQ_PM'		=> {
		Apache					=>	1.26,
		Apache::Constants		=>	'',
		Apache::URI				=>	'',
		Apache::Util			=>	'',
		BerkeleyDB				=>	.23,
		Class::Singleton		=>	'',
		DBI						=>	'',
		Digest::MD5				=>	'',
		HTML::Entities			=>	'',
		HTTP::Request::Common	=>	'',
		LWP::UserAgent			=>	'',
		MIME::Base64			=>	'',
		XML::Dumper				=>	.67,
		$blowfish				=>	'',
		$cgi					=>	'',
		$cookie					=>	''
	},
	AUTHOR			=> 'barry king <wyrd@nospam.wyrdwright.com>',
	clean			=> {
			FILES	=> q(t/TEST t/data/testindex.db t/data/ticketbook.db t/data/cookies.txt t/logs t/conf/modperl_startup.pl t/htdocs/index.html)
	}
);

my $perl_version = $];
my $os = $^O;
my $mod_perl_version = $Apache::VERSION;
my $bdb = $BerkeleyDB::db_version;
my $error = 0;
my $ua = undef;
my $url = 'http://www.wyrdwright.com/wyrd/wyrd_counter.html';

eval('use LWP::UserAgent');
$error ||= $@;
eval('use HTTP::Request::Common');
$error ||= $@;
eval('$ua = LWP::UserAgent->new');
$error ||= $@;
eval('$ua->timeout(20)');
$error ||= $@;

exit 0 if ($error);

print <<__MSG__;

==================
  SURVEY REQUEST
==================

The author of Apache::Wyrd would like to know what version of perl and
the operating system you are using to better support your system. The
information would be sent by HTTP to the www.wyrdwright.com site which
will log the time and the source of the information (IP address).  NO
OTHER SYSTEM INFORMATION WILL BE SENT THAN THE FOLLOWING:

	Apache::Wyrd version: $this_version
	perl version: $perl_version
	Operating System: $os
	mod_perl version: $mod_perl_version
	Berkeley DB version: $bdb

May I send this information to the Author?

__MSG__

my $ok = prompt('Send info (y/n)?', 'y');
if (lc($ok) ne 'y') {
	print "OK, I won't send it...\n\n";
	exit 0;
} else {
	print "Thanks.  Sending...\n\n";
	use LWP::UserAgent;
	use HTTP::Request::Common;
	$ua = LWP::UserAgent->new;
	$ua->timeout(20);
	$ua->request(POST $url,
		[
			perl		=>	$perl_version,
			mod_perl	=>	$mod_perl_version,
			os			=>	$os,
			bdb			=>	$bdb,
			wyrds		=>	$this_version
		]
	);
}
