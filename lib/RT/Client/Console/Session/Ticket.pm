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
        -aliased => qw(Cnx Session);
use relative -aliased => qw(Header CustFields Links Transactions);



my @tickets_list = ();
my $current_ticket_id;

=head1 CONSTRUCTORS

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
        if (! ($ticket = $class->_is_loaded($id)) ) {
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

sub _set_visibility {
    my ($class) = @_;
    foreach my $ticket (@tickets_list) {
        foreach my $session (@{$ticket->{sessions}}) {
            Session->set_display($session, 0);
        }
    }
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
    my $rt_handler = RT::Client::Console::Cnx->get_cnx_data()->{handler};
    my $ticket = RT::Client::REST::Ticket->new(
                                                rt  => $rt_handler,
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

    # the 'create' methods returns the name of the session, so the array
    # contains keep the list of child sessions.
    $self->{sessions} = [ Header->create($id),
                          CustFields->create($id),
                          Links->create($id),
                          Transactions->create($id),
                        ];
    return bless $self, $class;
}

=head1 ACCESSORS

=head2 get_tickets_list

Returns the list of loaded tickets. 

=cut

sub get_tickets_list {
    return @tickets_list;
}

=head1 METHODS

=head2 unload

unload a ticket

=cut

sub unload {
    my ($self) = @_;
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

=head1 METHODS

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

=head set_current_id

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
    my @matches = grep { $_->{id} eq $id } @tickets_list;
    @matches <= 1 or die "tickets loaded twice, shouldn't happen";
    return @matches;
}

1;
