package RT::Client::Console::Session::Ticket::Transactions;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Error qw(:try);
use File::Spec::Functions;
use File::Temp qw(tempdir);
use Curses::Widgets; # for textwrap
use Curses::Widgets::ListBox;
use Curses::Widgets::TextMemo;
use POE;
use Curses qw(endwin refresh);
use relative -to => "RT::Client::Console", 
        -aliased => qw(Connection Session Session::Ticket Session::Progress);
use RT::Client::Console::Session::Ticket;

# class method

# transactions session creation
sub create {
    my ($class, $ticket_id) = @_;
    my $session_name = "ticket_transactions_$ticket_id";
    $class->SUPER::create(
    $session_name,
    inline_states => {
        init => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{pos_x} = 0;
            $heap->{pos_y} = 1 + 7 + 6;  # tabs-bar + headers + custhdrs
        },
        window_resize => sub {
            my ($kernel, $heap, $old_screen_h, $old_screen_w) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
            $heap->{width } = $heap->{screen_w} * 2 / 3 - 2;  # - border
            $heap->{height} = $heap->{screen_h} - $heap->{pos_y} - 2 - 2;
        },
        available_keys => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            my @additional_key = ();
            if (defined($heap->{transactions})) {
                my $idx = $heap->{current};
                my $transaction = $heap->{transactions}->[$idx];
                if (_get_transaction_attachments($transaction)) {
                    @additional_key = ();
                }
            }

            return ( ['g',           'get attachments', 'get_attachments' ],
                     ['v',           'view attachments','view_attachments'],
                     ['e',           'new comment',     'new_comment'     ],
                     ['<KEY_NPAGE>', 'next attach.',    'next_transaction'],
                     ['<KEY_PPAGE>', 'prev. attach.',   'prev_transaction'],
                     ['<KEY_UP>',    'scroll up',       'scroll_up'       ],
                     ['<KEY_DOWN>',  'scroll down',     'scroll_down'     ],

#                     ['b',           'page up',          'page_up'        ],
#                     [' ',           'page down',        'page_down'      ],
                   );
        },

        get_attachments => sub {
             my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
             my $idx = $heap->{current};
             my $transaction = $heap->{transactions}->[$idx];
             defined $transaction or return;
             my @attachments = _get_transaction_attachments($transaction);
             @attachments or return;
             my %id_to_name = map { $_->{id}, $_->{name} } @attachments;
             @attachments = map { { text => $_->{name}, value => $_->{id} } } @attachments;
             my $id;
             while (!$id) {
                 $id = $class->input_list(title => ' Download attachments ',
                                          items => [ { text => 'Cancel',
                                                       value => -2,
                                                     },
                                                     { text => 'Download all',
                                                       value => -1,
                                                     },
                                                     { text => '------------',
                                                       value => 0,
                                                     },
                                                     @attachments
                                                   ],
                                          value => '-1',
                                         );
             }

              if ($id == -2) { # cancel
                  return;
              } elsif ($id == -1) { # download all
                  my @attachment_ids = map { $_->{value}; } @attachments;
                  try {
                      my $download_dir = $class->_get_download_dir();
                      if (defined $download_dir) {
                          foreach my $attachment_id (@attachment_ids) {
                              my $attachment_name = $id_to_name{$attachment_id};
                              _save_attachment($attachment_id, $attachment_name, $ticket_id, $download_dir);
                          }
                          $class->message('Saving attachment',
                                          "the attachments have been downloaded to '$download_dir'",
                                         );
                      }
                  } otherwise {
                      $class->error($@);
                  };
              } else {
                  try {
                      my $attachment_id = $id;
                      my $download_dir = $class->_get_download_dir();
                      if (defined $download_dir) {
                          my $attachment_name = $id_to_name{$attachment_id};
                          my $filename = _save_attachment($attachment_id, $attachment_name, $ticket_id, $download_dir);
                          $class->message('Saving attachment',
                                          "$attachment_name has been downloaded to '$filename'",
                                         );
                      }
                  } otherwise {
                      $class->error($@);
                  };
              }
        },

        view_attachments => sub {
             my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
             my $idx = $heap->{current};
             my $transaction = $heap->{transactions}->[$idx];
             defined $transaction or return;
             my @attachments = _get_transaction_attachments($transaction);
             @attachments or return;
             my %id_to_name = map { $_->{id}, $_->{name} } @attachments;
             @attachments = map { { text => $_->{name}, value => $_->{id} } } @attachments;
             my $id;
             while (!$id) {
                 $id = $class->input_list(title => ' View attachments ',
                                          items => [ { text => 'Cancel',
                                                       value => -2,
                                                     },
                                                     { text => '------------',
                                                       value => 0,
                                                     },
                                                     @attachments
                                                   ],
                                          value => '-1',
                                         );
             }

              if ($id == -2) { # cancel
                  return;
              } else {
                  try {
                      my $attachment_id = $id;
                      my $dir = tempdir();
                      my $attachment_name = $id_to_name{$attachment_id};
                      my ($filename, $content_type) = _save_attachment($attachment_id, $attachment_name, $ticket_id, $dir);
                      my $viewer = $class->_get_viewer($content_type);
                      my $command = sprintf($viewer, $filename);
                      endwin;
                      system($command);
                      refresh;
                  } otherwise {
                      $class->error($@);
                  };
              }
        },

        next_transaction => sub {
            my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{current}++;
            $heap->{current} > $heap->{total} - 1
              and $heap->{current} = $heap->{total} - 1;
            $heap->{positions}[$heap->{current}]->{current} = 0;
        },

        prev_transaction => sub {
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
                    $kernel->call($session_name, 'draw');
                }
                return -1;
            }
            $positions->{current} += $offset;
            $kernel->call($session_name, 'draw');
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
                    $kernel->call($session_name, 'draw');
                }
                return -1;
            }
            $positions->{current} -= $offset;
             $kernel->call($session_name, 'draw');
            return -1;
        },

        page_down => sub {
             my ($kernel, $heap) = @_[ KERNEL, HEAP ];
             my $offset = int($heap->{height} / 2);
            $kernel->call($session_name, 'scroll_down', $offset);
        },

        page_up => sub {
             my ($kernel, $heap) = @_[ KERNEL, HEAP ];
             my $offset = int($heap->{height} / 2);
            $kernel->call($session_name, 'scroll_up', $offset);
        },

        draw => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            my $label;

            if (!defined($heap->{transactions})) {
                $class->_generate_job($kernel, $heap, $ticket_id);
            }
            defined($heap->{transactions}) or return;
