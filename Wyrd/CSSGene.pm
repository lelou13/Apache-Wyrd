#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details
use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::CSSGene;
our $VERSION = '0.85';
use base qw (Apache::Wyrd::Interfaces::Setter Apache::Wyrd);
use BerkeleyDB;
use BerkeleyDB::Btree;

my $default_deviation = 20;
my $default_population = 20;

=pod

=head1 NAME

Apache::Wyrd::CSSGene - Example Wyrd for breeding CSS stylesheets

=head1 SYNOPSIS

    <BASENAME::CSSGene>
      <BASENAME::Template>
        <style type="text/css">
          TD.developing {
            font-size: #10-32#px;
            background-color: #@000000,00AAFF,FFFFFF@;
            margin: *
          }
        </style>
      </BASENAME::Template>
    </BASENAME::CSSGene>

=head1 DESCRIPTION

This Wyrd is provided as an example.  Gived a Wyrd::Template stylesheet
named 'stylesheet', it will use a genetic algorithm to aid in the
fine-tuning of a web page CSS.  Within this stylesheet template, it will
replace any sequence of #number-number# with values between those number
ranges, or any * with a number within the default ranges, or any
@value,value,value@ with one of the indicated values.

This will allow a stylesheet to be "bred" out of many elements within
acceptable parameters until the desired look is acheived.  It will do so
by providing an interface that allows the "more fit" style to be
selected and for bad stock to be culled.

=head2 HTML ATTRIBUTES

=over

=item population

size of the gene pool. (default: 20)

=item sample

size of mating pool. (default: same as population)

=item tempdir

temporary database to store state invformation on the gene pool.

=item deviation

amount of deviation for '*' values (@xx@ and #xx# values provide their
own range)

=back

=head2 PERL METHODS

NO PUBLIC METHODS

=head1 BUGS/CAVEATS/RESERVED METHODS

(Besides bordering on the absurd) Reserves the _format_output method.

=cut

