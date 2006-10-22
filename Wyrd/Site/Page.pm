package Apache::Wyrd::Site::Page;
use strict;
use base qw(Apache::Wyrd::Interfaces::IndexUser Apache::Wyrd::Interfaces::Indexable Apache::Wyrd::Interfaces::Setter Apache::Wyrd);
use Apache::Wyrd::Services::SAK qw(token_parse strip_html);
use Apache::Wyrd::Services::FileCache;
use Digest::SHA qw(sha1_hex);
our $VERSION = '0.94';

=pod

This is beta software.  Documentation Pending.  See Apache::Wyrd for more info.

=cut
#Copyright barry king <barry@wyrdwright.com> and released under the GPL.
#See http://www.gnu.org/licenses/gpl.html#TOC1 for details

sub _setup {
	my ($self) = @_;
	$self->_init_state;
	$self->_check_auth;
	$self->_init_index;
	$self->_page_edit;
	unless ($self->_flags->nofail) {
		my $name = $self->index_name;
		if ($name eq $self->{'original'}) {
			if ($name =~ m/^\//) {
				$self->_raise_exception("Original file doesn't exist ($name).  Use the nofail flag to override this error.") unless (-f $self->dbl->req->document_root . $name);
			}
		}
	}
}

#state of the widgets is stored by an alphanumeric code where a=1 and Z=62, limiting
#widget controlss to 62 states and widgets to 62 controls
my @encode = split //, 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
my $counter = 0;
my %decode = map {$_, $counter++} @encode;

sub _init_state {
	my ($self) = @_;
	#initialize the counter which will record the number of widgets
	$self->{'_state_counter'} = 0;

	#if the state information has arrive via CGI, set the _override marker to indicate that
	#the new state will have precedence over the default state, and decode that information
	#into the _state holding key
	my $string = $self->{'_override'} = $self->_state_string;
	$self->{'_state'} = $self->_decode_state($string) if ($string);
}

sub _state_digit {
	return $decode{$_[1]};
}

sub _state_symbol {
	return $encode[$_[1]];
}

sub _decode_state {
	my ($self, $string) = @_;
	#warn $string;
	my ($oldstate, $widget, $newstate) = split ':', $string;
	my @state = split //, $oldstate;
	my @array = ();
	while (@state) {
		my $controls = $self->_state_digit(shift @state);
		#warn $controls;
		my @controls = ();
		while ($controls) {
			push(@controls, $self->_state_digit(shift @state));
			$controls--;
		}
		push @array, \@controls;
	}
	#warn 'Decoded state: ' . Dumper(\@array);
	my ($control, $value) = split //, $newstate;
	$array[$widget]->[$self->_state_digit($control)]=$self->_state_digit($value);
	#warn 'Decoded state, with change: ' . Dumper(\@array);
	return \@array;
}

sub _encode_state {
	my ($self) = @_;

	#state emerges from the _register_child method of the widgets as an array of 'widgets'
	#each of which are an array of the current value of all widget controls.
	my $state = $self->{'_state'};
	#warn 'Pre-encoded state: ' . Dumper($state);

	#state will be encoded as:
	#	first char: number of widget controls
	#	second char: state of first widget
	#	third char: state of second widget
	#	fourth char: .....
	my @sequence = ();

	foreach my $widget (@$state) {
		#go through each widget (which have registered their controls via the
		#widget controls' _register_child method), and encode it by first taking
		#the number of controls in the widget and encoding that.
		push @sequence, $self->_state_symbol(scalar(@$widget));

		foreach my $value (@$widget) {
			#then put the value out of the possible values into the next char
			#until all the widget controls are accounted for.
			push @sequence, $self->_state_symbol($value);
		}
	}
	return join '', @sequence;
}

#returns the value of the current CGI variable for the state.
sub _state_string {
	my ($self) = @_;
	return $self->dbl->param($self->_state_marker);
}

=pod

=item (void) C<_state_marker> (void)

Provides a string of characters which will be globally replaced at runtime in
order to maintain state between page-views.  All Widget Controls (see
C<Apache::Wyrd::Site::WidgetControl>) will need to include this in information
submitted to the next page view in order to maintain consistent state between
page views.

=cut

sub _state_marker {
	my ($self) = @_;
	return '#!#_wyrd_site_page_state#!#';
}

sub _set_state {
	my ($self) = @_;
	my $state = $self->_encode_state;
	my $marker = $self->_state_marker;
	$self->{'_data'} =~ s/$marker/$state/g;
}

=pod

=item (void) C<get_state> (void)

This method is called by Widgets on the page to determine their overall state.
The widget passes a reference to itself as the argument of the method.  The Page
Object uses this method to obtain information on Widgets on the page in order to
track their current state and to give their controls a switch to use to pass as
a CGI variable in order to manipulate this state, changing the attributes of the
Widget.

