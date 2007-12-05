package RT::Client::Console::Session::TabBar;

use strict;
use warnings;

use base qw(RT::Client::Console::Session);

use POE;

# class method
sub create {
	my ($class) = @_;

	$class->SUPER::create(
        'tabbar',
		inline_states => {
			init => sub {
				my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
				# Get the main screen max y & X
				my ($screen_w, $screen_h);
				$class->GLOBAL_HEAP->{curses}{handler}->getmaxyx($screen_h, $screen_w);
	
				$heap->{width} = $screen_w;
			},
			draw => sub { 
				my ($kernel,$heap) = @_[ KERNEL, HEAP ];
				my $curses_handler = $class->GLOBAL_HEAP->{curses}{handler};

				my @tickets = @{$class->GLOBAL_HEAP->{rt}{tickets}{list}};
				@tickets > 0 or return;

				# clear the tab bar
				use Curses::Widgets::Label;
				my $label = Curses::Widgets::Label->new({
										BORDER      => 0,
										X           => 0,
										Y           => 0,
										COLUMNS     => $heap->{width},
										LINES       => 1,
										VALUE       => '',
										FOREGROUND  => 'black',
										BACKGROUND  => 'black',
									});
				$label->draw($curses_handler);
				
				use RT::Client::Console::Session::Ticket;
				my $current_id = RT::Client::Console::Session::Ticket->get_current_id();
				my @visible_tickets = @tickets;
				while (! _is_visible($current_id, \@visible_tickets, $heap->{width})) {
					shift @visible_tickets;					
				}

				my $widgets = {};
				my $current_pos_x = 0;
				foreach my $index (0..@visible_tickets-1) {
					my $ticket = $visible_tickets[$index];
					my $string = '[ ' . $ticket->id() . ' ]';
					$current_pos_x + length($string) > $heap->{width} and last;
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
				use Curses::Forms;
				my $form = Curses::Forms->new({
					   X           => 0,
					   Y           => 0,
					   COLUMNS     => $heap->{width},
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
		heap => { 'width' => 0 },
    );
}

sub _is_visible {
	my ($id, $visible_tickets, $max_width) = @_;
	my $current_pos_x = 0;
	foreach my $ticket (@$visible_tickets) {
		$current_pos_x += length "[ $id ]";
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
