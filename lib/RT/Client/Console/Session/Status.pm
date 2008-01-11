package RT::Client::Console::Session::Status;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Curses::Widgets::Label;
use Params::Validate qw(:all);
use POE;


# class method

### THIS MODULE IS NOT USED BY THE CORE, BUT SHOULD BE PROVIDED AS PLUGIN ###

# status session creation
sub create {
    my ($class) = @_;

    $class->SUPER::create(
        'status',
        inline_states => {
            init => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                $heap->{pos_x} = 0;
                $heap->{height} = 1;
			},
			window_resize => sub {
				my ($kernel, $heap, $old_screen_h, $old_screen_w) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
                $heap->{pos_y} = $heap->{screen_h} - 4;
                $heap->{width} = $heap->{screen_w} - 2;
            },
            set_message => sub {
                my ($kernel, $heap, $message) = @_[ KERNEL, HEAP, ARG0 ];
                $heap->{message} = $message;
            },
            draw => sub { 
                my ($kernel,$heap) = @_[ KERNEL, HEAP ];
                my $label;
    
                # Render the comment box
                $label = Curses::Widgets::Label->new({
                                                      CAPTION     => ' Keys ',
                                                      BORDER      => 1,
                                                      LINES       => $heap->{height},
                                                      COLUMNS     => $heap->{width},
                                                      Y           => $heap->{pos_y},
                                                      X           => $heap->{pos_x},
                                                      VALUE       => $heap->{message},
                                                      FOREGROUND  => 'white',
                                                      BACKGROUND  => 'blue',
                                                      BORDERCOL   => 'black',
                                                     });
                #refresh;
                $label->draw($class->get_curses_handler());
            },
        },
        heap => { 'pos_x' => 0,
                  'pos_y' => 0,
                  'width' => 0,
                  'height' => 0,
                  'message' => 'default',
                },
    );
}

1;