=cut

sub get_state {
	my ($self, $widget) = @_;
	#warn 'widget counter is ' . $self->{'_state_counter'};
	$widget->{'_widget_state_name'} = $self->{'_state_counter'};

	#if CGI data has been detected, prefer it over the default
	if ($self->{'_override'}) {

		#check to see if the widget in its default state registered itself on page load
		unless (ref($self->{'_state'}->[$self->{'_state_counter'}]) eq 'ARRAY') {
			#whoops!  the number of widgets has grown.  Assume the programmer knows
			#what is being done, so initialize an ARRAYREF for the widget, but log
			#this as an error anyway.
			$self->_error('Widget tracking state not initialized.  Assume widget number has grown');
			$self->{'_state'}->[$self->{'_state_counter'}] = $self->_read_widget_state($widget);
		}

		my @state = @{$self->{'_state'}->[$self->{'_state_counter'}]};#copy array to preserve actual state
		#hash of attributes under the control of widgetcontrols
		my %attr = ();

		#hash of the possible values the collective controls for a given attribute may have
		my %this_attr = ();
		my $attr_counter = 1;

		#go through each registered widget in order.
		foreach my $child (@{$widget->{'_children'}}) {
			#skip non-widget controls
			next unless UNIVERSAL::isa($child, 'Apache::Wyrd::Site::WidgetControl');

			#does this child have an attribute unlike other attributes?
			unless ($attr{$child->{'attribute'}}) {
				#assign it a number and indicate this attribute has been found
				$attr{$child->{'attribute'}} = $attr_counter++;
			}

			#make the child's "switch" out of the widget number, a colon,
			#the code for the attribute that's changing, and the value of
			#the choice of attribute.
			$child->{'_switch'} =  $self->{'_state_counter'}
								 . ':'
								 . $self->_state_symbol($attr{$child->{'attribute'}} - 1)
								 . $self->_state_symbol($this_attr{$child->{'attribute'}});
			if ($state[$attr{$child->{'attribute'}} - 1] == 0) {
				#warn 'found ' . $child->{'attribute'} . ' of ' . $child->{'value'};
				#we've hit the current state for that attribute, set the attribute of the widget to that value
				my $on_value = 1;
				$on_value = 0 if ($child->_flags->signal); #if a control is a signal, it's never "on", but sends a one-time value
				$child->{'_on'} = $on_value; 
				$widget->{$child->{'attribute'}} = $child->{'value'};
			} else {
				$child->{'_on'} = 0;
			}
			$this_attr{$child->{'attribute'}}++;
			$state[$attr{$child->{'attribute'}} - 1]--;
		};
	} else {
		#We don't know the state.  Read it off of the defaults
		$self->{'_state'}->[$self->{'_state_counter'}] = $self->_read_widget_state($widget);
	}
	$self->{'_state_counter'}++;
}

sub _read_widget_state {
	my ($self, $widget) = @_;
	my @state = ();
	my %attr = ();
	my %this_attr = ();
	my $attr_counter = 1;
	foreach my $child (@{$widget->{'_children'}}) {
		unless ($attr{$child->{'attribute'}}) {
			$attr{$child->{'attribute'}} = $attr_counter++;
		}
		$widget->{$child->{'attribute'}} ||= $child->{'value'};
		$widget->{$child->{'attribute'}} = $child->{'value'} if ($child->_flags->default);
		if ($widget->{$child->{'attribute'}} eq $child->{'value'}) {
			$state[$attr{$child->{'attribute'}} - 1] = $this_attr{$child->{'attribute'}};
			$child->{'_on'} = 1;
		}
		#give the child a "name" it passes via link
		$child->{'_switch'} =  $self->{'_state_counter'}
							 . ':'
							 . $self->_state_symbol($attr{$child->{'attribute'}} - 1)
							 . $self->_state_symbol($this_attr{$child->{'attribute'}});
		$this_attr{$child->{'attribute'}}++;
	};
	return \@state
}

sub _check_auth {
	my ($self) = @_;
	#warn 'here, authorizing with an allow of ' . $self->{'allow'};
	if ($self->{'allow'}) {
		return undef if($self->_override_auth_conditions);
		unless ($self->dbl->user->username) {
			#warn 'here, about to ask for a redirect';
			my $hash = $self->_auth_hash;
			while (my ($key, $value) = each %$hash) {
				$self->dbl->req->dir_config->add($key, $value);
			}
			#$self->dbl->req->dir_config->add('AuthLevel', $self->{'allow'});
			$self->abort('request authorization');
			die "abort failed.";
		}
		if ($self->dbl->user->auth($self->{'allow'}, $self->{'deny'})) {
			return;
		}
		my $redirect = $self->dbl->req->dir_config('UnauthURL');
		if ($redirect) {
			$self->abort($redirect);
			die "abort failed.";
		}
		$self->_data($self->_unauthorized_text);
	}
	#warn 'here about tor return from check_auth';
	return;
}

