require 5.6.1;
use ExtUtils::MakeMaker;
use Apache::TestMM qw(test clean);
use lib qw(../blib/lib lib );
use Cwd;

push @ARGV, '-maxclients', '2';

Apache::TestMM::filter_args();
Apache::TestMM::generate_script('t/TEST');

my $blowfish = 'Crypt::Blowfish';

eval ('use Crypt::Blowfish');
if ($@) {
	eval('use Crypt::Blowfish_PP');
	$blowfish .= '_PP' unless ($@);
}

WriteMakefile(
	'NAME'		=> 'Apache::Wyrd',
	'VERSION_FROM'	=> 'Wyrd.pm',
	'PREREQ_PM'		=> {
		Apache					=>	1.26,
		Apache::Constants		=>	1.09,
		Apache::Request			=>	1.1,
		Apache::Cookie			=>	1.1,
		Apache::URI				=>	1,
		Apache::Test			=>	1.08,
		Apache::Util			=>	1.02,
		BerkeleyDB				=>	.23,
		DBI						=>	1.2,
		Digest::MD5				=>	2.13,
		Exporter				=>	5.562,
		HTML::Entities			=>	1.22,
		HTTP::Request::Common	=>	1.19,
		LWP::UserAgent			=>	2.001,
		MIME::Base64			=>	2.12,
		$blowfish				=>	1
	},
	AUTHOR			=> 'barry king <wyrd@nospam.wyrdwright.com>',
	clean			=> {
			FILES	=> q(t/TEST t/data/testindex.db t/data/ticketbook.db t/data/cookies.txt t/logs t/conf/modperl_startup.pl t/htdocs/index.html)
	}
);

