#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details
use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Services::Index;
our $VERSION = '0.86';
use Apache::Wyrd::Services::SAK qw(token_parse);
use Apache::Wyrd::Services::SearchParser;
use BerkeleyDB;
use BerkeleyDB::Btree;
use HTML::Entities;

=pod

=head1 NAME

Apache::Wyrd::Services::Index - Metadata index for word/data search engines

=head1 SYNOPSIS

    my $init = {
      file => '/var/lib/Wyrd/pageindex.db',
      strict => 1,
      attributes => [qw(author text subjects)],
      maps => [qw(subjects)]
    };
    my $index = Apache::Wyrd::Services::Index->new($init);

    my @subject_is_foobar = $index->word_search('foobar', 'subjects');

    my @pages =
      $index->word_search('+musthaveword -mustnothaveword
        other words to search for and add to results');
    foreach my $page (@pages) {
      print "title: $$page{title}, author: $$page{author};
    }
    
    my @pages = $index->parsed_search('(this AND that) OR "the other"');
    foreach my $page (@pages) {
      print "title: $$page{title}, author: $$page{author};
    }


=head1 DESCRIPTION

General purpose Index object for retrieving a variety of information on
a class of objects.  The objects can have any type, but must implement
at a minumum the C<Apache::Wyrd::Interfaces::Indexable> interface.

The information stored is broken down into attributes.  The main builtin
(and not override-able) attributes are B<data>, B<word>, B<title>, and
B<description>, as well as three internal attributes of B<reverse>,
B<timestamp>, and B<digest>.  Additional attributes are specified via
the hashref argument to the C<new> method (see below).  There can be
only 255 total attributes.

Attributes are of two types, either regular or map, and these relate to
the main index, B<id>.  A regular attribute stores information on a
one-id-to-one-attribute basis, such as B<title> or B<description>.  A
map attribute provides a reverse lookup, such as words in a document, or
subjects covered by documents, such as documents with the word "foo" in
them or items classified as "bar".  One builtin map exists, B<word>
which reverse-indexes every word of the attribute B<data>.

The Index is meant to be used as a storage for meta-data about web
pages, and in this capacity, B<data> and B<word> provide the exact match
and word-search capacity respectively.

The internal attributes of B<digest> and B<timestamp> are also used to
determine whether the information for the item is fresh.  It is assumed
that testing a timestamp is faster than producing a digest, and that a
digest is faster to produce than re-indexing a document, so a check to
these two criteria is made before updating an entry for a given item. 
See C<update_entry>.

The information is stored in a Berkeley DB, using the
C<BerkeleyDB::Btree> perl module.  Because of concurrence of usage
between different Apache demons in a pool of servers, it is important
that this be a reasonably current version of BerkeleyDB which supports
locking and read-during-update.  This module was developed using
Berkeley DB v. 3.3-4.1 on Darwin and Linux.

Use with vast amounts of large documents is not recommended, but a
reasonably large (hundreds of 1000-word pages) web site can be indexed
and searched reasonably quickly(TM) on most cheap servers as of this
writing.  All hail Moore's Law.

=head1 METHODS

I<(format: (returns) name (arguments after self))>

=over

=item (Apache::Wyrd::Services::Index) C<new> (hashref)

Create a new Index object, creating the associated DB file if necessary.  The
index is configured via a hashref argument.  Important keys for this hashref:

=over

=item file

Absolute path and filename for the DB file.  Must be writeable by the Apache
process.

=item strict

Die on errors.  Default 1 (yes).

=item quiet

If not strict, be quiet in the error log about problems.  Use at your
own risk.

=item attributes

Arrayref of attributes other than the default to use.  For every attribute
B<foo>, an C<index_foo> method should be implemented by the object being
indexed.  The value returned by this method will be stored under the attribute
B<foo>.

=item maps

Arrayref of which attributes to treat as maps.  Anny attribute that is a map
must also be included in the list of attributes.

=back

=cut

sub new {
	my ($class, $init) = @_;
	die ('Must specify index file') unless($$init{'file'});
	die ('Must specify an absolute path for the index file') unless ($$init{'file'} =~ /^\//);
	my ($directory) = ($$init{'file'} =~ /(.+)\//);
	die ('Must specify a valid, writeable directory location.  Directory given: ' . $directory) unless (-d $directory && -w _);
	#Die on errors by default
	$$init{'strict'} = 1 unless exists($$init{'strict'});
	$$init{'quiet'} = 0 unless exists($$init{'quiet'});
	my @attributes = qw(reverse timestamp digest data word title description);
	my @check_reserved = ();
	foreach my $reserved (@attributes, 'id', 'score') {
		push @check_reserved, $reserved if (grep {$reserved eq $_} @{$$init{'attributes'}});
	}
	my $s = '';
	$s = 's' if (@check_reserved > 1);
	die ("Reserved attribute$s specified.  Use different name$s: " . join(', ', @check_reserved)) if (@check_reserved);
	my @maps = qw(word);
	my (%attributes, %maps) = ();
	@attributes = (@attributes, @{$init->{'attributes'}}) if (ref($init->{'attributes'}) eq 'ARRAY');
	warn ("Too many attributes.  First 255 will be used.") if (@attributes > 255);
	my $attr_index = 0;
	foreach my $attribute (@attributes) {
		$attributes{$attribute} = chr($attr_index);
		$attr_index++;
		last if ($attr_index > 255);
	}
	@maps = (@maps, @{$init->{'maps'}}) if (ref($init->{'maps'}) eq 'ARRAY');
	foreach my $map (@maps) {
		$maps{$map} = 1;
	}
	my $env = BerkeleyDB::Env->new(
		-Home			=> $directory,
		-Flags			=> DB_INIT_LOCK | DB_INIT_LOG | DB_INIT_MPOOL,
		-LockDetect		=> DB_LOCK_DEFAULT
	);
	#Note: die_no_lock is ignored if strict is not set
	my $data = {
		file			=>	$$init{'file'},
		directory		=>	$directory,
		db				=>	undef,
		env				=>	$env,
		status			=>	undef,
		strict			=>	$$init{'strict'},
		quiet			=>	$$init{'quiet'},
		error			=>	[],
		attributes		=>	\%attributes,
		attribute_list	=>	\@attributes,
		maps			=>	\%maps,
		map_list		=>	\@maps,
		extended		=>	((scalar(keys %attributes) > 7) ? 7 : 0)
	};
	bless $data, $class;
	$data->write_db unless (-e $$init{'file'});
	$data->read_db;
	return $data;
}

sub DESTROY {
	my ($self) = @_;
	$self->close_db;
}

sub db {
	my ($self) = @_;
	return $self->{'db'};
}

sub env {
	my ($self) = @_;
	return $self->{'env'};
}

sub extended {
	my ($self) = @_;
	return $self->{'extended'};
}

sub attributes {
	my ($self) = @_;
	return $self->{'attributes'};
}

sub maps {
	my ($self) = @_;
	return $self->{'maps'};
}

sub attribute_list {
	my ($self) = @_;
	return $self->{'attribute_list'};
}

sub map_list {
	my ($self) = @_;
	return $self->{'map_list'};
}

sub status {
	my ($self) = @_;
	return $self->{'status'};
}

sub strict {
	my ($self) = @_;
	return $self->{'strict'};
}

sub quiet {
	my ($self) = @_;
	return $self->{'quiet'};
}

sub file {
	my ($self) = @_;
	return $self->{'file'};
}

sub directory {
	my ($self) = @_;
	return $self->{'directory'};
}

sub error {
	my ($self) = @_;
	return @{$self->{'error'}};
}

sub set_error {
	my ($self, $error) = @_;
	$self->{'error'} = [@{$self->{'error'}}, $error];
	return undef;
}

=pod

=item (void) C<delete_index> (void)

Zero all data in the index and open a new one.

=cut

sub delete_index {
	my ($self) = @_;
	$self->write_db;
	$self->close_db;
	$self->set_error("Could not delete the index: $!") unless (unlink $self->file);
	$self->check_error;
	$self->write_db;
	$self->read_db;
	return undef;
}

sub newstatus {
	my ($self, $status) = @_;
	return undef if ($self->status eq 'X');#Once it's bad, it stays there.
	$self->{'status'} = $status;
	return undef;
}

sub check_error {
	my ($self) = @_;
	if ($self->strict) {
		die (join("\n", $self->error)) if ($self->error);
	} else {
		$self->{'status'} = 'X';
		return undef if ($self->quiet);
		warn (join("\n", $self->error)) if ($self->error);
	}
	return undef;
}

sub read_db {
	my ($self) = @_;
	if ($self->status eq 'R') {
		return $self->db;
	} elsif ($self->status eq 'RW') {
		$self->close_db;
	}
	my %index = ();
	my $index = tie %index, 'BerkeleyDB::Btree', -Filename => $self->file, -Flags => DB_RDONLY, -Env => $self->env, -Mode => 0660;
	$self->set_error ("Can't open the index for reading.") unless ($index);
	$self->check_error;
	$self->newstatus('R');
	$self->{'db'} = $index;
	return $index;
}

sub write_db {
	my ($self) = @_;
	if ($self->status eq 'RW') {
		return $self->db;
 	} elsif ($self->status eq 'R') {
		$self->close_db;
	}
	my %index = ();
	my $index = tie (%index, 'BerkeleyDB::Btree', -Filename => $self->file, -Flags => DB_CREATE, -Env => $self->env, -Mode => 0660);
	$self->set_error ("Can't open/create the index for writing.") unless ($index);
	$self->check_error;
	$self->newstatus('RW');
	$self->{'db'} = $index;
	return $index;
}

sub close_db {
	my ($self) = @_;
	my $index = $self->db;
	if ($index) {
		$index->db_sync;
		$self->{'db'} = undef;
		delete ($self->{'status'}); #close the DB ref
		$self->{'status'} = undef;
	}
	return undef;
}

=pod

=item (scalar) C<update_entry> (Apache::Wyrd::Interfaces::Indexable ref)

Called by an indexable object, passing itself as the argument, in order to
update it's entry in the index.  This method calls C<index_foo> for every
attribute B<foo> in the index, storing that value under the attribute entry for
that object.  The function always returns a message about the process.

update_entry will always check index_timestamp and index_digest.  If the stored
value and the returned value agree on either attribute, the index will not be
updated.  This behavior can be overridden by returning a true value from method
C<force_update>.

=cut

#attributes - integer=name (self_path), 0=reverse, 1=timestamp, 2=digest, 3=data, 4=word, 5=title, 6=description
sub update_entry {
	my ($self, $entry) = @_;
	$self->set_error = "Index entries must be objects " unless (ref($entry));
	foreach my $function (qw/no_index index_name index_timestamp index_digest index_data/) {
		$self->set_error = "Index entries must implement the method $function\(\)" unless ($entry->can($function));
	}
	$self->check_error;
	my $index = $self->read_db;
	my $null = undef;#used for DB checks where no value needs be returned
	if ($entry->no_index) {
		if ($index->db_get("\x00%" . $entry->index_name, $null)) {
			#if key is not found
			return "yes to no_index and not indexed.";
		}
		$index = $self->write_db;
		my $result = $self->purge_entry($entry->index_name);
		$self->close_db;
		return $result;
	}
	my ($id, $id_is_new) = $self->get_id($entry->index_name);
	unless ($entry->force_update) {
		$index->db_get("\x01\%$id", my $timestamp);
		if ($timestamp eq $entry->index_timestamp) {
			return "No update needed.  Timestamp is $timestamp." ;
		}
		$index->db_get("\x02\%$id", my $digest);
		#warn "Comparing digests: $digest <-> " . $entry->index_digest;
		if ($digest eq $entry->index_digest) {
			$index = $self->write_db;
			$self->update_key("\x01\%$id", $entry->index_timestamp);
			$self->close_db;
			return "Updated timestamp only, since digest was identical.";
		}
	}
	$index = $self->write_db;
	$self->purge_entry($id); #necessary to clear out words which will not match
	$self->update_key("\x01\%$id", $entry->index_timestamp);
	$self->update_key("\x02\%$id", $entry->index_digest);
	$self->process_html($id, $entry->index_data);
	$self->update_key("\x05\%$id", $entry->index_title) if ($entry->can('index_title'));
	$self->update_key("\x06\%$id", $entry->index_description) if ($entry->can('index_description'));
	if ($self->extended) {
		my @attributes = @{$self->attribute_list};
		splice(@attributes, 0, 7);
		foreach my $attribute (@attributes) {
			my $value = undef;
			if ($entry->can("index_$attribute")) {
				eval('$value = $entry->index_' . $attribute);
				$self->set_error($@) if ($@);
				$self->check_error;
			} elsif (exists($entry->{$attribute})) {
				$value = $entry->{$attribute};
			}
			if ($entry->can("handle_$attribute")) {
				eval('$entry->handle_' . $attribute . '($id, $value)');
				$self->set_error($@) if ($@);
				$self->check_error;
			} elsif ($value) {
				if ($self->maps->{$attribute}) {
					$self->index_map($attribute, $id, [token_parse($value)]);
				} else {
					$self->update_key($self->attributes->{$attribute} . "\%$id", $value);
				}
			}
		}
		$self->update_key($id, $entry->index_name);
		$self->update_key("\x00%" . $entry->index_name, $id);
		$self->close_db;
		return "Update of entry $id " . ($self->error ? "unsuccessful." : "successful.");
	}
}

sub purge_entry {
	my ($self, $entry) = @_;
	my $id = undef;
	my $null = undef;
	if ($entry =~ /^\d+$/) {
		$id = $entry unless ($self->db->db_get($entry, $null));
		$self->db->db_get("\x00\%$id", $entry) unless ($self->db->db_get("\x00%$entry", $null));#remember that get returns a 1 on failure
	} else {
		$self->db->db_get("\x00%$entry", $id) unless ($self->db->db_get("\x00%$entry", $null));
	}
	unless ($id and $entry) {
		return "Entry not found to purge: $entry";
	}
	foreach my $attribute (@{$self->attribute_list}) {
		if ($self->maps->{$attribute}) {
			$self->purge_map($attribute, $id);
		} else {
			$self->delete_key($self->attributes->{$attribute} . "%$id");
		}
	}
	return "Entry $entry ($id) successfully purged";
}

=pod

=item (hashref) C<entry_by_name> (scalar)

Given the value of an B<name> attribute, returns a hashref of all the regular
attributes stored for a given entry.

=cut

sub entry_by_name {
	my ($self, $name) = @_;
	my $id = $self->get_id($name);
	return $self->get_entry($id);
}

sub get_entry {
	my ($self, $id) = @_;
	$self->db->db_get($id, my $name);
	my %entry = (id => $id, name => $name);
	foreach my $attribute (@{$self->attribute_list}) {
		next if (grep {$_ eq $attribute} @{$self->map_list});
		$self->db->db_get($self->attributes->{$attribute} . '%' . $id, $entry{$attribute});
	}
	return \%entry;
}

sub get_id {
	my ($self, $name) = @_;
	my $result = $self->db->db_get("\x00%$name", my $id);
	return $id unless ($result);
	my $cursor = $self->db->db_cursor;
	$cursor->c_get($id, my $string, DB_FIRST);
	my $greatest = 0;
	do {
		if ($id =~ /^\d+$/) {
			return $id if ($string eq $name); #existing id
			$greatest = $id if ($id > $greatest);
		}
	} until ($cursor->c_get($id, $string, DB_NEXT));
	$greatest++;
	return ($greatest, 1);#new id + flag
}

sub update_key {
	my ($self, $key, $value) = @_;
	$self->db->db_put($key, $value);
	#warn "$key updated to $value";
	return undef;
}

sub delete_key {
	my ($self, $key) = @_;
	$self->db->db_del($key);
	#warn "$key updated to $value";
	return undef;
}

sub process_html {
	my ($self, $id, $data) = @_;
	$self->check_error;
	# Index all the words under the current key
	$data = $self->clean_html($data);
	$self->db->db_put("\x03\%$id", $data);
	#warn "\x03\%$id updated to $data";
	$self->index_words($id, $data);
	return undef;
}

sub index_map {
	my ($self, $attribute, $id, $data) = @_;
	#warn "mapping $id - $attribute : " . join (':', @$data);
	$attribute = $self->attributes->{$attribute};
	my (%unique, $item, @items) = (); # for unique-ifying word list
	#remove duplicates if necessary
	if (ref($data) eq 'ARRAY') {
		@items = grep { $unique{$_}++ == 0 } @$data;
	} elsif (ref($data) eq 'HASH') {
		%unique = %$data;
		@items = keys(%unique);
	} else {
		#not sure why you'd want to do this, but hey.
		@items = ($data);
	}
	# For each item, add key to word database
	foreach my $item (sort @items) {
		next unless ($item);
		my $value = undef;
		my $not_found = $self->db->db_get("$attribute\%$item", my $data);
		my(%entries) = ();
		%entries = unpack("n*", $data) unless ($not_found);
		$entries{$id} = $unique{$item};
		foreach my $item (keys %entries) {
			$value .= pack "n", $item;
			$value .= pack "n", $entries{$item};
		}
		#warn($self->translate_packed($attribute) . "\%$item: " . $self->translate_packed($value));
		$self->db->db_put("$attribute\%$item", $value);
	}
	return undef;
}

sub purge_map {
	my ($self, $attribute, $id) = @_;
	$attribute = $self->attributes->{$attribute};
	my ($key, $current, $removed) = ();
	my $cursor = $self->db->db_cursor;
	$cursor->c_get($key, $current, DB_FIRST);
	do {
		if ($key =~ /^$attribute\%/) {
			my $value = undef;
			my(%entries) = unpack("n*", $current);
			foreach my $item (keys %entries) {
				next if ($item eq $id);
				$value .= pack "n", $item;
				$value .= pack "n", $entries{$item};
			}
			$self->db->db_put($key, $value);
		}
	} until ($cursor->c_get($key, $current, DB_NEXT));
	return undef;
}

sub index_words {
	my ($self, $id, $data) = @_;
	# Split text into Array of words
	my (@words) = split(/\s+/, $data);
	return $self->index_map('word', $id, \@words);
}

=pod

=item (scalar) C<clean_html> (scalar)

Given a string of HTML, this method strips out all tags, comments, etc., and
returns only clean text for breaking down into tokens.  You may want to override
this method -- the default method is pretty quick-and-dirty.

=cut

sub clean_html {
	my ($self, $data) = @_;
	$data = decode_entities($data);
	$data =~ s/<>//g; # Strip out all empty tags
	$data =~ s/<--.*?-->/ /g; # Strip out all comments
	$data =~ s/<[^>]*?>/ /g; # Strip out all HTML tags
	$data =~ s/[,.!?;"'_\xD0\xD1\+=]/ /g; # Strip out all standard punctuation
	$data =~ s/\s+/ /g; # Flatten all whitespace
	{
		no warnings 'utf8';
		$data = lc($data);
	}
	$data =~ s/[^a-z0-9\x80-\x9f\xc0-\xff\s]+/ /gs; # Strip punct
	$data =~ s/^\s+//;
	$data =~ s/\s+$//;
	return $data;
}

sub clean_searchstring {
	my ($self, $data) = @_;
	$data = decode_entities($data);
	$data =~ s/[,.!?;"'_\xD0\xD1\+=]/ /g; # Strip out all standard punctuation
	$data =~ s/\s+/ /g; # Flatten all whitespace
	{
		no warnings 'utf8';
		$data = lc($data);
	}
	$data =~ s/[^a-z0-9\x80-\x9f\xc0-\xff\s]+/ /gs; # Strip punct
	$data =~ s/^\s+//;
	$data =~ s/\s+$//;
	return $data;
}

=pod

=item (array) C<word_search> (scalar, [scalar])

return entries matching tokens in a string within a given map attribute.  As map
attributes store one token, such as a word, against which all entries are
indexed, the string is broken into tokens before processing, with commas and
whitespaces delimiting the tokens unless they are enclosed in double quotes.

If a token begins with a plus sign (+), results must have the word, with a minus
sign, (-) they must not.  These signs can also be placed left of phrases
enclosed by double quotes.

Results are returned in an array of hashrefs ranked by "score".  The attribute
"score" is added to the hash, meaning number of matches for that given entry. 
All other regular attributes of the indexable object are values of the keys of
each hash returned.

The default map to use for this method is 'word'.  If the optional second
argument is given, that map will be used.

=cut

sub word_search { #accepts a search string, returns an arrayref of entry matches
	my ($self, $string, $attribute) = @_;
	if ($attribute) {
		$self->_raise_exception("You cannot perform a word search on the attribute $attribute; It doesn't exist")
			unless ($self->maps->{$attribute});
		$attribute = $self->{'attributes'}->{$attribute};
	} else {
		$attribute = "\x04";
	}
	my $index = $self->read_db;
	my (@out, %match, %must, %mustnot, @match, @add, @remove, $restrict, @entries)=();
	$string =~ s/(\+|\-)\s+/$1/g;
	if ($string =~ /"/) {#first deal with exact word matches
		while ($string =~ m/(([\+-]?)"([^"]+?)")/) { #whole=1, modifier=2, phrase=3
			my $phrase = $self->clean_searchstring($3);
			my $modifier = $2;
			my $substring = $1;
			#escape out phrase and substring since they will be used in regexps
			#later in this subroutine.
			$substring =~ s/([\\\+\?\:\\*\&\@\$\!])/\\$1/g;
			$phrase =~ s/([\\\+\?\:\\*\&\@\$\!])/\\$1/g;
			$string =~ s/$substring//; #remove the phrase from the string;
			if ($modifier eq '+') {
				push (@add, "_$phrase");
				$restrict = 1;
			} elsif ($modifier eq '-') {
				push (@remove, "_$phrase");
			} else {
				push (@match, "_$phrase");
			}
		}
	}
	my @word=split(/\s+/, $string); #then deal with single words
	foreach my $word (@word){
		my ($modifier) = $word =~ /^([\+\-])/;
		$word = $self->clean_searchstring($word);
		if ($modifier eq '+') {
			push (@add, $word);
			$restrict = 1;
		} elsif ($modifier eq '-') {
			push (@remove, $word);
		} else {
			push (@match, $word);
		}
	}
	#warn "searching for:";
	#warn map {"\nmatch - $_"} @match;
	#warn map {"\nadd - $_"} @add;
	#warn map {"\nremove - $_"} @remove;
	#if this is a 100% negative search, all entries match
	unless (scalar(@match) or scalar(@add)) {
		@entries = $self->get_all_entries;
		foreach my $key (@entries) {
			$match{$key}=1;
		}
	}
	foreach my $word (@match){
		if ($word =~ s/^_//) {
			foreach my $entry ($self->get_all_entries) {
				$index->db_get("\x03%$entry", my $data);
				my @count = $data =~ m/($word)/g;
				my $count = @count;
				$match{$entry} += $count;
			}
		} else {
			$index->db_get("$attribute\%$word", my $keys);
			#warn "match - '" . translate_packed($keys) . "'";
			my (@keys) = unpack("n*",$keys);
			while (@keys) {
				my $entry = shift @keys;
				my $count = shift @keys;
				#warn "entry: $entry, $count: $count";
				$match{$entry} += $count;
			}
		}
	}
	foreach my $word (@add){
		if ($word =~ s/^_//) {
			foreach my $entry ($self->get_all_entries) {
				$index->db_get("\x03%$entry", my $data);
				my @count = $data =~ m/($word)/g;
				my $count = @count;
				$match{$entry} += $count;
				$must{$entry.$word}=$count;
				#warn ($entry.$word . " is $count") if ($must{$entry.$word});
			}
		} else {
			$index->db_get("$attribute\%$word", my $keys);
			#warn "add - '" . translate_packed($keys) . "'";
			my (@keys) = unpack("n*",$keys);
			while (@keys) {
				my $entry = shift @keys;
				my $count = shift @keys;
				$match{$entry} += $count;
				$must{$entry.$word}=1;
			}
		}
	}
	foreach my $word (@remove){
		if ($word =~ s/^_//) {
			foreach my $entry ($self->get_all_entries) {
				$index->db_get("\x03%$entry", my $data);
				$mustnot{$entry}=$word if ($data =~ m/$word/);
			}
		} else {
			$index->db_get("$attribute\%$word", my $keys);
			my (@keys) = unpack("n*",$keys);
			while (@keys) {
				my $entry = shift @keys;
				shift @keys;
				$mustnot{$entry}=$word;
			}
		}
	}
	if ($restrict) {
		foreach my $add (@add) {
			foreach my $key (keys(%match)) {
				#warn "tossing out $index->{$key} ($key) because $add isn't in it." unless $must{$key.$add};
				delete($match{$key}) unless $must{$key.$add};
			}
		}
	}
	foreach my $key (keys(%match)) {
		#warn "tossing out $index->{$key} ($key) because $mustnot{$key} is in it." if ($mustnot{$key});
		delete($match{$key}) if($mustnot{$key});
	}
	my %output=();
	#map actual names to matches
	foreach my $key (keys(%match)) {
		$output{$key}=$self->get_entry($key);
		$output{$key}->{'score'} = $match{$key};
	}
	$self->close_db;
	my %matches=();
	foreach my $id (keys(%output)) {
		$matches{$output{$id}->{'score'}}=1;
	}
	#put matches in order of highest relevance down to lowest by mapping known
	#counts of words against the pages that are known to match that word.
	foreach my $relevance (sort {$b <=> $a} keys %matches){
		next unless $relevance;
		foreach my $id (sort keys(%output)) {
			if ($output{$id}->{'score'} == $relevance){
				push (@out, $output{$id});
			}
		}
	}
	return @out;
}

=pod

=item (array) C<search> (scalar, [scalar])

Alias for word_search.  Required by C<Apache::Wyrd::Services::SearchParser>.

=cut

sub search {
	my $self = shift;
	return $self->word_search(@_);
}

=pod

=item (array) C<parsed_search> (scalar, [scalar])

Same as word_search, but with the logical qualifiers AND, OR, and NOT.  More
complex searches can be accomplished, at a cost of speed.

=cut

sub parsed_search {
	my $self = shift;
	my $parser = Apache::Wyrd::Services::SearchParser->new($self);
	return $parser->parse(@_);
}

sub get_all_entries {
	my $self=shift;
	my @entries = ();
	my $cursor = $self->db->db_cursor;
	$cursor->c_get(my $id, my $entry, DB_FIRST);
	do {
		push @entries, $entry if ($id =~ /^\0%/);
	} until ($cursor->c_get($id, $entry, DB_NEXT));
	return @entries;
}

sub make_key {
	my ($self, $attribute, $id) = @_;
	return $self->attributes->{$attribute} . '%' . $id;
}

sub translate_packed {
	return join('',  map {(($_ + 0) < 33 or ($_ + 0) > 122) ? '{' . $_ . '}' : chr($_)} unpack('c*', $_[1]) );
}

=pod

=back

=head1 BUGS/CAVEATS/RESERVED METHODS

UNKNOWN

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item Apache::Wyrd

General-purpose HTML-embeddable perl object

=item Apache::Wyrd::Interfaces::Indexable

Methods to be implemented by any item that wants to be indexed.

=item Apache::Wyrd::Services::SearchParser

Parser for handling logical searches (AND/OR/NOT/DIFF).

=back

=head1 LICENSE

Copyright 2002-2004 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut


1;