#             if (!defined($heap->{attachments})) {
#                 $class->_generate_job2($kernel, $heap, $ticket_id);
#             }
#             defined($heap->{attachments}) or return;

            my $total = $heap->{total};
            $total > 0 or return;
            $heap->{current} ||= 0;

            my $idx = $heap->{current};

            my $transaction = $heap->{transactions}->[$idx];

            my $text = '...loading...';
            my $details = '';

            if (defined $transaction) {
                $details = 
                  $transaction->creator() . ' ' .
                  '(' . $transaction->created() . ') ' .
                  $transaction->type();

                $text = $class->as_text($heap, $transaction, $idx, $heap->{width}, $ticket_id);
            }
            my $title = '[ ' . ($idx + 1) . " / $total - $details ]";
            $title =~ s/\s+/ /g;

            my ($textstart, $cursorpos) = (0, 0);
            my $positions = $heap->{positions}[$idx];
            if (defined $positions && defined ($positions->{array}[$positions->{current}])) {
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
            my @keys = grep { $_->[0] !~ /^g|v$/; } map {
                my $n = $_->[0];
                $n =~ s/<KEY_(.*)>/$1/;
                [ lc($n), @{$_}[1,2] ];
            } $kernel->call($session_name => 'available_keys');            
            $class->draw_keys_label( Y => $heap->{'pos_y'} + $heap->{height} + 1 ,
                                     X => $heap->{'pos_x'} + 5,
                                     COLUMNS => $heap->{width} - 2,
                                     VALUE => \@keys,
                                     BACKGROUND  => 'black'
                                   );
        },
        new_comment => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            my ($button, $text) = Session->execute_textmemo_modal(
                title => 'new comment',
                text => '',
			);
			if ($button == 0) {
				my $ticket = RT::Client::Console::Session::Ticket->get_current_ticket();
				$ticket or return;
				$ticket->correspond(message => $text);
				$class->_generate_job($kernel, $heap, $ticket_id);
# 				$class->_generate_job2($kernel, $heap, $ticket_id);
			}
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

sub _save_attachment {
    my ($attachment_id, $attachment_name, $ticket_id, $download_dir) = @_;
    my $rt_handler = Connection->get_cnx_data()->{handler};
    my $attachment;
    Session->execute_wait_modal('  Retrieving Attachment...  ',
                                  sub { 
                                      $attachment = $rt_handler->get_attachment( parent_id => $ticket_id,
                                                                                 id => $attachment_id
                                                                               );
                                  },
                                );
    defined $attachment or die "Error retrieving attachment $attachment_id";
    my $filename = catfile($download_dir, $attachment_name);
    open my $f, '>', $filename or die $!;
    binmode $f;
    print $f $attachment->{Content}; #$res->content;
    close $f;
    return(wantarray() ? ($filename, $attachment->{ContentType}) : $filename);
}

