use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::Interfaces::Setter;
our $VERSION = '0.91';
use Apache::Util;

=pod

=head1 NAME

Apache::Wyrd::Interfaces::Setter - Templating Interface for Wyrds

=head1 SYNOPSIS

    !:information {<tr><td colspan="2">No information</td></tr>}
    ?:information {
      ?:phone{<tr><th>Phone:</th><td>$:phone</td></tr>}
      ?:fax{<tr><th>Fax:</th><td>$:fax</td></tr>}
      ?:email{<tr><th>Email:</th>
        <td><a href="mailto:$:email">$:email</a></td></tr>}
      ?:www{<tr><th>WWW:</th>
        <td><a href="$:www" target="external">$:www</a></td></tr>}
    }

    #interpret enclosed text and set enclosed text to result.
    $wyrd->_data($wyrd->_set());

    #interpret enclosed text and set the item placemarker.
    $wyrd->_data($wyrd->_set({item => 'this is the item'}));

    #interpret given template and set enclosed text to the result.
    $wyrd->_data($wyrd->_set(
      {item => 'this is the item'},
      'This is the item: $:item'
    ));

=head1 DESCRIPTION

The Setter interface give Wyrds a small templating "language" for
placing variables into HTML:  In short summary, there are two kinds of
tokens interpreted by the Setter: a placemarker and a conditional.  For
placemarkers, any valid perl variable name preceded by dollar-colon
("$:") is replaced by the value of that variable.  For conditionals, any
valid perl variable name preceded by an exclamation or question mark
and followed by curly braces enclosing text shows the enclosed text
conditionally if the variable is true ("?:") or false ("!:").  These
conditionals can be nested.

Note that despite the flavor of Set-ting, conditionals are always
interpreted and are considered false on non-existent, undefined, zero,
or '' values, and true on anything else.

The Setter interface provides several "flavors" of Set-ting functions
depending on their purpose.  In general, however, they all accept two
optional variables, one being the hashref of variables to set with, the
second being the text which will be interpreted.  If the second variable
is not provided, it is assumed that the enclosed text is the text to be
processed.  If neither the first or the second is provided, it is also
assumed the CGI environment is the source for the variable substitution.

If the CGI environment is used, the Setter will use the minimum
necessary, only using the items it can clearly find in placemarkers.

=head1 METHODS

I<(format: (returns) name (arguments after self))>

=over

=item (scalar) C<_set> ([hashref], [scalar])

Simplest flavor.  If a place-marked variable doesn't exist as a key in
the first argument (or in the CGI environment if missing), then the
placemarker is not interpreted, and remains untouched.

=cut

sub _set {
	my ($self, $hash, $temp) = @_;
	#if a target ($temp) is provided, use it instead of the data
	$temp ||= $self->{'_data'};
	$hash = $self->_cgi_hash($temp) unless (ref($hash) eq 'HASH');
	#first do conditionals
	$temp = $self->_regexp_conditionals($hash, $temp);
	#then do replacements
	foreach my $i (sort {length($b) <=> length($a)} keys(%$hash)) {
		#sorted so that the longest go first, avoiding problems where one variable (key) name is a
		#substring of another
		next unless ($i);#this is to prevent strange tied hashes from creating iloops
		$self->_verbose("temp is '$temp', i is '$i' and value is '$$hash{$i}'");
		$temp =~ s/\$:$i/$$hash{$i}/gi;
	}
	return $temp;
}

=pod

=item (scalar) C<_clear_set> ([hashref], [scalar])

Same as _set, but wipes anything remaining that looks like a placemarker.

=cut

sub _clear_set {#clear out any unset values.
	my ($self, $hash, $temp) = @_;
	my $result = $self->_set($hash, $temp);
	$result =~ s/\$:[a-zA-Z_0-9]+//g;
	return $result;
}

=pod

=item (scalar) C<_clean_set> ([hashref], [scalar])

More perl-ish.  If the placemarker is undefined OR false, it is not
interpreted.

