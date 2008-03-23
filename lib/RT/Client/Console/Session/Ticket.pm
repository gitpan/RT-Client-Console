package RT::Client::Console::Session::Ticket;

use strict;
use warnings;

# multi-inheritance
use parent qw(RT::Client::Console::Session
              RT::Client::REST::Ticket);

use Error qw(:try);
use POE;
use Params::Validate qw(:all);
use RT::Client::REST;
use RT::Client::REST::Ticket;
use relative -to => "RT::Client::Console", 
        -aliased => qw(Connection Session);
use relative -aliased => qw(Header CustFields Links Transactions);

my @tickets_list = ();
my $current_ticket_id;

=head1 CONSTRUCTORS

=head2 create

Create a new ticket. Displays input fields to the users.

=cut

sub create {
    my ($class) = @_;
    my $id;
    my $subject = $class->input_ok_cancel('New ticket', 'Enter the subject') or return;
    my $queue = $class->input_ok_cancel('New ticket', 'Enter the queue name or ID') or return;
    my ($button, $text) = Session->execute_textmemo_modal( title => 'New ticket',
                                                           text => '',
                                                         );
    $button and return;
    my $ticket;
    try {
        my $rt_handler = RT::Client::Console::Connection->get_cnx_data()->{handler};
        $ticket = RT::Client::REST::Ticket->new( rt => $rt_handler,
                                                 queue => $queue,
                                                 subject => $subject,
            )->store(text => $text);
        print STDERR " --> Created a new ticket, ID ", $ticket->id(), "\n";
        $class->load_from_id($ticket->id())
    } otherwise {
        $class->error("problem creating rt : " . $@);
    };
    return;
}

=head2 load

Loads a new ticket, or if already created, make sure it's made visible. If
needed, it adds it in the list of tickets.

input : 

=cut

sub load {
    my ($class) = @_;
    my $id;
    try {
        if ($id = $class->input_ok_cancel('Open a ticket', 'Ticket number')) {
            $class->load_from_id($id);
        }
    } otherwise {
        $class->error("problem opening/retrieving rt $id : " . $@);
    };
    return;
}

=head2 load_from_id

Given an id, loads a new ticket, or if already created, make sure it's made
visible. If needed, it adds it in the list of tickets.

=cut

sub load_from_id {
    my ($class, $id) = @_;
    try {
        my $ticket;
        if (! (scalar($class->_is_loaded($id))) ) {
            $ticket = $class->new($id);
            push @tickets_list, $ticket;
        }
        $class->set_current_id($id);
        $class->_set_visibility();
    } otherwise {
        $class->error("problem opening/retrieving rt $id : " . $@);
    };
    return;
}

# set the display status of the sessions of tickets.

sub _set_visibility {
    my ($class) = @_;
    # set every ticket sessions invisible
    foreach my $ticket (@tickets_list) {
        foreach my $session (@{$ticket->{sessions}}) {
            Session->set_display($session, 0);
        }
    }
    # set current ticket sessions visible
    my $current_ticket = $class->get_current_ticket();
    defined $current_ticket or return;
    foreach my $session (@{$current_ticket->{sessions}}) {
        Session->set_display($session, 1);
    }
}

=head2 open_from_id

Given an id, simply returns the REST ticket, don't display it, nor add it to
the tab, or list of loaded tickets.

=cut

sub open_from_id {
    my ($class, $id) = @_;
    my $rt_handler = RT::Client::Console::Connection->get_cnx_data()->{handler};
    my $ticket = RT::Client::REST::Ticket->new(
                                                rt  => $rt_handler,
                                                id  => $id,
                                              );
    RT::Client::Console::Session::Progress->add_and_execute('retrieving ticket',
									   sub { $ticket->retrieve() },
									  );
    return $ticket;
}

=head2 new

Creates a new ticket object, even if it is already loaded. You probably don't
want to use that. Use load instead

=cut

sub new {
    my ($class, $id) = @_;

    my $self = $class->open_from_id($id);

    # the 'create' methods returns the name of the session, so the array
    # contains keep the list of child sessions.
    $self->{sessions} = [
                        Header->create($id),
                        CustFields->create($id),
                        Links->create($id),
                        Transactions->create($id),
                        ];
    $self->{changed} = 0;
    return bless $self, $class;
}

