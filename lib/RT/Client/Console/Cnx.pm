package RT::Client::Console::Cnx;

use base qw(RT::Client::Console);

use Params::Validate qw(:all);

sub connect {
	my ($class, @args) = @_;
	my %params = validate( @args, { rt_servername => 0,
									rt_username => 0,
									rt_password => 0,
									queue_ids => 0,
								  }
						 );

	$params{queue_ids} ||= [];

	if (!$params{rt_servername}) {
		$params{rt_servername} = $class->input_ok_cancel('Connexion', 'RT server name');
	}
	$params{rt_servername} or return;

	use RT::Client::REST;
	use Error qw(:try);
 	try {
 		my $rt_handler = RT::Client::REST->new(
 											   server  => $params{rt_servername},
 											  );
		if (!(defined $params{rt_username} && defined $params{rt_password})) {
			use Curses::Forms::Dialog::Logon;
			use Curses::Forms::Dialog::Input;
			(my $rv, $params{rt_username}, $params{rt_password}) = logon('connect to RT server', BTN_OK | BTN_CANCEL, 50, qw(white red yellow) );
		}
		$rt_handler->login(username => $params{rt_username}, password => $params{rt_password});
		$class->GLOBAL_HEAP->{rt}{cnx}{handler} = $rt_handler;
		$class->GLOBAL_HEAP->{rt}{cnx}{servername} = $params{rt_servername};
		$class->GLOBAL_HEAP->{rt}{cnx}{username} = $params{rt_username};
		$class->GLOBAL_HEAP->{rt}{cnx}{password} = $params{rt_password};

# 		if (@{$params{queue_ids}}) {


# 			my $idx = 0;
# 			my $rt_handler = $class->GLOBAL_HEAP->{rt}{cnx}{handler};

# 			use RT::Client::Console::Session::Progress;
# 			RT::Client::Console::Session::Progress->add_progress(
# 				steps_nb => sub { scalar(@{$params{queue_ids}}) },
# 				caption => sub { 'generating queues' },
# 				initially => sub { },
# 				code => sub { 
# 					my $id = $params{queue_ids}->[$idx++];
# 					defined $id or return;
# 					use RT::Client::REST::Queue;
# 					my $queue;
# 					try {
# 						$queue = RT::Client::REST::Queue->new( rt  => $rt_handler,
# 															   id  => $id, )->retrieve();
# 					} catch Exception::Class::Base with { my $dummy = 0; };
# 					if (defined $queue) {
# 						$class->GLOBAL_HEAP->{server}{id_to_queue}{$id} = $queue;
# 						$class->GLOBAL_HEAP->{server}{name_to_queue}{$queue->name()} = $queue;
# 					}
# 					return 1;
# 				},
# 				finally => sub { },
# 			);
# 		}
		$class->cls();
 	} catch Exception::Class::Base with {
 		$class->error("problem logging in: $@" . shift->message());
#		print STDERR Dumper(shift); use Data::Dumper;
#		print STDERR $@ . "\n";
 	};
	return;
}

sub disconnect {
	my ($class) = @_;
	undef $class->GLOBAL_HEAP->{rt}{cnx}{handler};
	undef $class->GLOBAL_HEAP->{rt}{cnx}{servername};
	undef $class->GLOBAL_HEAP->{rt}{cnx}{username};
	undef $class->GLOBAL_HEAP->{rt}{cnx}{password};
	my $ticket;
	while ($ticket = $class->GLOBAL_HEAP->{rt}{tickets}{current}) {
		$ticket->unload();
	}
	return;
}


1;
