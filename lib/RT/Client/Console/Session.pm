package RT::Client::Console::Session;

use base qw(RT::Client::Console);

use POE;

sub create {
	my ($class, $name, %args) = @_;
	$args{inline_states}{_start} = sub { 
		my ($kernel, $heap) = @_[ KERNEL, HEAP ];
		$kernel->alias_set($name);
		$kernel->call($name, 'init');
	};
	$class->GLOBAL_HEAP->{sessions}{$name} = {
											  poe_object => POE::Session->create(%args),
											  displayed => 1,
											 };
	return $name;
}

sub run {
	my ($class) = @_;
	$poe_kernel->run();
}





{

my $modal_index = 0;

sub create_modal {
	my ($class, %args) = @_;
	
	my $text = $args{text} . "\n";
	$args{keys}{c} ||= { text => 'cancel',
						 code => sub { return 1 },
					   };
											
	while (my ($k, $v) = each %{$args{keys}} ) {
		$text .= "$k : " . $v->{text} . "\n";
	}
	my $height = scalar( () = $text =~ /(\n)/g) + 1;
	use List::Util qw(max);
	my $width = max (map { length } (split(/\n/, $text), $args{title}));

	my ($screen_w, $screen_h);
	my $curses_handler = $class->GLOBAL_HEAP->{curses}{handler};
	$curses_handler->getmaxyx($screen_h, $screen_w);
	
	use Curses::Widgets::Label;
	my $label = Curses::Widgets::Label->new({
											 CAPTION     => $args{title},
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
					pop @{$class->GLOBAL_HEAP->{modal_sessions}};
					$kernel->post('key_handler', 'draw_all');
				} else {
					$kernel->yield('draw');
				}
			},
			draw => sub {
				my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
				my $curses_handler = $class->GLOBAL_HEAP->{curses}{handler};
				$heap->{label}->draw($curses_handler);
			},
		},
	);
	push @{$class->GLOBAL_HEAP->{modal_sessions}}, $modal_session_name;
	return $modal_session_name;
}

}

=head2 remove

Removes a session

  input : a session name

=cut

sub remove {
	my ($class, $session_name) = @_;
	delete $class->GLOBAL_HEAP->{sessions}{$session_name};
}

1;
