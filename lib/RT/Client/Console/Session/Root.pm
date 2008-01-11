package RT::Client::Console::Session::Root;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Params::Validate qw(:all);
use POE;
use relative -to => "RT::Client::Console", 
        -aliased => qw(Cnx Session);
use relative -to => "RT::Client::Console::Session", 
        -aliased => qw(Progress Status TabBar Ticket);


# class method

# root session creation
sub create {
    my ($class) = @_;

    $class->SUPER::create(
    'root',
    inline_states => {
        init => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            print STDERR "root : init\n";
            $class->get_curses_handler()->clear();
            $kernel->yield('create_tab_bar');
#            $kernel->yield('create_status_session');
            $kernel->yield('create_progress_session');

            # the root session is special, it's the only one handling the
            # window size change signal. It takes care of changing it to events
            $kernel->sig(WINCH => 'sig_window_resize');

            $heap->{'pos_x'} = 0;
            $heap->{height} = 1;

        },
        sig_window_resize => sub { 
            my ($kernel, $heap) = @_[ KERNEL, HEAP];
            $class->restart_curses();
			my %sessions = $class->get_sessions();
			my @sessions_names = keys(%sessions);
			# send the window_resize to all sessions (including root)
			foreach my $name (@sessions_names) {
				# window resize signal provided by default (see Session.pm)
				$kernel->call($name, '__window_resize');
			}
        },
        window_resize => sub {
            my ($kernel, $heap, $old_screen_h, $old_screen_w) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
            $heap->{pos_y} = $heap->{screen_h} - 2;
            print STDERR " -- ROOT -- window resize " . $heap->{screen_w} . " | " . $heap->{screen_h} . "\n";
            $heap->{width} = $heap->{screen_w};
        },
        available_keys => sub {
            my @available_list = ();
            my $rt_handler = Cnx->get_cnx_data()->{handler};
            push @available_list, ['q', 'quit', 'quit'];
            if (!$rt_handler) {
                push @available_list, ['s', 'connect to RT server', 'connect_server'];
            } else {
                push @available_list, ['d', 'disconnect', 'disconnect_server'];
                push @available_list, ['o', 'open a ticket', 'open_ticket'];
                if (defined Ticket->get_current_id()) {
                    push @available_list, ['c', 'close current tab', 'close_tab'];
                    push @available_list, ['p', 'prev. tab', 'prev_tab'];
                    push @available_list, ['n', 'next tab', 'next_tab'];
                }
            }
            return @available_list;
        },
        draw => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            my @keys = $kernel->call(root => 'available_keys');
            $class->draw_keys_label( Y => $heap->{pos_y},
                                     X => $heap->{pos_x},
                                     COLUMNS => $heap->{width},
                                     VALUE => \@keys,
                                   );
        },
        quit => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            Session->remove_all();
        },
        create_tab_bar => sub {
            TabBar->create();
        },
        create_status_session => sub {
            Status->create();
        },
        create_progress_session => sub {
            Progress->create();
        },
        connect_server => sub {
            Cnx->connect();
        },
        disconnect_server => sub {
            Cnx->disconnect();
        },
        open_ticket => sub {
            print STDERR "root.pm : opening ticket\n";
            Ticket->load();
        },
        close_tab => sub {
            Ticket->get_current_ticket()->unload();
        },
        next_tab => sub {
            Ticket->next_ticket();
        },
        prev_tab => sub {
            Ticket->prev_ticket();
        },
    }
    );
}

1;
