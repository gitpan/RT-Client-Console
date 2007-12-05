package RT::Client::Console::Session::Ticket::Links;

use base qw(RT::Client::Console::Session);

use Params::Validate qw(:all);
use RT::Client::Console::Session::Ticket;

use POE;

# class method
sub create {
	my ($class, $id) = @_;
	$class->SUPER::create(
    "ticket_links_$id",
	inline_states => {
		init => sub {
			my ($kernel, $heap) = @_[ KERNEL, HEAP ];

			my ($screen_w, $screen_h);
			$class->GLOBAL_HEAP->{curses}{handler}->getmaxyx($screen_h, $screen_w);
	
			$heap->{'pos_x'} = $screen_w * 2 / 3 + 1;
			$heap->{'pos_y'} = 1;
			$heap->{width} = $screen_w - ($screen_w * 2 / 3);
			$heap->{height} = $screen_h - 5 - 1;
		},
		available_keys => sub {
			return (['l', 'change links', 'change_links']);
		},
		change_links => sub {
			my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
			$heap->{change_links_mode} = 1;
			my $text = qq(

 c : cancel
);
			my $height = scalar( () = $text =~ /(\n)/g) + 1;
			use List::Util qw(max);
			my $title = ' Change ticket links ';
			my $width = max (map { length } (split(/\n/, $text), $title));
			my ($screen_w, $screen_h);
			my $curses_handler = $class->GLOBAL_HEAP->{curses}{handler};
			$curses_handler->getmaxyx($screen_h, $screen_w);

			use Curses::Widgets::Label;
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
			$label->draw($curses_handler);
			$class->GLOBAL_HEAP->{modal_session} = 'ticket_links';
		},
		modal_handler => sub {
			my ( $kernel, $heap, $keystroke) = @_[ KERNEL, HEAP, ARG0 ];

			my $ticket = RT::Client::Console::Session::Ticket->get_current_ticket();
			if ($keystroke eq 'c' || $keystroke eq '<^[>') {
				delete $class->GLOBAL_HEAP->{modal_session};
			} else {
				$kernel->yield('change_links');
			}
			return;
		},
		draw => sub { 
			my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
			my $label;

			my $ticket = RT::Client::Console::Session::Ticket->get_current_ticket();

print STDERR "LINKS ---> got $ticket \n";

			if (!defined($heap->{parents})) {
				$class->_generate_job($kernel, $heap, 'parents', q(HasMember=') . $ticket->id() . q('))
			}
			if (!defined($heap->{children})) {
				$class->_generate_job($kernel, $heap, 'children', q(MemberOf=') . $ticket->id() . q('))
			}
			if (!defined($heap->{depends})) {
				$class->_generate_job($kernel, $heap, 'depends', q(DependedOnBy=') . $ticket->id() . q('))
			}
			if (!defined($heap->{depended})) {
				$class->_generate_job($kernel, $heap, 'depended', q(DependsOn=') . $ticket->id() . q('))
			}
			if (!defined($heap->{refers})) {
				$class->_generate_job($kernel, $heap, 'refers', q(ReferredToBy=') . $ticket->id() . q('))
			}
			if (!defined($heap->{refered})) {
				$class->_generate_job($kernel, $heap, 'refered', q(RefersTo=') . $ticket->id() . q('))
			}

			
			my $_ticket_to_label = sub {
				my ($t) = @_;
				defined $t && ref($t) or return '';
				return $t->id() . ' ' . $t->subject()
			};


			my @d = @{$heap->{depends}};
			my @depends_on = (
							  [ 'Depends on:' => $_ticket_to_label->($d[0]) ],
							  map { [ '' => $_ticket_to_label->($_) ] } @d[1..$#d]
							 );
			my @d2 = @{$heap->{depended}};
			my @depended_on_by = (
								  [ 'Depended on by:' => $_ticket_to_label->($d2[0]) ],
								  map { [ '' => $_ticket_to_label->($_) ] } @d2[1..$#d2]
								 );
print STDERR "----> parents : " . Dumper(\@p); use Data::Dumper;
			my @p = @{$heap->{parents}};
			my @parents = (
						   [ 'Parents:' => $_ticket_to_label->($p[0]) ],
						   map { [ '' => $_ticket_to_label->($_) ] } @p[1..$#p]
						  );
			my @c = @{$heap->{children}};
			my @children = (
							[ 'Children:' => $_ticket_to_label->($c[0]) ],
							map { [ '' => $_ticket_to_label->($_) ] } @c[1..$#c]
						   );
			my @r = @{$heap->{refers}};
			my @refers_to = (
							 [ 'Refers to:' => $_ticket_to_label->($r[0]) ],
							 map { [ '' => $_ticket_to_label->($_) ] } @r[1..$#r]
							);
			my @r2 = @{$heap->{refered}};
			my @referred_to_by = (
								  [ 'Refered to by:' => $_ticket_to_label->($r2[0]) ],
								  map { [ '' => $_ticket_to_label->($_) ] } @r2[1..$#r2]
								 );


			my @links_labels = (
								# first column
								[ @depends_on,
								  @depended_on_by,
								  @parents,
								  @children,
								  @refers_to,
								  @referred_to_by,
								],
							   );


			my %links_widgets = $class->struct_to_widgets(\@links_labels, $heap->{height}-2, $heap->{width}-2);

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
													   WIDGETS     => \%links_widgets,
													  },
													 );
			use Data::Dumper;
			$form->draw($class->GLOBAL_HEAP->{curses}{handler});
			#						refresh($mwh);
		},
	},
	heap => { 'pos_x' => 0,
			  'pos_y' => 0,
			  'width' => 0,
			  'height' => 0,
			  change_custfields_mode => 0,
			},
	);	  
}

sub _generate_job {
	my ($class, $kernel, $heap, $element, $query) = @_;
	$heap->{$element} = [];
	my @ids;
	my $idx = 0;
	my $rt_handler = $class->GLOBAL_HEAP->{rt}{cnx}{handler};
	use RT::Client::Console::Session::Progress;
	RT::Client::Console::Session::Progress->add_progress(
			steps_nb => sub { scalar(@ids) },
			caption => sub { $element },
			initially => sub {
				@ids = $rt_handler->search( type => 'ticket',
											query => $query,
										  );
			},
			code => sub { my $id = $ids[$idx++];
						  defined $id or return;
print STDERR "->>>>>> got id : [$id]\n";
						  push @{$heap->{$element}},
							RT::Client::Console::Session::Ticket->open_from_id($id);
						  #										   $kernel->post('ticket_links', 'draw');
						  return 1;
					  },
			finally => sub { 
				$kernel->post('ticket_links', 'draw'),
			},
	);
}
1;
