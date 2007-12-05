package RT::Client::Console::Session::Ticket::CustFields;

use base qw(RT::Client::Console::Session);

use Params::Validate qw(:all);
use RT::Client::Console::Session::Ticket;
use POE;

# class method
sub create {
	my ($class, $id) = @_;
	$class->SUPER::create(
    "ticket_custfields_$id",
	inline_states => {
		init => sub {
			my ($kernel, $heap) = @_[ KERNEL, HEAP ];
			print STDERR "ticket_custfields : init\n";

			my ($screen_w, $screen_h);
			$class->GLOBAL_HEAP->{curses}{handler}->getmaxyx($screen_h, $screen_w);

			$heap->{'pos_x'} = 0;
			$heap->{'pos_y'} = 8;
			$heap->{width} = $screen_w * 2 / 3;
			$heap->{height} = 3;

		},
		available_keys => sub {
			return (['u', 'change custom fields', 'change_custfields']);
		},
		change_custfields => sub {
			my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
			$class->create_modal( title => ' Change Custom fields ',
								  text => '',
								  keys => {
										  },
								);
		},
		draw => sub { 
			my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
			my $label;

			my $ticket = RT::Client::Console::Session::Ticket->get_current_ticket();
			my @custom_fields = sort $ticket->cf();
			use POSIX qw(floor);
			my $per_col = POSIX::floor(@custom_fields/3);
			my @custom_fields_labels;

			# first 2 column
			foreach (1..2) {
				push @custom_fields_labels, 
				  [
				   map {
					   [ "$_:", (defined $ticket->cf($_) ? $ticket->cf($_) : '') ],
				   } splice @custom_fields, 0, $per_col
				  ];
				
			}
			# third column
			push @custom_fields_labels, 
			  [
			   map {
				   [ "$_:", $ticket->cf($_) ],
			   } @custom_fields
			  ];
			
			my %custom_fields_widgets = $class->struct_to_widgets(\@custom_fields_labels, $heap->{height}, $heap->{width});
			
			use Curses::Forms;
			my $form = Curses::Forms->new({
										   X           => $heap->{'pos_x'},
										   Y           => $heap->{'pos_y'},
										   COLUMNS     => $heap->{width},
										   LINES       => $heap->{height},
										   
										   BORDER      => 0,
										   BORDERCOL   => 'blue',
										   FOREGROUND  => 'white',
										   BACKGROUND  => 'blue',
										   DERIVED     => 1,
										   #        AUTOCENTER  => 1,
										   TABORDER    => [],
										   FOCUSED     => 'label1',
										   WIDGETS     => \%custom_fields_widgets,
										  },
										 );
			$form->draw($class->GLOBAL_HEAP->{curses}{handler});
			#						refresh($mwh);
		},
	},
	heap => { 'pos_x' => 0,
			  'pos_y' => 0,
			  'width' => 0,
			  'height' => 0,
			},
	);	  
}

1;