=cut

sub _clean_set {
	#For making "set" more perl-ish and handling conditionals as if ''/null/undef value == undefined
	my ($self, $hash, $temp) = @_;
	if (ref($hash) eq 'HASH') {
		my %newhash = %$hash;
		foreach my $key (keys(%newhash)) {
			delete $newhash{$key} unless ($newhash{$key});#undefine missing bits for setter
		}
		return $self->_set(\%newhash, $temp);
	}
	return $self->_set($hash, $temp);
}

=pod

=item (scalar) C<_text_set> ([hashref], [scalar])

More text-ish and perl-ish.  If the placemarker is undefined OR false,
it is not interpreted.  Anything else that looks like a placemarker
after interpretation is finished is wiped out.

=cut

sub _text_set {
	#Like "_clean_set", but also interprets arrays and uses the _clear_set.
	#used for outputting directly to web pages
	my ($self, $hash, $temp) = @_;
	if (ref($hash) eq 'HASH') {
		my %newhash = %$hash;
		foreach my $key (keys(%newhash)) {
			$newhash{$key} = join ', ' , @{$newhash{$key}} if (ref($newhash{$key})) eq 'ARRAY';
			$newhash{$key} = '' unless ($newhash{$key} or ($newhash{$key} eq '0'));
		}
		return $self->_clear_set(\%newhash, $temp);
	}
	return $self->_clear_set($hash, $temp);
}

=pod

=item (scalar) C<_quote_set> ([hashref], [scalar])

More SQL-ish, but not CGI-ish.  A blank hashref is used in place of the
CGI environment when passed no parameters.  Placemarkers are replaced
with the quote function of DBI via the Wyrd->dbl->quote function so as
to be used in SQL queries.

=cut

sub _quote_set {
	my ($self, $hash, $temp) = @_;
	#if a target ($temp) is provided, use it instead of the data
	$temp = $self->{'_data'} unless ($temp);
	$hash = {} unless (ref($hash) eq 'HASH');
	#first do conditionals
	$temp = $self->_regexp_conditionals($hash, $temp);
	#then do quotations, altering a copy, not the original
	my %hash = %$hash;
	foreach my $i (keys(%hash)) {
		$hash{$i}=$self->dbl->dbh->quote($hash{$i});
		$hash{$i}='NULL' if ($hash{$i} eq q(''));
	}
	#then do replacements
	foreach my $i (keys(%hash)) {
		next unless ($i);#this is to prevent strange tied hashes from creating iloops
		$self->_verbose("temp is $temp, i is $i and hash is $$hash{$i}");
		$temp =~ s/\$:$i/$hash{$i}/gi;
	}
	return $temp;
}

=item (scalar) C<_cgi_quote_set> ([scalar])

same as C<_quote_set>, but with the CGI environment option forced and no
interpreted hash option.

=cut

sub _cgi_quote_set {
	my ($self, $temp) = @_;
	#if a target ($temp) is provided, use it instead of the data
	$temp = $self->{'_data'} unless ($temp);
	#first get a clean hash -- no point in doing conditionals if undef is changed to NULL
	my $hash = $self->_cgi_hash($temp);
	#then do conditionals
	$temp = $self->_regexp_conditionals($hash, $temp);
	#then do quotations
	$hash = $self->_cgi_hash($temp, 'quoted');
	#then do replacements
	foreach my $i (keys(%$hash)) {
		next unless ($i);#this is to prevent strange tied hashes from creating iloops
		$self->_verbose("temp is $temp, i is $i and hash is $$hash{$i}");
		$temp =~ s/\$:$i/$$hash{$i}/gi;
	}
	return $temp;
}

=pod

=item (scalar) C<_escape_set> ([hashref], [scalar])

More HTML-form-ish but not CGI-ish.  A blank hashref is used in place of
the CGI environment when passed no parameters.  Values are HTML escaped
so they can be used within <input type="text"> tags in HTML.

