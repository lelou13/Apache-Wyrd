use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Services::SAK;
use Exporter;
use Apache::Util;

=pod

=head1 NAME

Apache::Wyrd::Services::SAK - Swiss Army Knife of common subs

=head1 SYNOPSIS

	use Apache::Wyrd::Services::SAK qw(:hashes spit_file);

=head1 DESCRIPTION

"Swiss Army Knife" of functions used in Apache::Wyrd.

I<(format: (returns) C<name> (arguments))> for regular functions.

I<(format: (returns) C<$wyrd-E<gt>name> (arguments))> for methods


=cut

our $VERSION = '0.84';
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	array_4_get
	attopts_template
	cgi_query
	commify
	data_clean
	do_query
	env_4_get
	lc_hash
	send_mail
	set_clause
	slurp_file
	sort_by_ikey
	sort_by_key
	spit_file
	token_hash
	token_parse
	uri_escape
	uniquify_by_key
	uniquify_by_ikey
);

our %EXPORT_TAGS = (
	all			=>	\@EXPORT_OK,
	db			=>	[qw(cgi_query do_query set_clause)],
	file		=>	[qw(slurp_file spit_file)],
	hash		=>	[qw(array_4_get data_clean env_4_get lc_hash sort_by_ikey sort_by_key token_hash token_parse uniquify_by_ikey uniquify_by_key uri_escape)],
	mail		=>	[qw(send_mail)],
	string		=>	[qw(commify)],
	tag			=>	[qw(attopts_template)]
);

=pod

=head2 DATABASE (:db)

Functions for working with databases.  Designed for use with a
combination of C<Apache::Wyrd::Interfaces::Setter> and the DBI-compatible
database stored in C<Apache::Wyrd::DBL>.

=over

=item (scalarref) C<$wyrd-E<gt>cgi_query>(scalar)

For turning strings with conditional variables into
querys parseable by the SQL interpreter.  First sets all conditional variables
in the query that are known, then set all unknown variables to NULL.  The query
is then executes and the DBI handle to the query is returned.

     $sh = $wyrd->cgi_query(
       'select names from people where name=$:name'
     );

	$wyrd->cgi_query('delete from people where id=$:id');

=cut

sub cgi_query {
	my ($self, $query) = @_;
	$query=Apache::Wyrd::Interfaces::Setter::_cgi_quote_set($self, $query);
	#replace unknown variables with null
	$query =~ s/\$:[a-zA-Z_0-9]+/NULL/g;
	my $sh = $self->dbl->dbh->prepare($query);
	$self->_info("Executing $query");
	$sh->execute;
	my $err = $sh->errstr;
	$self->_error("DB Error: $err") if ($err);
	return $sh;
}

=pod

=item (scalarref) C<$wyrd-E<gt>do_query>(scalar, [hashref])

Shorthand for creating and executing a DBI statement handle, returning the
handle.  If the optional hashref is supplied, it will perform a substitution in
the manner of C<Apache::Wyrd::Interfaces::Setter>. Unknown variables will be
made NULL for the query.  The query is then executes and the DBI handle to the
query is returned.

    $sh = $wyrd->do_query(
      'select names from people where name=$:name', {name => $name}
    );

    $wyrd->do_query('delete from people');

=cut

sub do_query {
	my ($self, $query, $hash) = @_;
	$query = Apache::Wyrd::Interfaces::Setter::_quote_set($self, $hash, $query) if (ref($hash) eq 'HASH');
	my $sh = $self->dbl->dbh->prepare($query);
	$self->_info("Executing $query");
	$sh->execute;
	my $err = $sh->errstr;
	$self->_error("DB Error: $err") if ($err);
	return $sh;
}

=pod

=item (scalar) set_clause(array)

Shorthand for setting up a query to be settable per
C<Apache::Wyrd::Interfaces::Setter> when given an array of column names.

=cut

sub set_clause {
	my @items = @_;
	@items = map {$_ . '=$:' . $_} @items;
	return join(", ", @items);
}

=pod

=back

=head2 FILES (:file)