sub _get_download_dir {
    my ($class) = @_;
    my $configuration = RT::Client::Console->get_configuration();
    my $download_dir;
    if (exists $configuration->{files} && defined $configuration->{files}->{download_dir}) {
        $download_dir = $configuration->{files}->{download_dir};
    } else {
        $download_dir = $class->input_ok_cancel('Saving attachment',
                                                "Enter full directory",
                                                1000);
        $download_dir or $download_dir = undef;
    }    
    return $download_dir;
}

sub _get_viewer {
    my ($class, $ct) = @_;
    my $configuration = RT::Client::Console->get_configuration();
    my $viewer;
    $ct =~ s|/.*$||;
    if (exists $configuration->{files} && defined $configuration->{files}->{"view_$ct"}) {
        $viewer = $configuration->{files}->{"view_$ct"};
    } else {
        $viewer = $class->input_ok_cancel('Viewer for $ct',
                                          "Enter viewer command",
                                          1000);
        $viewer or $viewer = undef;
    }
    return $viewer;
}

# use Memoize;
# memoize('_get_user_details');

# sub _get_user_details {
#     my (%args) = @_;
#     my $user = RT::Client::REST::User->new( %args )->retrieve;
#     my $user_name = $user->name();
#     my $user_email = $user->email_address();
#     my $user_real_name = $user->real_name();
#     my $user_gecos = $user->gecos();
#     my $user_comments = $user->comments();
#     return ($user, $user_name, $user_email, $user_real_name, $user_gecos, $user_comments);
# }

sub as_text {
    my ($class, $heap, $transaction, $idx, $width, $ticket_id) = @_;
    defined $heap->{text}[$idx] and return $heap->{text}[$idx];
    use Data::Dumper;
    my $s = Dumper($transaction);

    my @attachments = _get_transaction_attachments($transaction);
    my $attachments_text = '';
    if (@attachments) {
        $attachments_text .= "\n   * Attachments  [ press 'g' to download them, 'v' to view them ] :";
    }
    foreach (@attachments) {
        $attachments_text .= "\n       * $_->{name} ($_->{size})";
    }
    
    my $text =
      "\n" .
      '   * ' . $transaction->description() .
      $attachments_text .
      "\n\n" .
      $transaction->content();
      
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

sub _get_transaction_attachments {
    my ($transaction) = @_;
    defined $transaction or return ();
    my $attachments_text = $transaction->attachments();
    my @attachments_strings = split /\n/, $attachments_text;
    my @attachments = map { /^(\d+): (.+) \(([^()]+)\)$/ ? { id => $1, name => $2, size => $3 } : () } @attachments_strings;
    my @non_empty_attachments = grep { $_->{name} ne 'untitled' } @attachments;
    return @non_empty_attachments;
}

sub _generate_job {
    my ($class, $kernel, $heap, $ticket_id) = @_;
    $heap->{transactions} = [];

    my @ids;
    my $idx = 0;
    my $rt_handler = Connection->get_cnx_data()->{handler};
    my $iterator;
    Progress->add_progress(
            steps_nb => sub { $heap->{total} },
            caption => sub { 'transactions' },
            initially => sub {
                my $ticket = Ticket->get_current_ticket();
                my $transactions_obj = $ticket->transactions();
                my $count = $transactions_obj->count();
                $heap->{total} = $count;
                $iterator = $transactions_obj->get_iterator();
            },
            code => sub {
                my $transaction = $iterator->();
                defined $transaction or return;
                push @{$heap->{transactions}}, $transaction;
                $idx++ or $kernel->post('key_handler', 'draw_all');
                return 1;
            },
            finally => sub { },
    );
}

# # get all attachments of the ticket
# sub _generate_job2 {
#     my ($class, $kernel, $heap, $ticket_id) = @_;
#     $heap->{attachments} = {};

#     my @ids;
#     my $idx = 0;
#     my $rt_handler = Connection->get_cnx_data()->{handler};
#     my $iterator;
#     Progress->add_progress(
#             steps_nb => sub { $heap->{total_transactions} },
#             caption => sub { 'attachments' },
#             initially => sub {
#                 my $ticket = Ticket->get_current_ticket();
#                 my $attachments_obj = $ticket->attachments();
#                 my $count = $attachments_obj->count();
#                 $heap->{total_transactions} = $count;
#                 $iterator = $attachments_obj->get_iterator();
#             },
#             code => sub {
#                 my $attachment = $iterator->();
#                 defined $attachment or return;
#                 $heap->{attachments}{$attachment->id()} = $attachment;
#                 $idx++ or $kernel->post('key_handler', 'draw_all');
#                 return 1;
#             },
#             finally => sub { },
#     );
# }

1
