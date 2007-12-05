package RT::Client::Console::Session::Ticket::Attachments;

use base qw(RT::Client::Console::Session);

use Params::Validate qw(:all);
use Error qw(:try);

use POE;

# class method
sub create {
	my ($class, $ticket_id) = @_;
	$class->SUPER::create(
	"ticket_attachments_$ticket_id",
	inline_states => {
		init => sub {
			my ($kernel, $heap) = @_[ KERNEL, HEAP ];


			my ($screen_w, $screen_h);
			$class->GLOBAL_HEAP->{curses}{handler}->getmaxyx($screen_h, $screen_w);

			$heap->{'pos_x'} = 0;
			$heap->{'pos_y'} = 1+5+5;
			$heap->{width} = $screen_w * 2 / 3 - 2;
			$heap->{height} = $screen_h - 5 - 7 - 5;

		},
		available_keys => sub {
			return (['<KEY_NPAGE>', 'next attachment', 'next_attachment'],
					['<KEY_PPAGE>', 'previous attachment', 'prev_attachment']
				   );
		},
		next_attachment => sub {
			my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
			$class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current}++;
			$class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current} > $class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{total} - 1
			  and $class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current} = $class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{total} - 1;
			$kernel->call('key_handler', 'draw_all');
		},
		prev_attachment => sub {
			my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
			$class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current}--;
			$class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current} < 0
			  and $class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current} = 0;
			$kernel->call('key_handler', 'draw_all');
		},
		draw => sub {
			my ($kernel, $heap) = @_[ KERNEL, HEAP ];
			my $label;

			if (!defined($heap->{attachments}{$ticket_id})) {
				$class->_generate_job($kernel, $heap, $ticket_id);
			}
			defined($heap->{attachments}{$ticket_id}) or return;
			my $total = $class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{total};
			$total > 0 or return;
			$class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current} ||= 0;

			my $idx = $class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{current};

			my $attachment = $heap->{attachments}{$ticket_id}->[$idx];

			my $text = '...loading...';
			my $user_details = '';

			if (defined $attachment) {
				try {
					my $user_id = $attachment->creator_id();
					use RT::Client::REST::User;

					my ($user, $user_name, $user_email, $user_real_name, $user_gecos, $user_comments)
					  = _get_user_details( rt  => $class->GLOBAL_HEAP->{rt}{cnx}{handler},
										   id  => $user_id,
										 );
					$user_details = "By : $user_real_name ($user_name) <$user_email>";
					
				} catch Exception::Class::Base with {
					my $e = shift;
					warn ref($e), ": ", $e->message || $e->description, "\n";
				};
				
				$text = $class->as_text($attachment);
			}
			my $title = 'Attachment ' . ($idx + 1) . " / $total - $user_details";

			use Curses::Widgets::ListBox;
#my $widget = Curses::Widgets::ListBox->new({
#  Y           => 2,
#  X           => 38,
#  COLUMNS     => 20,
#  LISTITEMS   => ['Ham', 'Eggs', 'Cheese', 'Hash Browns', 'Toast'],
#  MULTISEL    => 1,
#  VALUE       => [0, 2],
#  SELECTEDCOL => 'green',
#  CAPTION     => 'List Box',
#  CAPTIONCOL  => 'yellow',
#  });

			use Curses::Widgets::TextMemo;
 			my $widget = Curses::Widgets::TextMemo->new(
 					{
 					 X           => $heap->{'pos_x'},
 					 Y           => $heap->{'pos_y'},
 					 COLUMNS     => $heap->{width},
 					 LINES       => $heap->{height},
 					 MAXLENGTH   => undef,
 					 FOREGROUND  => 'white',
 					 BACKGROUND  => 'black',
 					 VALUE       => $text,
 					 BORDERCOL   => 'blue',
 					 BORDER      => 1,
 					 CAPTION     => $title,
 					 CAPTIONCOL  => 'yellow',
 					 READONLY    => 1,
 					}
 			);
#			$widget->execute($class->GLOBAL_HEAP->{curses}{handler});
			$widget->draw($class->GLOBAL_HEAP->{curses}{handler});
		},
	},
	heap => { 'pos_x' => 0,
			  'pos_y' => 0,
			  'width' => 0,
			  'height' => 0,
			},
	);
}


use Memoize;
memoize('_get_user_details');

sub _get_user_details {
	my (%args) = @_;
	my $user = RT::Client::REST::User->new( %args )->retrieve;
	my $user_name = $user->name();
	my $user_email = $user->email_address();
	my $user_real_name = $user->real_name();
	my $user_gecos = $user->gecos();
	my $user_comments = $user->comments();
	return ($user, $user_name, $user_email, $user_real_name, $user_gecos, $user_comments);
}

sub as_text {
    my ($class, $attachment) = @_;
	my $s = 'content :(' . $attachment->content_type() . ')' . "\n"
	      . 'subject :{' . $attachment->subject() . '}' . "\n"
	      . 'filename:{' . $attachment->file_name() . '}';
    if ($attachment->content_type eq 'text/plain') {
        return $s . "\n\n" . $attachment->content();
    } elsif ($attachment->content_type eq 'multipart/mixed') {
        return $s . "\n\n[" . $attachment->content() . "]\n";
	}
	else {
        return $s;
    }
}

sub _generate_job {
	my ($class, $kernel, $heap, $ticket_id) = @_;
	$heap->{attachments}{$ticket_id} = [];

	my @ids;
	my $idx = 0;
	my $rt_handler = $class->GLOBAL_HEAP->{rt}{cnx}{handler};
	my $iterator;
	use RT::Client::Console::Session::Progress;
	RT::Client::Console::Session::Progress->add_progress(
			steps_nb => sub { $class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{total} },
			caption => sub { 'attachments' },
			initially => sub {
				use RT::Client::Console::Session::Ticket;
				my $ticket = RT::Client::Console::Session::Ticket->get_current_ticket();
				my $attachments_obj = $ticket->attachments();
				my $count = $attachments_obj->count();
				$class->GLOBAL_HEAP->{rt}{attachments}{$ticket_id}{total} = $count;
				$iterator = $attachments_obj->get_iterator();
			},
			code => sub {
				my $attachment = $iterator->();
				defined $attachment or return;
				push @{$heap->{attachments}{$ticket_id}}, $attachment;
				$idx++ or $kernel->call('key_handler', 'draw_all');
				return 1;
			},
			finally => sub { },
	);
}


1;
