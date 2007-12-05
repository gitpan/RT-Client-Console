package RT::Client::Console::Session::Status;

use base qw(RT::Client::Console::Session);

use Params::Validate qw(:all);

use POE;
# class method
sub create {
	my ($class) = @_;

	$class->SUPER::create(
        'status',
		inline_states => {
			init => sub {
				my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
				# Get the main screen max y & X
				my ($screen_w, $screen_h);
				$class->GLOBAL_HEAP->{curses}{handler}->getmaxyx($screen_h, $screen_w);
	
				$heap->{'pos_x'} = 0;
				$heap->{'pos_y'} = $screen_h - 4;
				$heap->{width} = $screen_w-2;
				$heap->{height} = 1;
			},
			set_message => sub {
				my ($kernel, $heap, $message) = @_[ KERNEL, HEAP, ARG0 ];
				$heap->{message} = $message;
			},
			draw => sub { 
				my ($kernel,$heap) = @_[ KERNEL, HEAP ];
				my $label;
	
				# Render the comment box
				use Curses::Widgets::Label;
				$label = Curses::Widgets::Label->new({
													  CAPTION     => ' Keys ',
													  BORDER      => 1,
													  LINES       => $heap->{height},
													  COLUMNS     => $heap->{width},
													  Y           => $heap->{'pos_y'},
													  X           => $heap->{'pos_x'},
													  VALUE       => $heap->{message},
													  FOREGROUND  => 'white',
													  BACKGROUND  => 'blue',
													  BORDERCOL   => 'black',
													 });
				#refresh;
				$label->draw($class->GLOBAL_HEAP->{curses}{handler});
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
