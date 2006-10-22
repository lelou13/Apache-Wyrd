package Apache::Wyrd::Interfaces::IndexUser;

sub _init_index {
	my ($self) = @_;
	return $self->{'index'} if (UNIVERSAL::isa($self->{'index'}, $self->_base_class . '::Index'));
	my $formula = $self->_base_class . '::Index';
	eval("use $formula") unless ($INC{$formula});
	$self->{'index'} = eval($formula . '->new');
	$self->_raise_exception("Failed to open the index: $formula; reason: $@") if ($@);
	return $self->{'index'};
}

sub _dispose_index {
	my ($self) = @_;
	if (UNIVERSAL::isa($self->{'index'}, $self->_base_class . '::Index')) {
		$self->{'index'}->close_db;
	}
	$self->{'index'} = undef;
	return;
}

1;