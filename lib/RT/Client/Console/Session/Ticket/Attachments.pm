package RT::Client::Console::Session::Ticket::Attachments;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Curses::Widgets; # for textwrap
use Curses::Widgets::ListBox;
use Curses::Widgets::TextMemo;
use Error qw(:try);
use Params::Validate qw(:all);
use POE;
use Memoize;
use RT::Client::REST::User;
use relative -to => "RT::Client::Console", 
        -aliased => qw(Cnx Session Session::Ticket Session::Progress);


# class method


### THIS MODULE IS DEPRECATED, BUT COULD BE USED AS A PLUGIN ###

# attachments session creation
sub create {
    my ($class, $ticket_id) = @_;
    $class->SUPER::create(
    "ticket_attachments_$ticket_id",
    inline_states => {
        init => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{pos_x } = 0;
            $heap->{pos_y } = 1 + 7 + 6;  # tabs-bar + headers + custhdrs
		},
	    window_resize => sub {
            my ($kernel, $heap, $old_screen_h, $old_screen_w) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
            $heap->{width} = $heap->{screen_w} * 2 / 3 - 2;  # - border;
            $heap->{height} = $heap->{screen_h} - $heap->{pos_y} - 2 - 2;
        },
        available_keys => sub {
            return (['<KEY_NPAGE>', 'next attachment',  'next_attachment'],
                    ['<KEY_PPAGE>', 'prev. attachment', 'prev_attachment'],
                    ['<KEY_UP>',    'scroll up',        'scroll_up'      ],
                    ['<KEY_DOWN>',  'scroll down',      'scroll_down'    ],
                    ['b',           'page up',          'page_up'        ],
                    [' ',           'page down',        'page_down'      ],
                   );
        },

        next_attachment => sub {
            my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{current}++;
            $heap->{current} > $heap->{total} - 1
              and $heap->{current} = $heap->{total} - 1;
            $heap->{positions}[$heap->{current}]->{current} = 0;
        },

        prev_attachment => sub {
            my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{current}--;
            $heap->{current} < 0
              and $heap->{current} = 0;
            $heap->{positions}[$heap->{current}]->{current} = 0;
        },

        scroll_down => sub {
             my ($kernel, $heap, $offset) = @_[ KERNEL, HEAP, ARG0 ];
            $offset ||= 1;
             my $idx = $heap->{current};
            my $positions = $heap->{positions}[$idx];
            defined $positions or return -1;
            if ($positions->{current} >= @{$positions->{array}} - $offset) {
                if ($heap->{current} < $heap->{total} - 1 ) {
                    $heap->{current}++;
                    if (defined $heap->{positions}[$idx + 1]) {
                        $heap->{positions}[$idx + 1]->{current} = 0;
                    }
                    $kernel->call("ticket_attachments_$ticket_id", 'draw');
                }
                return -1;
            }
            $positions->{current} += $offset;
            $kernel->call("ticket_attachments_$ticket_id", 'draw');
            return -1;
        },

        scroll_up => sub {
             my ($kernel, $heap, $offset) = @_[ KERNEL, HEAP, ARG0 ];
             $offset ||= 1;
             my $idx = $heap->{current};
            my $positions = $heap->{positions}[$idx];
            defined $positions or return -1;
            if ($positions->{current} <= ($offset-1)) {
                if ($heap->{current} > 0) {
                    $heap->{current}--;
                    if (defined $heap->{positions}[$idx - 1]) {
                        $heap->{positions}[$idx - 1]->{current} =
                          @{$heap->{positions}[$idx - 1]->{array}} - 1;
                    }
                    $kernel->call("ticket_attachments_$ticket_id", 'draw');
                }
                return -1;
            }
            $positions->{current} -= $offset;
             $kernel->call("ticket_attachments_$ticket_id", 'draw');
            return -1;
        },

        page_down => sub {
             my ($kernel, $heap) = @_[ KERNEL, HEAP ];
             my $offset = int($heap->{height} / 2);
            $kernel->call("ticket_attachments_$ticket_id", 'scroll_down', $offset);
        },

        page_up => sub {
             my ($kernel, $heap) = @_[ KERNEL, HEAP ];
             my $offset = int($heap->{height} / 2);
            $kernel->call("ticket_attachments_$ticket_id", 'scroll_up', $offset);
        },

        draw => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            my $label;

            if (!defined($heap->{attachments})) {
                $class->_generate_job($kernel, $heap, $ticket_id);
            }
            defined($heap->{attachments}) or return;
            my $total = $heap->{total};
            $total > 0 or return;
            $heap->{current} ||= 0;

            my $idx = $heap->{current};

            my $attachment = $heap->{attachments}->[$idx];

            my $text = '...loading...';
            my $user_details = '';

            if (defined $attachment) {
                try {
                    my $user_id = $attachment->creator_id();
                    my $rt_handler = Cnx->get_cnx_data()->{handler};

                    my ($user, $user_name, $user_email, $user_real_name, $user_gecos, $user_comments)
                      = _get_user_details( rt  => $rt_handler,
                                           id  => $user_id,
                                         );
                    $user_details = "By: $user_real_name ($user_name) <$user_email>";
                    
                } catch Exception::Class::Base with {
                    my $e = shift;
                    warn ref($e), ": ", $e->message || $e->description, "\n";
                };
                
                $text = $class->as_text($heap, $attachment, $idx, $heap->{width}, $ticket_id);
            }
            my $title = '[ Attachment ' . ($idx + 1) . " / $total - $user_details ]";
            $title =~ s/\s+/ /g;

            my ($textstart, $cursorpos) = (0, 0);
            my $positions = $heap->{positions}[$idx];
            if (defined $positions) {
                ($textstart, $cursorpos) = @{$positions->{array}[$positions->{current}]};
            }
            print STDERR "+++ SCROLL : text start : $textstart\n";
            print STDERR "+++ CURSOR : $cursorpos\n";

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
                      BORDERCOL   => 'red',
                      BORDER      => 1,
                      CAPTION     => $title,
                      CAPTIONCOL  => 'yellow',
                      READONLY    => 1,
                     TEXTSTART   => $textstart,
                     CURSORPOS   => $cursorpos,
                    }
             );
            $widget->draw($class->get_curses_handler());

            # draw keys
            my @keys = map {
                my $n = $_->[0];
                $n =~ s/<KEY_(.*)>/$1/;
                [ lc($n), @{$_}[1,2] ];
            } $kernel->call("ticket_attachments_$ticket_id" => 'available_keys');            
            $class->draw_keys_label( Y => $heap->{'pos_y'} + $heap->{height} + 1 ,
                                     X => $heap->{'pos_x'} + 5,
                                     COLUMNS => $heap->{width} - 2,
                                     VALUE => \@keys,
                                     BACKGROUND  => 'black'
                                   );
        },
    },
    heap => { 'pos_x' => 0,
              'pos_y' => 0,
              'width' => 0,
              'height' => 0,
              positions => [],
              text => [],
            },
    );
}


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
    my ($class, $heap, $attachment, $idx, $width, $ticket_id) = @_;
    defined $heap->{text}[$idx] and return $heap->{text}[$idx];
    my $s = 'content :(' . $attachment->content_type() . ')' . "\n"
          . 'subject :{' . $attachment->subject() . '}' . "\n"
          . 'filename:{' . $attachment->file_name() . '}' . "\n"
          . 'created :{' . $attachment->created() . '}' . "\n"
          . 'transac :{' . $attachment->transaction_id() . '}' . "\n"
          . 'message :{' . $attachment->message_id() . '}';
    if (defined $attachment->transaction_id()) {
        my $id = $attachment->transaction_id();
        $s .= "\n--- transaction $id ----\n";
        my $rt_handler = Cnx->get_cnx_data()->{handler};
        my $transaction = $rt_handler->get_transaction(parent_id => $ticket_id,
                                                       id => $id);

#        my $ticket = Ticket->get_ticket_from_id($ticket_id);
#RT::Client::REST::Ticket
#        my $transaction = RT::Client::REST($ticket,parent_id => $ticket_id,
#                                                              id => $id);
#        my $transaction = $ticket->get_transaction(parent_id => $ticket_id,
#                                                   id => $id);
        use Data::Dumper;
        $s .= Dumper($transaction);
        $s .= "\n------------\n";
    }
    my $text;
    if ($attachment->content_type eq 'text/plain') {
        $text = $s . "\n\n" . $attachment->content();
    } elsif ($attachment->content_type eq 'multipart/mixed') {
        $text = $s . "\n\n[" . $attachment->content() . "]\n";
    } else {
        $text = $s;
    }
    $heap->{text}[$idx] = $text;
    my @lines = textwrap($text, $width - 1);
    my $i = 0;
    my $l = 0;
    $heap->{positions}[$idx] = 
      {
       current => 0,
       array => [
                 [ 0, 0 ],
                 map { [ ++$i, $l += length ]; } @lines,
                ],
      };
    return $text;
}

sub _generate_job {
    my ($class, $kernel, $heap, $ticket_id) = @_;
    $heap->{attachments} = [];

    my @ids;
    my $idx = 0;
    my $rt_handler = Cnx->get_cnx_data()->{handler};
    my $iterator;
    Progress->add_progress(
            steps_nb => sub { $heap->{total} },
            caption => sub { 'attachments' },
            initially => sub {
                my $ticket = Ticket->get_current_ticket();
                my $attachments_obj = $ticket->attachments();
                my $count = $attachments_obj->count();
                $heap->{total} = $count;
                $iterator = $attachments_obj->get_iterator();
            },
            code => sub {
                my $attachment = $iterator->();
                defined $attachment or return;
                push @{$heap->{attachments}}, $attachment;
                $idx++ or $kernel->post('key_handler', 'draw_all');
                return 1;
            },
            finally => sub { },
    );
}


1;
