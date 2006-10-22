package Apache::Wyrd::Site::EditablePage;
use strict;
use base qw(Apache::Wyrd::Site::Page);
use Apache::Wyrd::Services::SAK qw(slurp_file spit_file token_parse strip_html);
use XML::Dumper;
use Apache::Wyrd::Services::CodeRing;
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details


sub _encoded_metadata {
	my ($self) = @_;
	my @attribs = $self->_attributes;
	my %meta = ();
	foreach my $attrib (@attribs) {
		$meta{$attrib} = $self->{$attrib};
	}
	my $cr = Apache::Wyrd::Services::CodeRing->new;
	my $xd = XML::Dumper->new;
	my $data = $xd->pl2xml(\%meta);
	$data = ${$cr->encrypt(\$data)};
	return $data;
}

sub _do_edits {
	my ($self) = @_;
	my $action = $self->dbl->param('_wyrd_edit');
	if ($action eq 'expire') {
		my $tags = $self->{'tags'};
		my @tags = token_parse($tags);
		@tags = grep {$_ ne 'new'} @tags;
		$self->{'tags'} = join ', ', @tags;
	}
}

sub _edits_ok {
	my ($self) = @_;
	return 1;
	return $self->dbl->user->auth('edit_pages');
}

sub _page_edit {
	my ($self) = @_;
	return undef unless ($self->dbl->param('_wyrd_edit') and $self->_edits_ok);
	$self->_do_edits;
	my @valid_attribs = $self->_attribs;
	my @attribs = grep {$_ !~ /^_|loglevel|dielevel|index|file/} keys %{$self};
	my %use = map {$_ => 1} @attribs;
	my %additional = %use;
	map {delete($additional{$_})} @valid_attribs;
	my @also = keys %additional;
	my @flags = grep {$self->_flags->{$_}} keys %{$self->_flags};
	if (@flags) {
		$use{'flags'} = 1;
		$self->{'flags'} = join ', ', @flags;
	}
	my $text = '<' . $self->_class_name;
	foreach my $attribute (@valid_attribs, @also) {
		next unless $use{$attribute};
		$text .= qq(\n\t$attribute=") . $self->{$attribute} . qq(")
	}
	$text .= qq(\n>) . $self->_data . qq(\n</) . $self->_class_name . qq(>\n);
	spit_file($self->dbl->file_path, $text) || $self->_error("Could not write to " . $self->_self_file);
	delete $self->{'flags'};
}

1;