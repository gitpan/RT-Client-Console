package RT::Client::Console::Session::Ticket::CustFields;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Curses::Forms;
use Params::Validate qw(:all);
use POE;
use POSIX qw(floor);
use relative -to => "RT::Client::Console", 
        -aliased => qw(Connection Session Session::Ticket);


# class method

# custfields session creation
sub create {
    my ($class, $id) = @_;
    $class->SUPER::create(
    "ticket_custfields_$id",
    inline_states => {
        init => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{pos_x } = 0;
            $heap->{pos_y } = 1 + 7;  # tabs-bar + headers
            $heap->{height} = 4;
        },
        window_resize => sub { 
            my ($kernel, $heap, $old_screen_h, $old_screen_w) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
            $heap->{width} = $heap->{screen_w} * 2 / 3 - 2;  # - border
        },
        available_keys => sub {
            return (['u', 'change custom fields', 'change_custfields']);
        },
        change_custfields => sub {
            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
            $class->create_choice_modal(
                                  title => 'Change Custom fields',
                                  text => '',
                                  keys => {
                                           n => { text => 'new custom field',
                                                  code => sub {
                                                      if (my $field_name = $class->input_ok_cancel('New custom field name',
                                                                                                   '', 500)) {
                                                          if (my $field_value = $class->input_ok_cancel("$field_name value",
                                                                                                        '', 500)) {
                                                              my $ticket = Ticket->get_current_ticket();
                                                              $ticket->cf($field_name, $field_value);
                                                              $ticket->set_changed(1);
                                                              return 1; # stop modal mode
                                                          }
                                                      }
                                                  },
                                                },
                                           e => { text => 'edit custom field',
                                                  code => sub {
                                                      my $ticket = Ticket->get_current_ticket();
                                                      my @custom_fields = sort $ticket->cf();
                                                      my $field_name = $class->input_list(title => ' Edit custom fields ',
                                                                                          items => [ @custom_fields ],
                                                                                          value => $custom_fields[0],
                                                                                         );
                                                      if (my $field_value = $class->input_ok_cancel("$field_name value",
                                                                                                    '', 500)) {
                                                          $ticket->cf($field_name, $field_value);
                                                          $ticket->set_changed(1);
                                                          return 1; # stop modal mode
                                                      }
                                                  }
                                                },
                                           d => { text => 'delete custom field',
                                                  code => sub {
                                                      my $ticket = Ticket->get_current_ticket();
                                                      my @custom_fields = sort $ticket->cf();
                                                      my $field_name = $class->input_list(title => ' Delete custom fields ',
                                                                                          items => [ @custom_fields ],
                                                                                          value => $custom_fields[0],
                                                                                         );
                                                      $ticket->cf($field_name, undef);
                                                      $ticket->set_changed(1);
                                                      return 1; # stop modal mode
                                                  }
                                                },
                                          },
                                );
        },
        draw => sub { 
            my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
            my $label;

            my $ticket = Ticket->get_current_ticket();
            my @custom_fields = sort $ticket->cf();
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
            
            my %custom_fields_widgets = $class->struct_to_widgets(\@custom_fields_labels, $heap->{height}-1, $heap->{width});
            
            my $form = Curses::Forms->new({
                                           X           => $heap->{'pos_x'},
                                           Y           => $heap->{'pos_y'},
                                           COLUMNS     => $heap->{width},
                                           LINES       => $heap->{height},
                                           
                                           BORDER      => 1,
                                           BORDERCOL   => 'yellow',
                                           CAPTION     => '[ Custom fields ]',
                                           CAPTIONCOL  => 'yellow',
                                           FOREGROUND  => 'white',
                                           BACKGROUND  => 'blue',
                                           DERIVED     => 1,
                                           #        AUTOCENTER  => 1,
                                           TABORDER    => [],
                                           FOCUSED     => 'label1',
                                           WIDGETS     => \%custom_fields_widgets,
                                          },
                                         );
            $form->draw($class->get_curses_handler());
            #                        refresh($mwh);

            # draw keys
            my @keys = $kernel->call("ticket_custfields_$id" => 'available_keys');
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
