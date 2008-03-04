package RT::Client::Console::Session::KeyHandler;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Curses;
use Params::Validate qw(:all);
use POE;

# class method

# key handler session creation
sub create {
    my ($class) = @_;

    $class->SUPER::create(
    'key_handler',
    inline_states => {
        init => sub {
             my ($kernel, $heap) = @_[ KERNEL, HEAP];
             $kernel->yield('compute_keys');
             $kernel->yield('draw_all');

            # Generate events from console input.  Sets up Curses, too.
            $heap->{console} = POE::Wheel::MyCurses->new(
                                                         InputEvent => 'handler',
                                                        );
        },
        _quit => sub {
             my ($kernel, $heap) = @_[ KERNEL, HEAP];
            # release the Curses wheel
            undef $heap->{console};
        },
         handler => sub {
             my ($kernel, $heap, $keystroke) = @_[ KERNEL, HEAP, ARG0];
            if ($keystroke ne -1) {
                 if ($keystroke lt ' ') {
                     $keystroke = '<' . uc(unctrl($keystroke)) . '>';
                 } elsif ($keystroke =~ /^\d{2,}$/) {
                     $keystroke = '<' . uc(keyname($keystroke)) . '>';
                 }
                 print STDERR "handler got $keystroke\n";
                my $modal_session = ($class->get_modal_sessions())[-1];
                if ($modal_session) {
                     print STDERR "modal handler : " . $modal_session . "\n";
                    $kernel->call($modal_session, 'key_handler', $keystroke);
                     $kernel->call('key_handler', 'draw_all');
                } elsif (exists $heap->{key_to_action}->{$keystroke}) {
                     my $action = $heap->{key_to_action}->{$keystroke};
                     print STDERR "action : $action, event : $action->{event}\n";
                     my $ret = $kernel->call($action->{session}, $action->{event});
                    $kernel->call('key_handler', 'compute_keys');
                    if (!defined $ret || $ret ne '-1') {
                        $kernel->call('key_handler', 'draw_all');
                    }
                 }
            }
         },
         compute_keys => sub {
             my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
             my $status_message = '';
             $heap->{key_to_action} = {};
             my %sessions = $class->get_sessions();
             while (my ($session_name, $struct) = each %sessions) {
                 $struct->{displayed} or next;
                 my @list = $kernel->call($session_name, 'available_keys');
                 foreach (@list) {
                     defined && ref or next;
                     my ($key, $message, $event) = @$_;
                     defined $key or next;
                     $status_message .= " | $key: $message";
                     $heap->{key_to_action}->{$key} = { session => $session_name, event => $event };
                 }
             }
             $kernel->call('status', 'set_message', $status_message);
             return;
         },
         draw_all => sub {
             my ($kernel, $heap) = @_[ KERNEL, HEAP ];
             noutrefresh();
             if ($class->need_cls) {
                 clear();
                $class->reset_cls();
                $kernel->yield('draw_all');
             } else {
                my %sessions = $class->get_sessions();
                while (my ($session_name, $struct) = each %sessions) {
                    $struct->{displayed} and 
                      $kernel->call($session_name, 'draw');
                }
                foreach my $modal_session ($class->get_modal_sessions()) {
                    $kernel->call($modal_session, 'draw');
                }
            }
            doupdate();
         }
    },
    heap => { 
              console => undef,
            },
    );

}
















# TODO : clean and try to use POE::Wheel::Curses instead

# our own Cuses::Wheel
package POE::Wheel::MyCurses;

use strict;

use vars qw($VERSION);
$VERSION = do {my($r)=(q$Revision: 2102 $=~/(\d+)/);sprintf"1.%04d",$r};

use Carp qw(croak);
#use Curses qw(
#  initscr start_color cbreak raw noecho nonl nodelay timeout keypad
#  intrflush meta typeahead mousemask ALL_MOUSE_EVENTS clear refresh
#  endwin COLS
#);

use Curses;
use POE qw( Wheel );
use POSIX qw(:fcntl_h);


sub SELF_STATE_READ  () { 0 }
sub SELF_STATE_WRITE () { 1 }
sub SELF_EVENT_INPUT () { 2 }
sub SELF_ID          () { 3 }

sub new {
  my $type = shift;
  my %params = @_;

  croak "$type needs a working Kernel" unless defined $poe_kernel;

  my $input_event = delete $params{InputEvent};
  croak "$type requires an InputEvent parameter" unless defined $input_event;

  if (scalar keys %params) {
    carp( "unknown parameters in $type constructor call: ",
          join(', ', keys %params)
        );
  }

  # Create the object.
  my $self = bless
    [ undef,                            # SELF_STATE_READ
      undef,                            # SELF_STATE_WRITE
      $input_event,                     # SELF_EVENT_INPUT
      &POE::Wheel::allocate_wheel_id(), # SELF_ID
    ];

  # Set up the screen, and enable color, mangle the terminal and
  # keyboard.

  #initscr();
  #start_color();

  #cbreak();
  #raw();
  #noecho();
  #nonl();

  # Both of these achieve nonblocking input.
  #nodelay(1);
  #timeout(0);

  keypad(1);
  intrflush(0);
  meta(1);
  typeahead(-1);

  my $old_mouse_events = 0;
  mousemask(ALL_MOUSE_EVENTS, $old_mouse_events);

#  clear();
#  refresh();

  # Define the input event.
  $self->_define_input_state();

  # Oop! Return ourself.  I forgot to do this.
  $self;
}

