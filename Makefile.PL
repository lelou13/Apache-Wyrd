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
		Apache::Constants		=>	'',
		Apache::Request			=>	'',
		Apache::Cookie			=>	'',
		Apache::URI				=>	'',
		Apache::Test			=>	1.08,
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
		$blowfish				=>	''
	},
	AUTHOR			=> 'barry king <wyrd@nospam.wyrdwright.com>',
	clean			=> {
			FILES	=> q(t/TEST t/data/testindex.db t/data/ticketbook.db t/data/cookies.txt t/logs t/conf/modperl_startup.pl t/htdocs/index.html)
	}
);

