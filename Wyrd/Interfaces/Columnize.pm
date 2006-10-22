use strict;
package Apache::Wyrd::Interfaces::Columnize;

=pod

takes an array of items and arranges them on a table.  Supported table attributes should be place
in the Columnize-ed Wyrd.  Supported attributes: cellpadding, cellspacing, and <td class>.

=cut

sub _columnize {
	my($self, @items) = @_;

	my $cols = ($self->{'columns'} || 1);
	my $class = ($self->{'class'});
	$class = qq( class="$class") if $class;
	my $cellpadding = ($self->{'cellpadding'} || '0');
	my $cellspacing = ($self->{'cellspacing'} || '0');

	my $out = undef;
	my $rows = scalar(@items) ? int(1 + (@items/$cols)) : 1;
	if ($self->{'direction'} eq 'down') {#only re-map the array to the down-first direction if specified
		my (@newitems, $counter, $rowcounter) = ();
		my $count = $#items;
		while (@items) {#map a new array by iterating across the old array horizontal-wise
			my $cursor = $counter;
			while ($cursor <= $count) {
				my $item = shift @items;
				$newitems[$cursor] = $item;
				$cursor += $cols;
			}
			$counter++;
		}
		while (@newitems < ($cols * $rows)) {#fill in additional items;
			push @newitems, '&nbsp';
		}
		@items = @newitems;
	}
	while (@items) {
		$out .= join (
			'',
			'<tr>',
			(
				map {qq(<td$class>$_</td>)}
				map {$_ || '&nbsp;'}
				splice(@items, 0, $cols)
			),
			'</tr>'
		);
	}
	$out =  qq(<table border="0" cellpadding="$cellpadding" cellspacing="$cellspacing">$out</table>);
	return $out;
}

1;