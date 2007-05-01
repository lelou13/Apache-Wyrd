package Apache::Wyrd::Site::IndexBrowser;
use strict;
use warnings;
use base qw(Apache::Wyrd::Interfaces::IndexUser Apache::Wyrd);
use BerkeleyDB;
use BerkeleyDB::Btree;
use Apache::Util;
our $VERSION = '0.96';

=pod

This is a wyrd for debugging Apache::Wyrd::Services::Index data. 
Documentation will not be provided, due to the depreciation of the
Apache::Wyrd::Services::Index class.  The
Apache::Wyrd::Services::MySQLIndex class that replaces it is easier to
debug via SQL queries, so no parallel version will be made.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub _generate_output {
	no warnings qw(uninitialized);
	my ($self) = @_;
	my $debug = $self->_flags->debug;
	my $name = $self->dbl->param('name');
	my $url = $self->dbl->self_path;
	$name = $url unless($self->_flags->general);
	my $id = $self->dbl->param('id');
	my $attribute = $self->dbl->param('attribute');
	my $index = $self->_init_index;
	$index->read_db;
	$attribute = '' if (grep {$attribute eq $_} @{$index->map_list});
	$id = $index->get_id($name) if ($name);
	if ($id and $attribute) {
		my $value = $index->lookup($id, $attribute);
		$value = "<pre>$value</pre>";
		return $value;
	} elsif ($id) {
		my $out = '';
		if ($self->_flags->debug) {
			$out .= '<table border="1" width="100%"><tr><th colspan="2">Raw Search/Dump</td></tr>';
			my $db=$index->read_db;
			my $cursor = $db->db_cursor;
			my $counter = 0;
			my %attr = map {$counter++, $_} @{$index->attribute_list};
			map {$attr{$counter++} = $_ . '&nbsp;(rev.)'} @{$index->map_list};
			$counter = 0;
			my %attr_rev = map {$_, $counter++} @{$index->attribute_list};
			my %maps = map {$_, $attr_rev{$_}} @{$index->map_list};
			my %mapping = map {$_, []} @{$index->map_list};
			my $filenames = '';
			$cursor->c_get(my $name, my $entry, DB_FIRST);
			do {
				$filenames .= "$entry " if ($name eq $id);
				$name =~ /^([\x00-\xff])%(.*)$/;
				if ($maps{$attr{ord($1)}}) {
					my(%entries) = unpack("n*", $entry);
					push @{$mapping{$attr{ord($1)}}}, $2 if ($entries{$id});
				}
				if ($name =~ /^([\x00-\xff])%($id|$name)$/) {
					if (not($maps{ord($1)})) {
						my $attribute = ord($1) . '&nbsp;' . $attr{ord($1)};
						$entry =~ s/\x00/, /g;
						$entry = Apache::Util::escape_html($entry);
						$out .= qq(<tr><td>$attribute</td><td>$entry</td></tr>) unless (grep {$attr{ord($1)} eq $_} (@{$index->map_list}));
					}
				}
				
			} until ($cursor->c_get($name, $entry, DB_NEXT));
			$cursor->c_close;
			foreach my $map (sort keys %maps) {
				$out .= qq(<tr><td>$map</td><td>) . join(', ', @{$mapping{$map}}) . qq(</td></tr>);
			}
			$out .= qq(<tr><td>filenames</td><td>$filenames</td></tr>);
			$out .= '</table><br>';
		}
		$out .= '</table><br><table border="1" width="100%"><tr><th colspan="2">"Regular Dump" (no maps, no data)</td></tr>';
		my @attributes = @{$index->attribute_list};
		my $entry = $index->get_entry($id);
		foreach my $attribute (@attributes) {
			next if (grep {$attribute eq $_} (@{$index->map_list}, 'reverse', 'data'));
			my $value = Apache::Util::escape_html($entry->{$attribute});
			if ($attribute eq 'timestamp') {
				my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
					$wday, $yday, $isdst) = localtime($value);
				$value .= sprintf(" (%04d/%02d/%02d at %02d:%02d:%02d)",
					$year+1900, $month+1, $day_of_month, $hours, $minutes, $seconds);
			}
			$out .= qq(<tr><td>$attribute</td><td>$value</td></tr>);
		}
		return $out . '</table>';
	} else {
		my $out = '';
		my $db=$index->read_db;
		my $cursor = $db->db_cursor;
		$cursor->c_get(my $name, my $entry, DB_FIRST);
		my $count = 0;
		do {
			if ($name =~ /^\0%/) {
				$out .= qq(<a href="$url?id=$entry">$name</a><br>\n);
				$count++;
			}
		} until ($cursor->c_get($name, $entry, DB_NEXT));
		$cursor->c_close;
		$out .= '<p>Index is empty</p>' unless ($count);
		return $out;
	}
};

1;