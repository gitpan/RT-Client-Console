package RT::Client::Console::Session::Ticket::Header;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Curses::Forms;
use Params::Validate qw(:all);
use POE;
use relative -to => "RT::Client::Console", 
        -aliased => qw(Cnx Session Session::Ticket);

# class method

# headers session creation
sub create {
    my ($class, $id) = @_;

    $class->SUPER::create(
    "ticket_header_$id",
    inline_states => {
        init => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{pos_x } = 0;
            $heap->{pos_y } = 1;  # tabs-bar
            $heap->{height} = 5;            
        },
        window_resize => sub { 
            my ($kernel, $heap, $old_screen_h, $old_screen_w) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
            $heap->{width } = $heap->{screen_w} * 2 / 3 - 2;  # - border
        },
        available_keys => sub {
            return (['h', 'change ticket header', 'change_header']);
        },
        change_header => sub {
            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
            my $ticket = Ticket->get_current_ticket();
            $class->create_modal( title => 'Change ticket headers',
                                  text => '',
                                  keys => {
                                           s => { text => 'change subject',
                                                  code => sub {
                                                      if (my $new_subject = $class->input_ok_cancel('Change subject', $ticket->subject(), 500)) {
                                                          $ticket->subject($new_subject);
                                                          return 1; # stop modal mode
                                                      }
                                                  }
                                                },
                                           t => { text => 'change status',
                                                  code => sub {
                                                      if (my $new_status = $class->input_list(title => 'Change status',
                                                                                              items => [ qw(new open resolved stalled rejected deleted) ],
                                                                                              value => $ticket->status(),
                                                                                             )) {
                                                          $ticket->status($new_status);
                                                          return 1; # stop modal mode
                                                      }
                                                  }
                                                },
                                           q => { text => 'change queue',
                                                  code => sub {

                                                      if (my $new_queue = $class->input_ok_cancel('Change queue', $ticket->queue(), 500)) {
                                                          $ticket->queue($new_queue);
                                                          return 1; # stop modal mode
                                                      }

#                                                       my $queues = $class->GLOBAL_HEAP->{server}{id_to_queue};

#                                                       my @queues_list_items;
#                                                       while (my ($id, $queue) = each %$queues) {
#                                                           push @queues_list_items, { text => $queue->name() . ' - ' . $queue->description(),
#                                                                                      value => $id,
#                                                                                    };
#                                                       };
#                                                       @queues_list_items = sort { $a->{text} cmp $b->{text} } @queues_list_items;

#                                                       if (my $new_queue_id = $class->input_list(title => ' Change queue ',
#                                                                                                 items => [ @queues_list_items ],
#                                                                                                 value => $class->GLOBAL_HEAP->{server}{name_to_queue}{$ticket->queue()}->id(),
#                                                                                                )) {
                                                          
#                                                           my $new_queue_name = $class->GLOBAL_HEAP->{server}{id_to_queue}{$new_queue_id}->name();
#                                                           $ticket->queue($new_queue_name);
#                                                           return 1; # stop modal mode
#                                                       }
                                                  } 
                                                },
                                           p => { text => 'change priority',
                                                  code => sub {
                                                      if (my $new_priority = $class->input_ok_cancel('Change priority', $ticket->priority(), 20)) {
                                                          $ticket->priority($new_priority);
                                                          return 1; # stop modal mode
                                                      }
                                                  }
                                                },
                                           o => { text => 'change owner',
                                                  code => sub {},
                                                },
                                          },
                                );
        },
        draw => sub { 
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            my $label;

            my $ticket = Ticket->get_current_ticket();
            my @requestors = $ticket->requestors();
            my @requestor_text_list = map {
                [ 'Requestor ' . $_ . ':' => $requestors[$_-1] ]
            } (1..@requestors);
                        
            my @header_labels = (
                                 # first column
                                 [ [ 'Id:'       => $ticket->id() ],
                                   [ 'Status:'   => $ticket->status() ],
                                   [ 'Queue:'    => $ticket->queue() ],
                                   [ 'Priority:' => $ticket->priority() ],
                                 ],
                                 
                                 # second column
                                 [ [ 'Owner:' => $ticket->owner() ],
                                   @requestor_text_list,
                                   [ 'Cc:' => $ticket->cc() ],
                                 ],
                                 
                                 # third column
                                 [ [ 'Created:' => $ticket->created() ],
                                   [ 'Updated:' => $ticket->last_updated() ],
                                 ],
                                 
                                );
            
            my %label_widgets = $class->struct_to_widgets(\@header_labels, $heap->{height}-2, $heap->{width}-2);
            
            my $form = Curses::Forms->new({
                                           X           => $heap->{'pos_x'},
                                           Y           => $heap->{'pos_y'},
                                           COLUMNS     => $heap->{width},
                                           LINES       => $heap->{height},
                                           
                                           BORDER      => 1,
                                           BORDERCOL   => 'yellow',
                                           CAPTION     => '[ ' . $ticket->subject() . ' ]',
                                           CAPTIONCOL  => 'yellow',
                                           FOREGROUND  => 'white',
                                           BACKGROUND  => 'blue',
                                           DERIVED     => 1,
                                           #        AUTOCENTER  => 1,
                                           TABORDER    => [],
                                           FOCUSED     => 'label1',
                                           WIDGETS     => \%label_widgets,
                                          },
                                         );
            $form->draw($class->get_curses_handler());
            #                        refresh($mwh);

            # draw keys
            my @keys = $kernel->call("ticket_header_$id" => 'available_keys');
            $class->draw_keys_label( Y => $heap->{'pos_y'} + $heap->{height} + 1,
                                     X => $heap->{'pos_x'} + 5,
                                     COLUMNS => $heap->{width} - 2,
                                     VALUE => \@keys,
                                   );

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
