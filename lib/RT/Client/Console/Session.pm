package RT::Client::Console::Session;

use strict;
use warnings;

use parent qw(RT::Client::Console);

use POE;
use List::Util qw(max);
use Curses::Widgets::Label;


# global vars

my %sessions;
my @modal_sessions;
my $modal_index = 0;

# a small wrapper around POE::Session
sub create {
    my ($class, $name, %args) = @_;
    $args{inline_states}{_start} = sub { 
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        $kernel->alias_set($name);
        $kernel->call($name, 'init');
    };
    $args{inline_states}{_unalias} = sub {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        my @aliases = $kernel->alias_list();
        foreach my $alias (@aliases) {
            $kernel->alias_remove($alias);
        }
    };
    $sessions{$name} = {
                        poe_object => POE::Session->create(%args),
                        displayed => 1,
                       };
    return $name;
}

sub get_sessions { return %sessions; }

# create a modal session
sub create_modal {
    my ($class, %args) = @_;

    my $title = "[ $args{title} ]";    
    my $text = $args{text} . "\n";
    $args{keys}{c} ||= { text => 'cancel',
                         code => sub { return 1 },
                       };
                                            
    while (my ($k, $v) = each %{$args{keys}} ) {
        $text .= "$k : " . $v->{text} . "\n";
    }
    my $height = scalar( () = $text =~ /(\n)/g) + 1;
    my $width = max (map { length } (split(/\n/, $text), $title));

    my ($screen_w, $screen_h);

    my $curses_handler = $class->get_curses_handler();
    $curses_handler->getmaxyx($screen_h, $screen_w);
    
    my $label = Curses::Widgets::Label->new({
                                             CAPTION     => $title,
                                             CAPTIONCOL  => 'yellow',
                                             BORDER      => 1,
                                             LINES       => $height,
                                             COLUMNS     => $width,
                                             Y           => $screen_h/2-($height+2)/2,
                                             X           => $screen_w/2-($width+2)/2,,
                                             VALUE       => $text,
                                             FOREGROUND  => 'white',
                                             BACKGROUND  => 'blue',
                                             BORDERCOL   => 'white',
                                            });


    my $modal_session_name = 'modal_' . ++$modal_index;
    POE::Session->create(
        inline_states => {
            _start => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                $heap->{label} = $label;
                $kernel->alias_set($modal_session_name);
            },
            key_handler => sub {
                my ( $kernel, $heap, $keystroke ) = @_[ KERNEL, HEAP, ARG0 ];
                exists $args{keys}->{$keystroke} or return;
                if ($args{keys}{$keystroke}{code}->()) {
                    # stop modal mode
                    pop @modal_sessions;
                    $class->remove($modal_session_name);
                    $kernel->post('key_handler', 'compute_keys');
                } else {
                    $kernel->yield('draw');
                }
            },
            draw => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                my $curses_handler = $class->get_curses_handler();
                $heap->{label}->draw($curses_handler);
            },
        },
    );
    push @modal_sessions, $modal_session_name;
    return $modal_session_name;
}

sub get_modal_sessions {
    my ($class) = @_;
    return @modal_sessions;
}

# start the POE main loop
sub run {
    my ($class) = @_;
    $poe_kernel->run();
}

# display/hide a session
sub set_display {
    my ($class, $session_name, $display_state) = @_;
    $sessions{$session_name}{displayed} = $display_state ? 1 : 0;
}

=head2 remove

Removes a session

  input : a session name

=cut

sub remove {
    my ($class, $session_name) = @_;
    delete $sessions{$session_name};
    $poe_kernel->call($session_name, '_quit');
    $poe_kernel->call($session_name, '_unalias');

}

sub remove_all {
    my ($class) = @_;
    my %sessions = $class->get_sessions();
    my @sessions_names = keys(%sessions);
    foreach (@sessions_names) {
        $class->remove($_);
    }
}

1;