sub _define_input_state {
  my $self = shift;

  # Register the select-read handler.
  if (defined $self->[SELF_EVENT_INPUT]) {
    # Stupid closure tricks.
    my $event_input = \$self->[SELF_EVENT_INPUT];
    my $unique_id   = $self->[SELF_ID];

    $poe_kernel->state
      ( $self->[SELF_STATE_READ] = ref($self) . "($unique_id) -> select read",
        sub {

          # Prevents SEGV in older Perls.
          0 && CRIMSON_SCOPE_HACK('<');

          my ($k, $me) = @_[KERNEL, SESSION];

          # Curses' getch() normally blocks, but we've already
          # determined that STDIN has something for us.  Be explicit
          # about which getch() to use.
          while ((my $keystroke = Curses::getch) ne '-1') {
            $k->call( $me, $$event_input, $keystroke, $unique_id );
          }
        }
      );

    # Now start reading from it.
    $poe_kernel->select_read( \*STDIN, $self->[SELF_STATE_READ] );

    # Turn blocking back on for STDIN.  Some Curses implementations
    # don't deal well with non-blocking STDIN.
    my $flags = fcntl(STDIN, F_GETFL, 0) or die $!;
    fcntl(STDIN, F_SETFL, $flags & ~O_NONBLOCK) or die $!;
  }
  else {
    $poe_kernel->select_read( \*STDIN );
  }
}

sub DESTROY {
  my $self = shift;

  # Turn off the select.
  $poe_kernel->select( \*STDIN );

  # Remove states.
  if ($self->[SELF_STATE_READ]) {
    $poe_kernel->state($self->[SELF_STATE_READ]);
    $self->[SELF_STATE_READ] = undef;
  }

  # Restore the terminal.
  endwin if COLS;

  &POE::Wheel::free_wheel_id($self->[SELF_ID]);
}

###############################################################################
1;

__END__

=head1 NAME

POE::Wheel::Curses - non-blocking Curses.pm input for full-screen console apps

=head1 SYNOPSIS

  use POE;
  use Curses;  # for unctrl, etc
  use POE::Wheel::Curses;

  # Generate events from console input.  Sets up Curses, too.
  $heap->{console} = POE::Wheel::Curses->new(
    InputEvent => 'got_keystroke',
  );

  # A keystroke handler.  This is the body of the program's main input
  # loop.
  sub keystroke_handler {
    my ($keystroke, $wheel_id) = @_[ARG0, ARG1];

    # Control characters.  Change them into something printable via
    # Curses' unctrl function.

    if ($keystroke lt ' ') {
      $keystroke = '<' . uc(unctrl($keystroke)) . '>';
    }

    # Extended keys get translated into their names via Curses'
    # keyname function.

    elsif ($keystroke =~ /^\d{2,}$/) {
      $keystroke = '<' . uc(keyname($keystroke)) . '>';
    }

    # Just display it.
    addstr( $heap->{some_window}, $keystroke );
    noutrefresh( $heap->{some_window} );
    doupdate;
  }

=head1 DESCRIPTION

Many console programs work best with full-screen input: top, systat,
nethack, and various text editors.  POE::Wheel::Curses provides a
simple way to add full-screen interfaces to POE programs.

Whenever something occurs on a recognized input device-- usually just
the keyboard, but also sometimes the mouse, as in the case of
ncurses-- the Curses wheel will emit a predetermined event to tell the
program about it.  This lets the program do other non-blocking things
in between keystrokes, like interact on sockets or watch log files or
move monsters or highlight text or something.

=head1 PUBLIC METHODS

=over 2

=item new NOT_SO_MANY_THINGS

new() creates a new Curses wheel.  Note, though, that there can be
only one Curses wheel in any given program, since they glom onto
*STDIN real hard.  Maybe this will change.

new() always returns a Curses wheel reference, even if there is a
problem glomming onto *STDIN or otherwise initializing curses.

new() accepts only one parameter so far: InputEvent.  InputEvent
contains the name of the event that the Curses wheel will emit
whenever there is input on the console or terminal.

=back

=head1 EVENTS AND PARAMETERS

=over 2

=item InputEvent

InputEvent defines the event that will be emitted when the Curses
wheel detects and receives input.

InputEvent is accompanied by two parameters:

C<ARG0> contains the raw keystroke as received by Curses' getch()
function.  It may be passed to Curses' unctrl() and keyname()
functions for further processing.

C<ARG1> contains the ID of the Curses wheel.

=back

=head1 SEE ALSO

curses, Curses, POE::Wheel.

The SEE ALSO section in L<POE> contains a table of contents covering
the entire POE distribution.

=head1 BUGS

Curses implementations vary widely, and Wheel::Curses was written on a
system sporting ncurses.  The functions used may not be the same as
those used on systems with other curses implementations, and Bad
Things might happen.  Please send patches.

=head1 AUTHORS & COPYRIGHTS

Please see L<POE> for more information about authors and contributors.

=cut
