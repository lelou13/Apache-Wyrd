#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details
use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Interfaces::Indexable;
our $VERSION = '0.85';
use Digest::MD5 qw(md5_hex);

=pod

=head1 NAME

Apache::Wyrd::Interfaces::Indexable - Pass metadata to Wyrd Index service

=head1 SYNOPSIS

NONE

=head1 DESCRIPTION

Indexable provides the minimum methods required by an object to be indexed using
the Apache::Wyrd::Services::Index object.  An indexable object can be inserted
into the index via the C<update_entry> method of the index.

=head1 METHODS

I<(format: (returns) name (arguments after self))>

=over

=item (scalar) C<no_index> (void)

Returns true if the item should not be indexed.  Traditionally supplied via the
B<noindex> flag attribute of a Wyrd.

=cut

sub no_index {
	my ($self) = @_;
	return $self->_flags->noindex;
}

=pod

=item (scalar) C<force_update> (void)

Tells the index to ignore timestamp and digest arguments, and always update the
entry for this object even if there is no apparent change

=cut

sub force_update {
	return 0;
}

=pod

=item (scalar) C<index_foo> (void)

Where B<foo> is at a minimum of name, timestamp, digest, data, title, and
description.  Any attributes specified in the B<attributes> option of the
Apache::Wyrd::Services::Index object will also need to be implemented in an
indexable object.  If the attribute is a map, it needs only to return a string
of tokens separated by whitespace, punctuation optional.

Because the assumption is that the indexible item will probably be a web page,
the path to the file from the server root is the traditional "name" of the item.
As such, when the results of a search are returned by the Index, the B<href>
attribute of a link to the page is created from the B<name> attribute.

Also in this tradition, the default map for searching uses the tokens provided
by C<index_data> as the basis for the index' C<word_search>.

=cut

sub index_name {
	my ($self) = @_;
	return $self->dbl->self_path;
}

sub index_timestamp {
	my ($self) = @_;
	return $self->dbl->mtime;
}

sub index_digest {
	my ($self) = @_;
	return md5_hex($self->index_data . $self->index_title . $self->index_description);
}

sub index_data {
	my ($self) = @_;
	return $self->{'title'} . ' ' . $self->{'description'} . ' ' . $self->{'_data'};
}

sub index_title {
	my ($self) = @_;
	return $self->{'title'};
}

sub index_description {
	my ($self) = @_;
	return $self->{'description'};
}

=pod

=back

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item Apache::Wyrd

General-purpose HTML-embeddable perl object

=item Apache::Wyrd::Services::Index

Berkeley DB-based reverse index for search engines and other meta-data-bases.

=back

=head1 LICENSE

Copyright 2002-2004 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

1;