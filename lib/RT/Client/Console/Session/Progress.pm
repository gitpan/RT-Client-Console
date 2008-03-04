package RT::Client::Console::Session::Progress;

use strict;
use warnings;

use parent qw(RT::Client::Console::Session);

use POE;

my @progress_texts = ();

# class method

# progress session creation
sub create {
    my ($class) = @_;

    $class->SUPER::create(
        'progress_draw',
        inline_states => {
                          init => sub {
                              my ($kernel, $heap) = @_[ KERNEL, HEAP ];
                          },
                          draw => sub {
                              my ( $kernel, $heap) = @_[ KERNEL, HEAP ];
                              my $draw_x = 0;
                              my @toremove = ();

                              my $curses_handler = $class->get_curses_handler();

                              my $label = Curses::Widgets::Label->new({
                                        BORDER      => 0,
                                        X           => 0,
                                        Y           => $heap->{screen_h} - 1,
                                        COLUMNS     => $heap->{screen_w},
                                        LINES       => 1,
                                        VALUE       => '',
                                        FOREGROUND  => 'black',
                                        BACKGROUND  => 'black',
                                    });
                              $label->draw($curses_handler);
                              
                              foreach my $pos (0..@progress_texts-1) {
                                  my ($text, $erase) = @{$progress_texts[$pos]};
                                  length $text or next;
                                  
                                  if ($erase) {
                                      push @toremove, $pos;
                                  } else {
                                      $label = Curses::Widgets::Label->new({
                                        BORDER      => 0,
                                        LINES       => 1,
                                        COLUMNS     => length($text),
                                        Y           => $heap->{screen_h} - 1,
                                        X           => $draw_x,
                                        VALUE       => $text,
                                        FOREGROUND  => 'white',
                                        BACKGROUND  => 'red',
                                        });
                                      $label->draw($curses_handler);
                                      $draw_x += length($text) + 1;
                                  }
                              }
                              foreach(@toremove) {
                                  splice(@progress_texts, $_, 1);
                              }
                          },
                         },
                         );
}

# add an asynchronous progress session
sub add_progress {
    my ($class, %args) = @_;

    my $progress_text = ['', 0];
    push @progress_texts, $progress_text;

    my $progress_session = POE::Session->create(
        inline_states => {
            _start => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                $heap->{value} = 0;
                $args{initially}->();
                $kernel->yield('draw');
                $kernel->yield('code');
            },
            code => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                if ($args{code}->()) {
                    $heap->{value}++;
                    $kernel->yield('draw');
                    $kernel->yield('code');
                } else {
                    $args{finally}->();
                    $kernel->yield('draw', 1);
                }
            },
            draw => sub {
                my ( $kernel, $heap, $erase ) = @_[ KERNEL, HEAP, ARG0 ];

                my $value = $args{caption}->() . ':' . int($heap->{value}*100/($args{steps_nb}->()||1)) . '%';
                $erase and $value = ' ' x length $value;

                $progress_text->[0] = $value;
                $progress_text->[1] = $erase;

                $kernel->post('key_handler', 'draw_all');
            },
        },
    );
}

# add an asynchronous progress session
sub add_and_execute {
    my ($class, $text, $code) = @_;

    my $progress_text = [$text, 0];
    push @progress_texts, $progress_text;
    $poe_kernel->call('progress_draw', 'draw');

    my @ret;
    eval { @ret = wantarray ? $code->() : scalar($code->()) };
	my $save_error = $@;

    $progress_text->[0] = ' ' x length $text;
    $progress_text->[1] = 1;
    $poe_kernel->call('progress_draw', 'draw');

    $save_error and die $save_error;
    return @ret;
}

1;
