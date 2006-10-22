use 5.006;
use strict;
use warnings;
no warnings qw(uninitialized);

package Apache::Wyrd::BrowserSwitch;
our $VERSION = '0.94';
use base qw (Apache::Wyrd);

sub _add_version {
	my ($self, $version) = @_;
	$self->raise_exception('Only Apache::Wyrd::Version-derived objects should call _add_version()')
		unless UNIVERSAL::isa($version, 'Apache::Wyrd::Version');
	push @{$self->{'versions'}}, $version;
}

sub _setup {
	my ($self) = @_;
	$self->{'versions'} = [];
}

sub _generate_output {
	my ($self) = @_;
	my $agent = $self->dbl->req->headers_in->{'User-Agent'};
	my $out = '';
	foreach my $version (@{$self->{'versions'}}) {
		$out = $version->_data if ($version->match($agent));
	}
	$out ||= $self->_data;
	return $out;
}

sub _count_attrs

1;