Old-style file routines.

=over

=item (scalarref) C<slurp_file>(scalar)

get whole contents of a file.  The only argument is the whole path and
filename.  A scalarref to the contents of the file is returned.

=cut

sub slurp_file {
	my $file = shift;
	$file = open (FILE, $file);
	my $temp = $/;
	undef $/;
	$file = <FILE>;
	close (FILE);
	$/ = $temp;
	return \$file;
}

=pod

=item (scalar) C<spit_file>(scalar, scalar)

Opposite of C<slurp_file>.  The second argument is the contents of the file.
A positive response means the file was successfully written.

=cut

sub spit_file {
	my ($file, $contents) = @_;
	my $success = open (FILE, "> $file");
	print FILE $contents;
	close (FILE);
	return $success;
}

=pod

=back

=head2 HASHES (:hash)

Helpful routines for handling hashes.

=over

=item (scalar) C<array_4_get> (array)

create the query portion of a URL as a get request out of the current
CGI environment values for those elements.  When multiple values of an
element exist, they are appended.

=cut

sub array_4_get {
	my ($self, @array) = @_;
	my @param = ();
	foreach my $param (@array) {
		my @values = $self->dbl->param($param);
		foreach my $value (@values) {
			push @param, Apache::Wyrd::Services::SAK::uri_escape("$param=" . $value);
		}
	}
	return join('&', @param);
}

=pod

=item (scalar) C<data_clean>(scalar)

Shorthand for turning a string into "all lower case with underlines for
whitespace".

=cut

sub data_clean {
	my $data = shift;
	$data = lc($data);
	$data =~ s/\s+/_/gm;
	$data = Apache::Util::escape_uri($data);
	return $data;
}

=pod

=item (scalar) C<env_4_get>([array/hashref])

attempt to re-create the current CGI environment as the query portion of a GET
request.  Either a hash or an array of variables to ignore can be supplied.

=cut

sub env_4_get {
	my ($self, $ignore, @ignore) = @_;
	my %drop = ();
	my $out = undef;
	my @params = ();
	unless (ref($ignore) eq 'HASH') {
		foreach my $i ($ignore, @ignore) {
			$drop{$i} = 1;
		}
	} else {
		%drop = %$ignore;
	}
	foreach my $i ($self->dbl->param) {
		next if (exists($drop{$i}));
		push @params, Apache::Wyrd::Services::SAK::uri_escape("$i=" . $self->dbl->param($i));
	}
	return join('&', @params);
}

=pod

=item (hashref) C<data_clean>(hashref)

Shorthand for turning a hashref into a lower-case version of itself.  Will
randomly destroy one value of any key for which multiple keys of different case
are given.

=cut

sub lc_hash {
	my $hashref = shift;
	return {} if (ref($hashref) ne 'HASH');
	my %temp = ();
	foreach my $i (keys %$hashref) {
		$temp{lc($i)} = $$hashref{$i};
	}
	$hashref = \%temp;
	return $hashref;
}

=pod

=item (scalar, scalar) C<sort_by_ikey>(a_hashref, b_hashref, array of keys)

Sort hashes by key.  To be used in conjunction with the sort function:

    sort {sort_by_ikey($a, $b, 'lastname', 'firstname')} @array

=cut

sub sort_by_ikey {
	my $first = shift;
	my $last = shift;
	my $key = shift;
	return 0 unless ($key);
	no warnings q/numeric/;
	return ((lc($first->{$key}) cmp lc($last->{$key})) || ($first->{$key} <=> $last->{$key}) || (sort_by_ikey($first, $last, @_)));
}

=pod

=item (scalar, scalar) C<sort_by_key>(a_hashref, b_hashref, array of keys)

Case-insensitive version of C<sort_by_ikey>

    sort {sort_by_key($a, $b, 'lastname', 'firstname')} @array

=cut

sub sort_by_key {
	my $first = shift;
	my $last = shift;
	my $key = shift;
	return 0 unless ($key);
	no warnings q/numeric/;
	return (($first->{$key} cmp $last->{$key}) || ($first->{$key} <=> $last->{$key}) || (sort_by_ikey($first, $last, @_)));
}

