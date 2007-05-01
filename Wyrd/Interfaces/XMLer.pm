use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Interfaces::XMLer;
our $VERSION = '0.96';
use XML::Simple qw(:strict);

=pod

=head1 NAME

Apache::Wyrd::Interfaces::XMLer - Convenience interface for XML::Simple

=head1 SYNOPSIS

    use base qw(Apache::Wyrd::Interfaces::XMLer Apache::Wyrd);
    
    return $self->_put_data('/var/list.xml',
      $data,
      {
        noattr => 1,
        keyattr => ['name'],
        rootname=>'list',
        suppressempty => 1
      }
    );

=head1 DESCRIPTION

Convenience wrapper for XML::Simple.  Files are stored under the
document root.  Exceptions are caught by eval().

=head1 METHODS

I<(format: (returns) name (arguments after self))>

=over

=item (scalar) C<_get_data> (scalar, hashref)

Open the XML file and read it in as a hashref.  The first argument
should be the document-root-relative filename, the second is the hashref
used to initialize the XML::Simple object.

=cut

sub _get_data {
	my ($self, $file, $xml_init) = @_;
	my $root = $self->dbl->req->document_root;
	if ($file =~ /^\//) {
		$file = $root . $file;
	} else {
		my $path = $self->dbl->self_path;
		$path =~ s|/([^/]+)$|/|;
		$file = $root . $path . $file;
	}
	$xml_init->{forcearray} ||= 1;
	$xml_init->{keyattr} ||= [];
	my $hashref = {};
	eval('$hashref = XMLin($file, %$xml_init)');
	$self->_raise_exception($@) if ($@);
	return $hashref;
}

=pod

=item (scalar) C<_put_data> (void)

Save a hashref as an XML file.  Similar to _get_data.

=cut

sub _put_data {
	my ($self, $file, $data, $xml_init) = @_;
	my $root = $self->dbl->req->document_root;
	if ($file =~ /^\//) {
		$file = $root . $file;
	} else {
		my $path = $self->dbl->self_path;
		$path =~ s|/([^/]+)$|/|;
		$file = $root . $path . $file;
	}
	#put in some defaults
	$xml_init->{keyattr} ||= [];
	$xml_init->{noattr} = 1 unless (defined($xml_init->{noattr}));
	$xml_init->{outputfile} = $file;
	$self->_info("outputting to $file");
	eval ('XMLout($data, %$xml_init)');
	$self->_raise_exception($@) if ($@);
	return;
}

=pod

=back

=head1 BUGS/CAVEATS/RESERVED METHODS

This Interface is scheduled for depreciation.  Use at your own risk.

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item XML::Simple

=back

=head1 LICENSE

Copyright 2002-2007 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

1;
