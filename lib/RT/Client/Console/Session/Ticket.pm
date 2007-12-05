package RT::Client::Console::Session::Ticket;

use base qw(RT::Client::Console::Session
			RT::Client::REST::Ticket);

use Params::Validate qw(:all);

use RT::Client::REST;

use POE;

=head1 CONSTRUCTORS

=head2 load

Loads a new ticket, or if already created, make sur it's made visible. If
needed, it adds it in the list of tickets.

input : 

=cut

sub load {
	my ($class) = @_;
	use Error qw(:try);
	try {
		if (my $id = $class->input_ok_cancel('Open a ticket', 'Ticket number')) {
			$class->load_from_id($id);
		}
	} otherwise {
		$class->error("problem opening/retrieving rt $rt_num : " . $@);
	};
	return;
}

sub load_from_id {
	my ($class, $id) = @_;
	use Error qw(:try);
	try {
		my $ticket;
		if (! ($ticket = $class->_is_loaded($id)) ) {
			$ticket = $class->new($id);
			push @{$class->GLOBAL_HEAP->{rt}{tickets}{list}}, $ticket;
			$class->GLOBAL_HEAP->{rt}{tickets}{total}++;
		}
		$class->set_current_id($id);
		$class->_set_visibility();
	} otherwise {
		$class->error("problem opening/retrieving rt $rt_num : " . $@);
	};
	return;
}

sub _set_visibility {
	my ($class) = @_;
	foreach my $ticket (@{$class->GLOBAL_HEAP->{rt}{tickets}{list}}) {
		foreach my $session (@{$ticket->{sessions}}) {
			$class->GLOBAL_HEAP->{sessions}{$session}{displayed} = 0;
		}
	}
	foreach my $session (@{$class->get_current_ticket()->{sessions}}) {
		$class->GLOBAL_HEAP->{sessions}{$session}{displayed} = 1;
	}
}

=head2 open_from_id

simply return the REST ticket, don't display it, nor add it to the tab, or list of loaded tickets.

=cut

sub open_from_id {
	my ($class, $id) = @_;
	use RT::Client::REST::Ticket;
	my $ticket = RT::Client::REST::Ticket->new(
												rt  => $class->GLOBAL_HEAP->{rt}{cnx}{handler},
												id  => $id,
											  );
	$ticket->retrieve();
	return $ticket;
}

=head2 new

Creates a new ticket object, even if it is already loaded. You probably don't
want to use that. Use load instead

=cut

sub new {
	my ($class, $id) = @_;

	my $self = $class->open_from_id($id);

	use RT::Client::Console::Session::Ticket::Header;
	use RT::Client::Console::Session::Ticket::CustFields;
	use RT::Client::Console::Session::Ticket::Links;
	use RT::Client::Console::Session::Ticket::Attachments;

	# the 'create' methods returns the name of the session, so the array
	# contains keep the list of child sessions.
	$self->{sessions} = [ RT::Client::Console::Session::Ticket::Header->create($id),
						  RT::Client::Console::Session::Ticket::CustFields->create($id),
						  RT::Client::Console::Session::Ticket::Links->create($id),
						  RT::Client::Console::Session::Ticket::Attachments->create($id),
						];
	return bless $self, $class;
}

=head1 METHODS

=head2 unload

unload a ticket

=cut

sub unload {
	my ($self) = @_;
	# break references
	foreach my $session_name (@{$self->{sessions}}) {
		RT::Client::Console::Session->remove($session_name);
	}
	# remove from the list of tickets
	@{$self->GLOBAL_HEAP->{rt}{tickets}{list}} = grep { $_ ne $self } @{$self->GLOBAL_HEAP->{rt}{tickets}{list}};
	# display the next visible ticket
	if ($self->get_current_id() == $self->id()) {
		if (@{$self->GLOBAL_HEAP->{rt}{tickets}{list}} > 0) {
			$self->set_current_ticket($self->GLOBAL_HEAP->{rt}{tickets}{list}->[-1]);
			$self->cls();
		} else {
			$self->set_current_id(undef);
			$self->cls();
		}
	}
	$self->_set_visibility();
}

=head1 METHODS

=head2 get_current_ticket

=cut

sub get_current_ticket {
	my ($class) = @_;
	my $current_id = $class->GLOBAL_HEAP->{rt}{tickets}{current_id};
	defined $current_id or return;
	foreach my $ticket (@{$class->GLOBAL_HEAP->{rt}{tickets}{list}}) {
		$ticket->id() == $current_id and return $ticket;
	}
	return;
}

=head2 get_current_id

=cut

sub get_current_id {
	my ($class) = @_;
	return $class->GLOBAL_HEAP->{rt}{tickets}{current_id};
}

=head2 set_current_ticket 

=cut

sub set_current_ticket {
	my ($class, $ticket) = @_;
	$class->GLOBAL_HEAP->{rt}{tickets}{current_id} = defined $ticket ? $ticket->id() : undef;
}

=head set_current_id

=cut

sub set_current_id {
	my ($class, $id) = @_;
	$class->GLOBAL_HEAP->{rt}{tickets}{current_id} = $id;
}


=head2 next

show the next ticket from the list

=cut

sub next_ticket {
	my ($class) = @_;

	my $current_id = $class->get_current_id();
	my $index = 0;
	foreach my $ticket (@{$class->GLOBAL_HEAP->{rt}{tickets}{list}}) {
		if ($ticket->id() == $current_id && exists $class->GLOBAL_HEAP->{rt}{tickets}{list}->[$index+1] ) {
			$class->set_current_ticket($class->GLOBAL_HEAP->{rt}{tickets}{list}->[$index+1]);
		}
		$class->_set_visibility();
		$index++;
	}
	return;
}

=head2 next

show the previous ticket from the list

=cut

sub prev_ticket {
	my ($class) = @_;
	
	my $current_id = $class->get_current_id();
	my $index = 0;
	foreach my $ticket (@{$class->GLOBAL_HEAP->{rt}{tickets}{list}}) {
		if ($ticket->id() == $current_id && $index > 0 ) {
			$class->set_current_ticket($class->GLOBAL_HEAP->{rt}{tickets}{list}->[$index-1]);
		}
		$class->_set_visibility();
		$index++;
	}
	return;
}

# returns the ticket object if it's already loaded, empty list otherwise

sub _is_loaded {
	my ($class, $id) = @_;
	my @matches = grep { $_->{id} eq $id } @{$class->GLOBAL_HEAP->{rt}{tickets}{list}};
	@matches <= 1 or die "tickets loaded twice, shouldn't happen";
	return @matches;
}

1;
