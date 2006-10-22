package Apache::Wyrd::Site::WidgetIndex;
use base qw(Apache::Wyrd::Services::Index);
use strict;
our $VERSION = '0.94';

=pod

=head1 NAME

Apache::Wyrd::Site::WidgetIndex - Wrapper class to support Widget Class

=head1 SYNOPSIS

  package BASENAME::WidgetIndex;
  use strict;
  use base qw(Apache::Wyrd::Site::WidgetIndex);
  use Apache::Wyrd::Services::Index;
  
  sub new {
      my ($class) = @_;
      my $init = {
          file => '/var/www/indexes/widgetindex.db'
      };
      return Apache::Wyrd::Services::Index::new($class, $init);
  }
  
  1;


=head1 DESCRIPTION

Provides a simple Apache::Wyrd::Services::Index object for storing metadata on
Apache::Wyrd::Site::Widget objects.  Please see Apache::Wyrd::Site::Widget for
why you might need one.

=head1 BUGS/CAVEATS

Not the most efficient way to store Widget information, but quick to implement.

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item Apache::Wyrd

General-purpose HTML-embeddable perl object

=item Apache::Wyrd::Site::Widget

Base object for Widgets - semi-independent objects which enrich the content of a page

=back

=head1 LICENSE

Copyright 2002-2005 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

sub new {
	my ($class, $init) = @_;
	warn ("You can avoid a performance penalty by subclassing Apache::Wyrd::Site::WidgetIndex and defining a new() method that returns a WidgetIndex for your site.");
	$init = {} unless (ref($init) eq 'HASH');
	die "Need a file attribute for Apache::Wyrd::Site::WidgetIndex" unless ($init->{file});
	return Apache::Wyrd::Services::Index::new($class, $init);
}

sub update_entry {
	my ($self, $entry) = @_;
	my $changed = 0;
	my $index = $self->read_db;
	my ($id, $id_is_new) = $self->get_id($entry->index_name);
	$index->db_get("\x02\%$id", my $digest);
	if ($digest ne $entry->index_digest) {
		$index = $self->write_db;
		$self->update_key($id, $entry->index_name);
		$self->update_key("\x00%" . $entry->index_name, $id);
		$self->update_key("\x02%" . $id, $entry->index_digest);
		$changed = 1;
		$index->db_get("\xff%greatest_id", my $greatest_id);
		$index->db_put("\xff%greatest_id", $id) if ($id > $greatest_id);
	}
	$self->close_db;
	return $changed;
}

1;