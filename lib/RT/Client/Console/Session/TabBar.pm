package RT::Client::Console::Session::TabBar;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Curses::Forms;
use Curses::Widgets::Label;
use POE;
use relative -to => "RT::Client::Console", 
        -aliased => qw(Connection Session Session::Ticket);


# class method

# tabs bar session creation
sub create {
    my ($class) = @_;

    $class->SUPER::create(
        'tabbar',
        inline_states => {
            init => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
            },
            draw => sub { 
                my ($kernel,$heap) = @_[ KERNEL, HEAP ];
                my $curses_handler = $class->get_curses_handler();

                my @tickets = Ticket->get_tickets_list();
                @tickets > 0 or return;

                # clear the tab bar
                my $label = Curses::Widgets::Label->new({
                                        BORDER      => 0,
                                        X           => 0,
                                        Y           => 0,
                                        COLUMNS     => $heap->{screen_w},
                                        LINES       => 1,
                                        VALUE       => '',
                                        FOREGROUND  => 'black',
                                        BACKGROUND  => 'black',
                                    });
                $label->draw($curses_handler);
                
                my $current_id = Ticket->get_current_id();
                my @visible_tickets = @tickets;
                while (! _is_visible($current_id, \@visible_tickets, $heap->{screen_w})) {
                    shift @visible_tickets;                    
                }

                my $widgets = {};
                my $current_pos_x = 0;
                foreach my $index (0..@visible_tickets-1) {
                    my $ticket = $visible_tickets[$index];
                    my $string = '[ ' . $ticket->id() . ( $ticket->has_changed() ? ' *' : '' ). ' ]';
                    $current_pos_x + length($string) > $heap->{screen_w} and last;
                    $widgets->{"tab_$index"} = 
                      {
                       TYPE        => 'Label',
                       X           => $current_pos_x,
                       Y           => 0,
                       COLUMNS     => length($string),
                       LINES       => 1,
                       FOREGROUND  => $ticket->id() eq $current_id ? 'yellow' : 'white',
                       BACKGROUND  => 'blue',
                       VALUE       => $string,
                       ALIGNMENT   => 'C',
                      };
                    $current_pos_x += length($string);
                }
                my $form = Curses::Forms->new({
                       X           => 0,
                       Y           => 0,
                       COLUMNS     => $heap->{screen_w},
                       LINES       => 1,
                       BORDER      => 0,
                       FOREGROUND  => 'white',
                       BACKGROUND  => 'blue',
                       DERIVED     => 1,
                       #        AUTOCENTER  => 1,
                       TABORDER    => [],
                       WIDGETS     => $widgets,
                                              },
                                             );
                $form->draw($curses_handler);
            },
        },
    );
}

sub _is_visible {
    my ($id, $visible_tickets, $max_width) = @_;
    my $current_pos_x = 0;
    foreach my $ticket (@$visible_tickets) {
        $current_pos_x += length "[ $id" . ( $ticket->has_changed() ? ' *' : '' ) . ' ]';
        print STDERR ("-- ticket id : " . $ticket->id() . "\n");
        print STDERR ("-- id : " . $id . "\n");
        print STDERR ("-- " . ($current_pos_x > $max_width) . "\n");
        if ( $ticket->id() == $id ) {
            print STDERR ("-- YES\n");
            return (! ($current_pos_x > $max_width));
        }
    }
    die "shouldn't reach here";
}
1;