sub _format_output {
	my ($self) = @_;
	my $temp_dir = ($self->{'tempdir'} || '/tmp');
	my $env = BerkeleyDB::Env->new(
		-Home			=> "$temp_dir",
		-Flags			=> DB_INIT_LOCK | DB_INIT_LOG | DB_INIT_MPOOL,
		-LockDetect		=> DB_LOCK_DEFAULT
	);

	#define the genotype based on the template
	my $genotype = $self->_get_template;

	my $pop_size = ($self->{'population'} || $default_population);
	my $sample_size = ($self->{'sample'} || $pop_size);
	my $generation = ($self->dbl->param('generation') || 1);

	#open up a DB file to use as the pool, or open an existing one
	my $session_id = $self->dbl->param('session_id');
	my %pool = ();
	$session_id = (time . rand()) unless ($session_id);
	my $savannah = tie (
		%pool, 'BerkeleyDB::Btree',
		-Filename => "$temp_dir/Wyrd.Savannah.$session_id",
		-Flags => DB_CREATE,
		-Env => $env,
		-Mode => 0640
	);
	$self->raise_exception("Can't open/create the gene pool: $temp_dir/Wyrd.Savannah.$session_id") unless ($savannah);

	my $rating = ($self->dbl->param('rating') + 0);
	my $control = $self->dbl->param('control');
	my %studs = ();
	my $counter = 1;
	unless ($rating or $control) {
		for (my $animal = 1; $animal <= $pop_size; $animal++) {
			$pool{$animal} = $self->_new_animal($genotype);
		}
	} else {
		while ($self->dbl->param("animal$counter") ne undef) {
			$studs{$pool{$counter}} = $self->dbl->param("animal$counter");
			$counter++;
		}
		if ($control eq 'replace') {
			$pool{$counter} = $self->_new_animal($genotype);
		} else {
			$studs{$pool{$counter}} = $rating;
			$counter++;
		}
		if ($counter > $sample_size) {
			#mate now
			#warn q(mating...);
			$generation++;
			my @pecking_order = sort {$studs{$a} <=> $studs{$b}} keys(%studs);
			my $alpha = undef;
			my $matings = 1;
			my @animals = keys %pool;
			#fisher-yates shuffle of animals for random matings
			for (my $i = @animals; --$i; ) {
				my $j = int rand ($i+1);
				next if $i == $j;
				@animals[$i, $j] = @animals[$j, $i]
			}
			foreach my $animal (@animals) {
				if (not($alpha) or ($matings > $studs{$alpha})) {
					$alpha = pop @pecking_order;
					$matings = 1;
					#warn ("Current Alpha is $alpha, with a rating of $studs{$alpha}");
				}
				last unless ($alpha);#run out of alphas?  No matings, then.
				my @alpha = split ':', $alpha;#get the alpha's genes
				my @genes = split ':', $pool{$animal}; #get this animals genes
				my $half = scalar(@genes)/2;
				my %cell = ();
				my $gene_counter = 0;
				foreach my $cell (@genes) {
					$cell{$gene_counter} = rand();
					$gene_counter++;
				}
				my $replaced = 0;
				foreach my $gene (sort {$cell{$a} <=> $cell{$b}} keys(%cell)) {
					$genes[$gene] = ((rand > ($self->{mutations}/1000000)) ? $alpha[$gene] : $self->_new_gene($genotype->{$gene}));
					$replaced++;
					last if ($replaced > $half);
				}
				$matings++;
				#warn "$alpha mates with\n$pool{$animal} to produce\n" . join (':', @genes);
				$pool{$animal} = join (':', @genes);
			}
			#new gene pool -- restore pointer to beginning
			$counter = 1;
		}
	}
	#counter should at this point be the # of the current beast
	my %out = ();
	for (my $animal = 1; $counter > $animal; $animal++) {
		$out{'record'} .= qq(<input type="hidden" name="animal$animal" value="$studs{$pool{$animal}}">);
	}
	my $current_animal = $pool{$counter};
	$out{'variant'} = $counter;
	$counter = 0;
	foreach my $gene (split ':', $current_animal) {
		$self->{'stylesheet'} =~ s/_VARIABLE_$counter\_/$gene/;
		$counter++;
	}
	$out{'record'} ||= '';
	my $buttons = '';
	for (my $rating = 1; $rating <= ($self->{'scale'} || 10); $rating++) {
		$buttons .= qq(<input type="submit" name="rating" value="$rating">);
	}
	$buttons .= qq(<input type="submit" name="control" value="replace">);
	$out{'ratebuttons'} = $buttons;
	$out{'session_id'} = $session_id;
	$out{'generation'} = $generation;
	$out{'url'} = $self->dbl->self_path;
	$out{'stylesheet'} = $self->{'stylesheet'};
	$out{'text'} = $self->{'_data'};
	my $page = <<'__PAGE__';
<form action="$:url" method="post">
<P>Generation: $:generation, variant $:variant</P>
<P>Rate this: $:ratebuttons</P>
<input type="hidden" name="session_id" value="$:session_id">
<input type="hidden" name="generation" value="$:generation">
$:record
$:stylesheet
$:text
</form>
__PAGE__
	$self->_data($self->_set(\%out, $page));
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

Copyright 2002-2004 Wyrdwright, Inc. and licensed under the GNU GPL.

See LICENSE under the documentation for C<Apache::Wyrd>.

=cut

sub _new_animal {
	my ($self, $genotype) = @_;
	my @genes = ();
	foreach my $gene (sort {$a <=> $b} keys %$genotype) {
		push @genes, $self->_new_gene($genotype->{$gene});
	}
	return join ':', @genes;
}

sub _new_gene {
	my ($self, $gene) = @_;
	unless ($gene->{'items'}) {
		return int(rand($gene->{'deviation'} + 1) + $gene->{'offset'});
	} else {
		my $pick = int(rand($gene->{'picks'}));
		return $gene->{'items'}->[$pick];
	}
}

sub _get_template {
	my ($self) = @_;
	my $id = 0;
	my %gene = ();
	$self->_raise_exception("Must define 'stylesheet' template to use this object") unless ($self->{'stylesheet'});
	my $continue = 0;
	do {
		$continue = $self->{'stylesheet'} =~ s/(.+?)(\#(\d+)\-(\d+)\#|\*|\@([^\@]+?)\@)/$1\_VARIABLE_$id\_/s;
		if ($continue) {
			my (undef, $variable, $offset, $max, $variations) = ($1, $2, $3, $4, $5);
			my $deviation = $max - $offset;
			if ($variations) {
				$deviation = 0;
				my @varieties = split ",", $variations;
				$gene{$id} = {picks => scalar(@varieties), items => \@varieties}
			}
			$gene{$id} = {offset => $offset, deviation => $deviation} if ($deviation);
			$gene{$id} ||= {offset => 0, deviation => ($self->{'deviation'} || $default_deviation)};
			$id++;
		}
	} while ($continue);
	return \%gene;
}

1;