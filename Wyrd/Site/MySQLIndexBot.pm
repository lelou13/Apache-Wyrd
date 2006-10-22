use strict;
package Apache::Wyrd::Site::MySQLIndexBot;
use base qw(Apache::Wyrd::Site::IndexBot);
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub purge_missing {
	my ($self, $instance) = @_;
	my @no_skip = ();
	$instance->read_db;
	my $root = $self->{'document_root'};
	my $sh=$instance->db->prepare('select id, name from _wyrd_index');
	$sh->execute;
	while (my $data_ref=$sh->fetchrow_arrayref) {
		my $id = $data_ref->[0];
		my $file = $data_ref->[1];
		if ($file =~ m{^/}) {
			my $exists = -f $root . $file;
			unless ($exists) {
				print $instance->purge_entry($id) . "\n";
			}
		}
	}
	return @no_skip;
}

1;