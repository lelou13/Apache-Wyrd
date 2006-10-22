use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Input::Preload;
our $VERSION = '0.94';
use base qw(Apache::Wyrd::Interfaces::Setter Apache::Wyrd);
use Apache::Wyrd::Services::SAK qw(token_parse);

=pod

=head1 NAME

Apache::Wyrd::Input::Preload - Specify preloaded form values from CGI

=head1 SYNOPSIS

  <BASENAME::Form>
    <BASENAME::Form::Template name="options">
    <BASENAME::Input::Preload params="username, preferred_items" />
      <b>Username:</b><br>
      <BASENAME::Input name="username" type="text" />
	  <BASENAME::Input::Set name="options" type="checkboxes" options="Foo, Bar" />
    </BASENAME::Form::Template>
    <BASENAME::Form::Template name="saved">
    <H1>Status: $:_status</H1>
    <HR>
    <P>$:_message</P>
    </BASENAME::Form::Template>
  </BASENAME::Form>

=head1 DESCRIPTION

The Input::Preload Input Wyrd will load the values passed to it via the CGI into
the opening Template of a form Wyrd.  The inputs which are to be preloaded are
specified in the param attribute and are loaded into inputs with that parameter
name.

This allows a Form Wyrd to be preloaded from a regular HTML form or from a
different Form Wyrd rather than duplicating Forms across different pages.

=head2 HTML ATTRIBUTES

=over

=item param, params

The cgi parameters which contain the values to be preloaded, separated by either
commas or whitespace.

=back

=head1 BUGS/CAVEATS

Reserves the _format_output method.

=cut

sub _format_output {
	my ($self) = @_;
	my $out = '';
	my $base_class = $self->base_class;
	my @params = token_parse($self->{'params'} || $self->{'param'});
	foreach my $param (@params) {
		my @values = $self->dbl->param($param);
		foreach my $value (@values) {
			$out .= qq(<) . $base_class . qq(::Input type="hidden" name="$param" value="$value" />);
		}
	}
	$self->_data($out);
}


=pod

=head1 AUTHOR

Barry King E<lt>wyrd@nospam.wyrdwright.comE<gt>

=head1 SEE ALSO

=over

=item Apache::Wyrd

General-purpose HTML-embeddable perl object

=back

=head1 LICENSE

Copyright 2002-2005 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

1;