=head1 CLASS METHODS

=head2 get_tickets_list

Returns the list of loaded tickets. 

=cut

sub get_tickets_list {
    return @tickets_list;
}

=head2 get_current_ticket

=cut

sub get_current_ticket {
    my ($class) = @_;
    my $current_id = $class->get_current_id();
    defined $current_id or return;
    foreach my $ticket (@tickets_list) {
        $ticket->id() == $current_id and return $ticket;
    }
    return;
}

=head2 get_current_id

=cut

sub get_current_id {
    my ($class) = @_;
    return $current_ticket_id;
}

=head2 set_current_ticket 

=cut

sub set_current_ticket {
    my ($class, $ticket) = @_;
    $current_ticket_id = defined $ticket ? $ticket->id() : undef;
}

=head2 set_current_id

=cut

sub set_current_id {
    my ($class, $id) = @_;
    $current_ticket_id = $id;
}


=head2 next

show the next ticket from the list

=cut

sub next_ticket {
    my ($class) = @_;

    my $current_id = $class->get_current_id();
    my $index = 0;
    foreach my $ticket (@tickets_list) {
        if ($ticket->id() == $current_id && exists $tickets_list[$index+1] ) {
            $class->set_current_ticket($tickets_list[$index+1]);
        }
        $index++;
    }
    $class->_set_visibility();
    return;
}

=head2 next

show the previous ticket from the list

=cut

sub prev_ticket {
    my ($class) = @_;
    
    my $current_id = $class->get_current_id();
    my $index = 0;
    foreach my $ticket (@tickets_list) {
        if ($ticket->id() == $current_id && $index > 0 ) {
            $class->set_current_ticket($tickets_list[$index-1]);
        }
        $index++;
    }
    $class->_set_visibility();
    return;
}

# returns the ticket object if it's already loaded, empty list otherwise

sub _is_loaded {
    my ($class, $id) = @_;
    my @matches = grep { $_->id() == $id } @tickets_list;
    @matches <= 1 or die "tickets loaded twice, shouldn't happen";
    return @matches;
}

=head1 METHODS

=head2 set_changed

set the "changed" status of a ticket

=cut

sub set_changed {
    my ($self, $status) = @_;
    $self->{changed} = $status;
    return;
}

=head2 has_changed

Return true if the ticket has been changed and needs to be saved

=cut

sub has_changed {
    my ($self) = @_;
    return $self->{changed};
}

sub save_current_if_needed {
    my ($class) = @_;
    if (my $ticket = $class->get_current_ticket()) {
        if ($ticket->has_changed()) {
			try {
				Session->execute_wait_modal('  Saving the ticket ' . $ticket->id() . '...  ',
											sub { $ticket->store();
												  $ticket->set_changed(0);
											  }
										   );
			} otherwise {
				$class->error('problem saving ticket ' . $ticket->id() . ' : ' . shift->message());
			};
        }
    }
}

=head2 unload

unload a ticket

=cut

sub unload {
    my ($self) = @_;
    # warn if ticket needs saving
print STDERR "_____________******* UNLOAD\n";
    if ($self->has_changed()) {
        use Curses::Forms::Dialog;
        my $ret = dialog('Unsaved changes made', BTN_YES | BTN_NO | BTN_CANCEL, 'Do you want to save this ticket before closing it ?', 
                         qw(white red yellow));
        $ret eq 2 and return; # cancel
        $ret eq 0 and $self->save_current_if_needed(); #yes
        # otherwise, continue closing without saving
    }
    # break references
    foreach my $session_name (@{$self->{sessions}}) {
        Session->remove($session_name);
    }
    # remove from the list of tickets
    @tickets_list = grep { $_ ne $self } @tickets_list;
    # display the next visible ticket
    if ($self->get_current_id() == $self->id()) {
        if (@tickets_list > 0) {
            $self->set_current_ticket($tickets_list[-1]);
        } else {
            $self->set_current_id(undef);
            $self->cls();
        }
    }
    $self->_set_visibility();
}

1;
