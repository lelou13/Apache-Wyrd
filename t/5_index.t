#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(uninitialized);
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw(GET_BODY GET_OK);
use Cwd;

my $directory = getcwd;
$directory =~ s#(/t/?)*$#/t#;

my $count = &count;
eval {use Apache::Wyrd::Services::Index};
$count = 0 if ($@);

print "1..$count\n";

unless ($count) {
	exit 0;
}

my $index = undef;

print "not " unless (GET_OK '/13.html');
print "ok 1 - Index creation\n";

eval {$index = Apache::Wyrd::Services::Index->new({
	file => "$directory/data/testindex.db",
	attributes => [qw(regular map)],
	maps => [qw(map)],
	strict => 1
})};

print "not " if ($@);
print "ok 2 - Index tie\n";

print "not " unless (GET_OK '/13.html');
print "ok 3 - Indexable objects\n";

my $text = GET_BODY '/13.html';

my $found = $index->entry_by_name('one');

print "not " if (ref($found) ne 'HASH');
print "ok 4 - Lookup\n";

print "not " if ($found->{description} ne 'first');
print "ok 5 - Find by name\n";

print "not " if ($found->{regular} ne 'regular1');
print "ok 6 - Custom regular attribute\n";

my @found = $index->word_search('one');

print "not " if (@found != 2);
print "ok 7 - Find by word\n";

@found = $index->word_search('four', 'map');

print "not " if (@found != 2);
print "ok 8 - Find by custom map\n";

@found = $index->word_search('+one');

print "not " if (@found != 2);
print "ok 9 - Exclusive word search\n";

@found = $index->word_search('+one +more');

print "not " if (@found != 1);
print "ok 10 - Exclusive word search combined 1\n";

@found = $index->word_search('+one -more');

print "not " if (@found != 1);
print "ok 11 - Exclusive word search combined 2\n";

@found = $index->word_search('-one -more');

print "not " if (@found != 2);
print "ok 12 - Exclusive word search combined 3\n";

@found = $index->word_search('-one -more');

print "not " if (@found != 2);
print "ok 13 - Exclusive word search combined 4\n";

@found = $index->parsed_search('one AND more');

print "not " if (@found != 1);
print "ok 14 - Exclusive logical search 1\n";

@found = $index->parsed_search('one NOT more');

print "not " if (@found != 1);
print "ok 15 - Exclusive logical search 2\n";

@found = $index->parsed_search('this AND (another OR more)');

print "not " if (@found != 3);
print "ok 16 - Exclusive logical search 3\n";

@found = $index->parsed_search('NOT one NOT more');

print "not " if (@found != 2);
print "ok 17 - Exclusive logical search 4\n";

$index->delete_index;
$found = $index->get_entry('one');

print "not " if ($found->{description});
print "ok 18 - Zero index\n";

sub count {18}
