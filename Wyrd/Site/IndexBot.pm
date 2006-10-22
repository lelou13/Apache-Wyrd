use strict;
package Apache::Wyrd::Site::IndexBot;
use base qw(Apache::Wyrd::Bot);
use Apache::Wyrd::Services::SAK qw(:file);
use HTTP::Request::Common;
use BerkeleyDB;
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub index_site {
	my ($self, $index) = @_;
	my $lastindex = undef;
	my $hostname = $self->{'server_hostname'};
	my $root = $self->{'document_root'};

	#purge_missing returns a list of existing files for which there is no
	#database entry and/or the entry has been deleted.
	my @no_skip = $self->purge_missing($index);
	my %no_skip = map {$_ , 1} @no_skip;
	if ($self->{'realclean'}) {
		print "Expired data purge complete.";
	}

	#create a user-agent to trigger the updates to the index with
	my $ua = $index->ua;
	$ua->timeout(60);
	local $| = 1;

	#go through the files in the document root that match ".html",
	#and read in the file that shows when the last update was done
	open (FILES, "/usr/bin/find $root -name \*.html |");
	$lastindex = ${slurp_file($root . "/var/lastindex.db")};
	my $newest = $lastindex;
	my @files = ();
	while (<FILES>) {
		chomp;
		push @files, $_;
	}
	print "<P>" . scalar(@files) . " files to index.</p>";

	#For each file, try to navigate to it with the User-agent.  Use the auth
	#cookie of the viewer of this Wyrd.
	my $counter = 0;
	while ($_ = shift @files) {
		my @stats = stat($_);
		#warn "Document status/lastindex/current newest:" . join('/', $stats[9], $lastindex, $newest);
		$newest = $stats[9] if ($stats[9] > $newest);
		$counter++;
		s/$root//;
		unless ($no_skip{$_}) {
			next if ($self->{'fastindex'} and ($stats[9] <= $lastindex));
			next if $index->skip_file($_);
		}
		my $url = "http://$hostname$_";
		my $response = '';
		my $auth_cookie = $self->{'auth_cookie'};
		if ($auth_cookie) {
			$response = $ua->get($url, Cookie => $auth_cookie);
		} else {
			$response = $ua->get($url);
		}
		my $status = $response->status_line;
		if ($status =~ /200|OK/) {
			print "$counter. $_: OK";
		} else {
			print "$counter. $_: <span class=\"error\">$status</span>";
			system "touch $_" if (-f $_);
		}
	}
	print "<b><p>$counter files indexed</p></b>";

	#Save the date to the lastindex file.
	spit_file($root . '/var/lastindex.db', $newest);
	return;
}

sub purge_missing {
	my ($self, $instance) = @_;
	my @no_skip = ();
	my $root = $self->{'document_root'};
	print "<P>First checking for deleted documents and corrupt data";
	my $index = $instance->write_db;
	my %ismap = ();
	foreach my $value (keys %{$instance->maps}) {
		$value = $instance->attributes->{$value};
		$ismap{$value} = 1;
	}
	my %exists = ();
	my %reverse = ();
	my %force_purge = ();
	my $cursor = $index->db_cursor;
	$cursor->c_get(my $id, my $document, DB_FIRST);
	do {
		my ($first, $second, $identifier) = unpack('aaa*', $id);
		if ($second ne '%') {
			#if the metachar is not there, this is a primary filename map.
			$exists{$id} = $document || 'error: unnamed entry';
		} elsif ($first eq "\0") {
			#if the metachar is 0, this is a reversemap
			$reverse{$document} = $identifier;
		}
	} until ($cursor->c_get($id, $document, DB_NEXT));
	undef $cursor;
	foreach my $id (keys %exists) {
		my $document = $exists{$id};
		if ($reverse{$id} ne $exists{$id}) {
			print "Entry $id for $exists{$id} seems to be a duplicate entry.  Deleting it prior to purge...";
			my $result = $index->db_del($id);
			$force_purge{$id} = 1;
			if ($result) {
				print "Failed to delete dangling entry $id.  Manual repair may be necessary...";
			}
		} elsif (-f ($root . $document)) {
			#document exists as a file
			print"keeping $root$document";
		} else {
			my $entry = $instance->get_entry($id);
			my $file = $entry->{'file'};
			if (-f ($root . $file)) {
				push @no_skip, $entry;
				if ($document =~ /^\//) {
					print "purging $document, since it's been deleted, but <span class=\"error\">you need to delete the proxy page $file</span>: ". $instance->purge_entry($id);
				} else {
					print "keeping $document, since it's off-site but the proxy ($file) exists";
				}
			} elsif ($document eq '<DELETED>') {
				if ($self->{'realclean'}) {
					print"purging dirty reference to an updated document: ". $instance->purge_entry($id);
				} else {
					print"skipping dirty reference to a previously deleted document";
				}
			} elsif ($document =~ /^\//) {
				print "purging proxy reference to deleted document $root$document: ". $instance->purge_entry($id);
			} else {
				print "purging reference to a dropped proxy to $document ($file): ". $instance->purge_entry($id);
			}
		}
	}
	#re-invoke an instance of cursor since db may have changed (just in case)
	$cursor = $index->db_cursor;
	$cursor->c_get(my $id, my $document, DB_FIRST);
	do {
		my ($attribute, $separator, $current_id) = unpack('aaa*', $id);
		if ($separator ne '%') {
			#do nothing with primary data
		} elsif ($ismap{$attribute}) {
			my $do_update = 0;
			my $value = '';
			my @ids = ();
			my(%entries) = unpack("n*", $document);
			foreach my $item (keys %entries) {
				if (not($exists{$item}) or $force_purge{$item}) {
					$do_update = 1;
					push @ids, $item;
					next;
				}
				$value .= pack "n", $item;
				$value .= pack "n", $entries{$item};
			}
			if ($do_update) {
				my $ids = join ', ', @ids;
				my $error = $index->db_put($id, $value);
				my $ord = unpack "C", $id;
				print "WARNING: purged corrupt map data for nonexistent ids $ids &#151; " . ($instance->attribute_list->[$ord] || "Unknown attribute [$ord]") . " (id# $current_id): " . ($error ? 'failed!' : 'succeeded.');
			}
		} elsif (($attribute eq "\x00") and not(-f ($root . $current_id))) {
			if ($current_id !~ m#^https?://#) {
				my $error = $index->db_del($id);
				my $ord = unpack "C", $id;
				print "WARNING: purged reverse filemap for nonexistent file $current_id &#151; " . ($instance->attribute_list->[$ord] || "Unknown attribute [$ord]") . " (id# $current_id): ". ($error ? 'failed!' : 'succeeded.');
			};
		} elsif ($attribute eq "\xff") {
			#do nothing to global metadata
		} elsif (not($current_id)) {
			print "Strange null entry under attribute " . $instance->attribute_list->[unpack "C", $id] . "... Your guess is as good ad mine...";
		} elsif ($force_purge{$current_id} or (not(($attribute eq "\x00")) and not($exists{$current_id}))) {
			my $error = $index->db_del($id);
			my $ord = unpack "C", $id;
			print "WARNING: purged corrupt data for nonexistent id $current_id &#151; " . ($instance->attribute_list->[$ord] || "Unknown attribute [$ord]") . " (id# $current_id): ". ($error ? 'failed!' : 'succeeded.');
		}
	} until ($cursor->c_get($id, $document, DB_NEXT));
	$cursor->c_close;
	$instance->close_db;
	print "</p>";
	return @no_skip;
}

1;