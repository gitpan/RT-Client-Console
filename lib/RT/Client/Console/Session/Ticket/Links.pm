package RT::Client::Console::Session::Ticket::Links;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use Curses::Forms;
use Params::Validate qw(:all);
use POE;
use relative -to => "RT::Client::Console", 
        -aliased => qw(Cnx Session Session::Ticket Session::Progress);

# class method

# links session creation
sub create {
    my ($class, $id) = @_;
    $class->SUPER::create(
    "ticket_links_$id",
    inline_states => {
        init => sub {
            my ($kernel, $heap) = @_[ KERNEL, HEAP ];
            $heap->{pos_y } = 1;  # tabs-bar
        },
        window_resize => sub { 
            my ($kernel, $heap, $old_screen_h, $old_screen_w) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
            $heap->{pos_x } = $heap->{screen_w} * 2 / 3 + 1;
            $heap->{width } = $heap->{screen_w} - $heap->{pos_x} - 2;  # - border
            $heap->{height} = $heap->{screen_h} - $heap->{pos_y} - 2 - 2;  # - status - border
        },
        available_keys => sub {
            return (['l', 'change links', 'change_links']);
        },
        change_links => sub {
            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
            $class->create_modal( title => 'Change tickets links',
                                  text => '',
                                  keys => {
                                           p => { text => 'change parents',
                                                  code => sub {
                                                      if (my $new_parents = $class->input_ok_cancel('Change parents', join(', ', map {$_->id() } @{$heap->{parents}}), 500)) {
                                                          return 1; # stop modal mode
                                                      }
                                                      
                                                  }
                                                },
                                           c => { text => 'change children',
                                                  code => sub {
                                                      if (my $new_children = $class->input_ok_cancel('Change children', join(', ', map {$_->id() } @{$heap->{children}}), 500)) {
                                                          return 1; # stop modal mode
                                                      }
                                                      
                                                  }
                                                },
                                           d => { text => 'change depends',
                                                  code => sub {
                                                      if (my $new_children = $class->input_ok_cancel('Change depends', join(', ', map {$_->id() } @{$heap->{depends}}), 500)) {
                                                          return 1; # stop modal mode
                                                      }
                                                      
                                                  }
                                                },
                                           D => { text => 'change depended',
                                                  code => sub {
                                                      if (my $new_children = $class->input_ok_cancel('Change depended', join(', ', map {$_->id() } @{$heap->{depended}}), 500)) {
                                                          return 1; # stop modal mode
                                                      }
                                                      
                                                  }
                                                },
                                           r => { text => 'change refers',
                                                  code => sub {
                                                      if (my $new_children = $class->input_ok_cancel('Change refers', join(', ', map {$_->id() } @{$heap->{refers}}), 500)) {
                                                          return 1; # stop modal mode
                                                      }
                                                      
                                                  }
                                                },
                                           R => { text => 'change referred',
                                                  code => sub {
                                                      if (my $new_children = $class->input_ok_cancel('Change referred', join(', ', map {$_->id() } @{$heap->{refered}}), 500)) {
                                                          return 1; # stop modal mode
                                                      }
                                                      
                                                  }
                                                },
                                          }
                                );
        },
        draw => sub { 
            my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
            my $label;

            my $ticket = Ticket->get_current_ticket();
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

            my $form = Curses::Forms->new({
                                                       X           => $heap->{'pos_x'},
                                                       Y           => $heap->{'pos_y'},
                                                       COLUMNS     => $heap->{width},
                                                       LINES       => $heap->{height},

                                                       BORDER      => 1,
                                                       BORDERCOL   => 'yellow',
                                                       CAPTION     => '[ Relations ]',
                                                       CAPTIONCOL  => 'yellow',
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
            $form->draw($class->get_curses_handler());
            #                        refresh($mwh);

            # draw keys
            my @keys = $kernel->call("ticket_links_$id" => 'available_keys');
            $class->draw_keys_label( Y => $heap->{'pos_y'} + $heap->{height} + 1,
                                     X => $heap->{'pos_x'} + 5,
                                     COLUMNS => $heap->{width},
                                     VALUE => \@keys,
                                   );
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
    my $rt_handler = Cnx->get_cnx_data()->{handler};
    Progress->add_progress(
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
                            Ticket->open_from_id($id);
                          #                                           $kernel->post('ticket_links', 'draw');
                          return 1;
                      },
            finally => sub { 
                $kernel->post('ticket_links', 'draw'),
            },
    );
}

1;