sub _override_auth_conditions {
	my ($self) = @_;
	my $addrs = $self->dbl->req->dir_config('trusted_ipaddrs');
	return 0 unless ($addrs);
	my @trusted_ips = split /\s+/, $addrs;
	my $ip = $self->dbl->req->connection->remote_addr;
	return 1 if (grep {$_ eq $ip} @trusted_ips);
	return 0;
}

sub _unauthorized_text {
	my ($self) = @_;
	return '<h1>Unauthorized</h1><hr>You are not authorized to view this document';
}

sub _page_edit {
	my ($self) = @_;
	return;
}

sub _attribs {
	my ($self) = @_;
	return qw(section title shorttitle description keywords doctype published expires tags parent flags);

}

sub _format_output {
	my ($self) = @_;
	my $response = $self->index->update_entry($self);
	$self->_info($response);
	$self->_set_state;
	my $head = join ('/', $self->dbl->req->document_root, 'lib/head.html');
	my $file = join ('/', $self->dbl->req->document_root, 'lib/body.html');
	my $template = $self->get_cached($head);
	my $title = $self->{'title'};
	my $keywords = $self->{'keywords'};
	my $description = $self->{'description'};
	my $meta = $self->{'meta'};
	$template =~ s/<\/head>/\n$meta\n<\/head>/ if ($meta);
	my $lib = $self->{'lib'};
	if ($lib) {
		my @inserts = token_parse($lib);
		foreach my $lib (@inserts) {
			$lib =  join ('/', $self->dbl->req->document_root, 'lib', $lib);
			$lib = $self->get_cached($lib);
			$template =~ s/<\/head>/$lib\n<\/head>/;
		}
	}
	$title =~ s/\s+/ /g;
	$keywords =~ s/\s+/ /g;
	$description =~ s/\s+/ /g;
	$template = $self->_set({title => strip_html($title), keywords => strip_html($keywords), description => strip_html($description)}, $template);
	$template .= $self->get_cached($file);
	$self->_process_template($template);
	return;
}

sub _generate_output {
	my ($self) = @_;
	$self->_dispose_index;
	return $self->SUPER::_generate_output;
}

#index-dependent attribute list
sub _attribute_list {
	my ($self) = @_;
	return ($self->index->attribute_list, $self->SUPER::attribute_list);
}

sub _map_list {
	my ($self) = @_;
	return $self->index->map_list;
}

#overloads Indexable

sub index_digest {
	my ($self) = @_;
	return $self->SUPER::index_digest(
		  $self->index_parent
		. $self->index_published
		. $self->index_section
		. $self->index_allow
		. $self->index_deny
		. $self->index_tags

		. $self->index_doctype
		. $self->index_expires
		. $self->index_longdescription
		. $self->index_shorttitle

		. $self->more_info
	);
}

sub more_info {
	return;
}

#handled by Indexable: name reverse timestamp digest data count title keywords description

#Abstract Page attributes: parent file published section allow deny tags children

sub index_parent {
	my ($self) = @_;
	return $self->{'parent'};
}

sub index_file {
	my ($self) = @_;
	return $self->dbl->self_path;
}

sub index_published {
	my ($self) = @_;
	return $self->{'published'};
}

sub index_section {
	my ($self) = @_;
	return $self->{'section'};
}

sub index_allow {
	my ($self) = @_;
	return $self->{'allow'};
}

sub index_deny {
	my ($self) = @_;
	return $self->{'deny'};
}

sub index_tags {
	my ($self) = @_;
	return $self->{'tags'};
}

sub index_children {
	my ($self) = @_;
	return $self->{'parent'};
}

sub handle_children {
	my ($self, $id, $parent) = @_;
	my @parents = token_parse($parent);
	my %score = ();
	foreach $parent (@parents) {
		($parent, my $score) = split(':', $parent);
		$score{$parent} = $score;
	}
	$self->index->index_map('children', $id, \%score);
}

#The list goes on and on

sub index_doctype {
	my ($self) = @_;
	return ($self->{'doctype'} || 'HTML');
}

sub index_expires {
	my ($self) = @_;
	return $self->{'expires'};
}

sub index_longdescription {
	my ($self) = @_;
	return ($self->{'longdescription'} || $self->{'description'});
}

sub index_shorttitle {
	my ($self) = @_;
	return ($self->{'shorttitle'} || $self->{'title'});
}

1;