=cut

sub _escape_set {
	my ($self, $hash, $temp) = @_;
	#if a target ($temp) is provided, use it instead of the data
	$temp = $self->{'_data'} unless ($temp);
	$hash = {} unless (ref($hash) eq 'HASH');
	#first do conditionals
	$temp = $self->_regexp_conditionals($hash, $temp);
	#then do quotations, altering a copy, not the original
	my %hash = %$hash;
	foreach my $i (keys(%hash)) {
		$hash{$i}=Apache::Util::escape_html($hash{$i});
	}
	#then do replacements
	foreach my $i (keys(%hash)) {
		next unless ($i);#this is to prevent strange tied hashes from creating iloops
		$self->_verbose("temp is $temp, i is $i and hash is $$hash{$i}");
		$temp =~ s/\$:$i/$hash{$i}/gi;
	}
	return $temp;
}

=pod

=item (scalar) C<_cgi_escape_set>  ([scalar])

same as C<_escape_set>, but with the CGI environment option forced and
no interpreted hash option.

=cut

sub _cgi_escape_set {
	my ($self, $temp) = @_;
	#if a target ($temp) is provided, use it instead of the data
	$temp = $self->{'_data'} unless ($temp);
	#first get a clean hash -- no point in doing conditionals if undef is changed to NULL
	my $hash = $self->_cgi_hash($temp);
	#then do conditionals
	$temp = $self->_regexp_conditionals($hash, $temp);
	#then do quotations
	$hash = $self->_cgi_hash($temp, 'escaped');
	#then do replacements
	foreach my $i (keys(%$hash)) {
		next unless ($i);#this is to prevent strange tied hashes from creating iloops
		$self->_verbose("temp is $temp, i is $i and hash is $$hash{$i}");
		$temp =~ s/\$:$i/$$hash{$i}/gi;
	}
	return $temp;
}

=item (scalar) C<_regexp_conditionals> (hashref, scalar)

internal method for performing conditional interpretation.

=cut

sub _regexp_conditionals {
	my ($self, $hash, $string) = @_;
	my $result = undef;
	do {
		$result =
			$string =~ s/(\?:([a-zA-Z_][a-zA-Z_0-9]*)\{(?!.*\{)([^\}]*)\})/defined($$hash{$2})?$3:undef/ges;
		$result ||=
			$string =~ s/(\!:([a-zA-Z_][a-zA-Z_0-9]*)\{(?!.*\{)([^\}]*)\})/defined($$hash{$2})?undef:$3/ges;
	} while ($result);
	return $string;
}

=item (scalar) C<_cgi_hash> (hashref, scalar)

internal method for interpreting the CGI environment into the template
data hashref.

=cut

sub _cgi_hash {
	my ($self, $temp, $modifier) = @_;
	my $hash = {};
	my @params = ();
	unless ($temp) {
		#give up and use CGIs params
		@params = $self->dbl->param;
	} else {
		#guess at the params from the template
		@params = ($temp =~ m/[\$\?\!]\:([a-zA-Z_][a-zA-Z0-9_]+)/g);
	}
	foreach my $param (@params) {
		if ($modifier eq 'escaped') {
			$hash->{$param} = Apache::Util::escape_html(scalar($self->dbl->param($param)));
		} elsif ($modifier eq 'quoted') {
			#scalar is used because of some funny business in dbh -- worth investigating?
			$hash->{$param} = $self->dbl->dbh->quote(scalar($self->dbl->param($param)));
		} else {
			$hash->{$param} = $self->dbl->param($param);
		}
		$self->_verbose("$param = $$hash{$param}");
	}
	$self->_debug("Found params ->" . join ', ', @params);
	return $hash
}

=pod

=back

=head1 BUGS/CAVEATS/RESERVED METHODS

"$:" is a variable in perl, so be sure to escape or single-quote your
in-code templates.  If you start seeing B<-variablename> in your pages,
you'll know why.

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