=pod

=item (hashref) C<token_hash>(scalar, [scalar])

Shorthand for performing C<token_hash> on a string and returning a hash with
positive values for every token.  Useful for making a hash that can be easily
used to check against the existence of a token in a string.

=cut

sub token_hash {
	my ($text, $token_regexp) = @_;
	my @parts = token_parse($text, $token_regexp);
	my %hash = ();
	foreach my $part (@parts) {
		$hash{$part} = 1;
	}
	return \%hash;
}

=pod

=item (array) C<token_parse>(scalar, [regexp])

given a string made up of tokens it will split the tokens into an array
of these tokens separated.  It defaults to separating by commas, or if
there are no commas, by whitespace.  The optional regexp overrides the
normal behavior.


	token_parse('each peach, pear, plum')

returns

	(q/each peach/, q/pear/, q/plum/)

and

	token_parse('every good boy does fine')

returns

	qw(every good boy does fine)

=cut

sub token_parse {
	my ($text, $token_regexp) = @_;
	if ($token_regexp) {
		return split(/$token_regexp/, $text);
	} else {
		if ($text =~ /,/) {
			return split /\s*,\s*/, $text;
		} else {
			return split /\s+/, $text;
		}
	}
}

=pod

=item (array of hashrefs) C<uniquify_by_ikey>(scalar, array of hashrefs)

given a key and an array of hashrefs, returns an array in the same order,
dropping any hashrefs with duplicate values in the given key.  Items are
evaluated in a case-insensitive manner.

=cut

sub uniquify_by_ikey {
	my ($key, @array) = @_;
	my %counts =();
	return grep {$counts{lc($_->{$key})}++ == 0} @array;
}

=pod

=item (array of hashrefs) C<uniquify_by_key>(scalar, array of hashrefs)

case sensitive version of C<uniquify_by_ikey>.

=cut

sub uniquify_by_key {
	my ($key, @array) = @_;
	my %counts =();
	return grep {$counts{$_->{$key}}++ == 0} @array;
}

=pod

=item (array of hashrefs) C<uri_escape>(scalar, array of hashrefs)

Quick and dirty shorthand for encoding a get request within a get request.

=cut

sub uri_escape {
	my $value = shift;
	$value = Apache::Util::escape_uri($value);
	$value =~ s/\&/%26/g;
	$value =~ s/\?/%3f/g;
	$value =~ s/\#/%23/g;
	return $value;
}

=pod

=back

=head2 MAIL (:mail)

Quick and dirty interfaces to sendmail

=over

=item (null) C<send_mail> (hashref)

Send an email.  Assumes that the apache process is a trusted user (see
sendmail documentation).  The hash should have the following keys: to,
from, subject, and body.  Unless sendmail is in /usr/sbin, the path key
should also be set.

=cut

sub send_mail {
	my $mail = shift;
	$mail = lc_hash($mail);
	my $path = ($$mail{'path'} || '/usr/sbin');
	open (OUT, "| $path/sendmail -t ") || die("Mail Failed: sendmail could not be used to send mail");
	print OUT <<__mail_end__;
From: $$mail{from}
To: $$mail{to}
Subject: $$mail{subject}

$$mail{body}

__mail_end__
	close OUT;
}

=pod

=back

=head2 Strings (:string)

String manipulations.

=over

=item (scalar) C<commify> (array)

Add commas to numbers, thanks to the perlfaq.

=cut

 sub commify {
	my $number = shift;
	1 while ($number =~ s/^([-+]?\d+)(\d{3})/$1,$2/);
	return $number;
}

=pod

=back

=head2 TAGS (:tag)

Tag-generation tools.

=over

=item (scalar) C<attopts_template> (array)

Creates a template of attribute options, given an array of the attributes.

=cut

sub attopts_template {
	my @opts = @_;
	my $string = '';
	foreach my $opt (@opts) {
		$string .= '?:' . $opt . '{ $:' . $opt . '}';
	}
}

=pod

=back

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