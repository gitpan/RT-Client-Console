package RT::Client::Console::Session::Root;

use base qw(RT::Client::Console::Session);

use Params::Validate qw(:all);
use RT::Client::Console::Session::Ticket;

use POE;

# class method
sub create {
	my ($class) = @_;

	$class->SUPER::create(
    'root',
	inline_states => {
		init => sub {
			my ($kernel, $heap) = @_[ KERNEL, HEAP ];
			print STDERR "root : init\n";
			$class->GLOBAL_HEAP->{curses}{handler}->clear();
			$kernel->yield('create_tab_bar');
			$kernel->yield('create_status_session');
			$kernel->yield('create_progress_session');
		},
		available_keys => sub {
			my @available_list = ();
			if (!$class->GLOBAL_HEAP->{rt}{cnx}{handler}) {
				push @available_list, ['s', 'connect to RT server', 'connect_server'];
			}
			if ($class->GLOBAL_HEAP->{rt}{cnx}{handler}) {
				push @available_list, ['d', 'disconnect from RT server', 'disconnect_server'];
				push @available_list, ['o', 'open a ticket', 'open_ticket'];
				if (defined RT::Client::Console::Session::Ticket->get_current_id()) {
					push @available_list, ['c', 'close current ticket', 'close_ticket'];
					push @available_list, ['p', 'prev. ticket', 'prev_ticket'];
					push @available_list, ['n', 'next ticket', 'next_ticket'];
				}
			}
			return @available_list;
		},
		create_tab_bar => sub {
			use RT::Client::Console::Session::TabBar;
			RT::Client::Console::Session::TabBar->create();
		},
		create_status_session => sub {
			use RT::Client::Console::Session::Status;
			RT::Client::Console::Session::Status->create();
		},
		create_progress_session => sub {
			use RT::Client::Console::Session::Progress;
			RT::Client::Console::Session::Progress->create();
		},
		connect_server => sub {
			use RT::Client::Console::Cnx;
			RT::Client::Console::Cnx->connect();
		},
		disconnect_server => sub {
			use RT::Client::Console::Cnx;
			RT::Client::Console::Cnx->disconnect();
		},
		open_ticket => sub {
			print STDERR "root.pm : opening ticket\n";
			RT::Client::Console::Session::Ticket->load();
		},
		close_ticket => sub {
			RT::Client::Console::Session::Ticket->get_current_ticket()->unload();
		},
		next_ticket => sub {
			RT::Client::Console::Session::Ticket->next_ticket();
		},
		prev_ticket => sub {
			RT::Client::Console::Session::Ticket->prev_ticket();
		},
	}
	);
}

1;
