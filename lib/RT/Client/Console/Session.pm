package RT::Client::Console::Session;

use strict;
use warnings;

use parent qw(RT::Client::Console);

use POE;
use List::Util qw(max first);
use Curses::Widgets::Label;
use Curses::Forms;

use relative -to => "RT::Client::Console::Session", 
        -aliased => qw(Ticket);

use Params::Validate qw(:all);

# global vars

my %sessions;
my @modal_sessions;
my $modal_index = 0;

sub get_sessions { return %sessions }

sub get_modal_sessions { return @modal_sessions }

# a small wrapper around POE::Session
sub create {
    my ($class, $name, %args) = @_;
    my $is_modal = delete $args{_is_modal};
    $args{inline_states}{_start} = sub { 
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        $kernel->alias_set($name);
#        $kernel->call($name, 'window_resize', undef, undef);
        $kernel->call($name, 'init');
        $kernel->call($name, '__window_resize', !$is_modal);
    };
    $args{inline_states}{_unalias} = sub {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        my @aliases = $kernel->alias_list();
        foreach my $alias (@aliases) {
            $kernel->alias_remove($alias);
        }
    };
    # automatic window change handling
	$args{inline_states}{__window_resize} = sub {
        my ($kernel, $heap, $is_init_mode) = @_[ KERNEL, HEAP, ARG0 ];
        my ($old_screen_h, $old_screen_w) = @{$heap}{qw(screen_h screen_w)};
        my ($screen_w, $screen_h);
        $class->get_curses_handler()->getmaxyx($screen_h, $screen_w);
        $heap->{screen_h} = $screen_h;
        $heap->{screen_w} = $screen_w;
        print STDERR " -- $name -- __window resize " . $heap->{screen_w} . " | " . $heap->{screen_h} . "\n";
        $is_init_mode or $kernel->yield('draw');
        # give a chance to the session to do something specific
        $kernel->call($name, 'window_resize', $old_screen_h, $old_screen_w);
    };

	if ($is_modal) {
        my $keys = delete $args{keys};
        $args{inline_states}{key_handler} = sub {
            my ( $kernel, $heap, $keystroke ) = @_[ KERNEL, HEAP, ARG0 ];
            if (!defined $keys) { 
                $kernel->yield('private_key_handler', $keystroke);
                $kernel->yield('draw');
                return;
            }
            exists $keys->{$keystroke} or return;
            if ($keys->{$keystroke}{code}->()) {
                $class->remove_modal($name);
            } else {
                $kernel->yield('draw');
            }
        };
        POE::Session->create(%args);
        push @modal_sessions, $name;
    } else {
        $sessions{$name} = {
                            poe_object => POE::Session->create(%args),
                            displayed => 1,
                           };
    }
    return $name;
}

# create a modal session
sub create_modal {
    my ($class, %args) = @_;
    $args{_is_modal} = 1;
    my $name = 'modal_' . ++$modal_index;
    return create($class, $name, %args);
}

sub create_choice_modal {
    my ($class, %args) = @_;

    my $title = "[ $args{title} ]";    
    my $text = $args{text} . "\n";

    exists $args{interactive} or $args{interactive} = 1;
    if ($args{interactive}) {
        $args{keys}{c} ||= { text => "close this dialog",
                             code => sub { return 1 },
                           };
        while (my ($k, $v) = each %{$args{keys}} ) {
            $text .= "$k : " . $v->{text} . "\n";
        }
        $args{keys}{'<^[>'} ||= { text => "close this dialog",
                             code => sub { return 1 },
                           };
    }

    my $height = scalar( () = $text =~ /(\n)/g) + 1;
    my $width = max (map { length } (split(/\n/, $text), $title));

    return create_modal(
        $class,
        keys => $args{keys},
        inline_states => {
            draw => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                my $curses_handler = $class->get_curses_handler();
                my $label = Curses::Widgets::Label->new({
                                                         CAPTION     => $title,
                                                         CAPTIONCOL  => 'yellow',
                                                         BORDER      => 1,
                                                         LINES       => $height,
                                                         COLUMNS     => $width,
                                                         Y           => $heap->{screen_h}/2-($height+2)/2,
                                                         X           => $heap->{screen_w}/2-($width+2)/2,
                                                         VALUE       => $text,
                                                         FOREGROUND  => 'white',
                                                         BACKGROUND  => 'blue',
                                                         BORDERCOL   => 'white',
                                                        });
                $label->draw($curses_handler);
            }
        },
                       );

}

sub create_wait_modal {
    my ($class, $text) = @_;
    return create_choice_modal($class,
                               title => 'Please wait',
                               text => $text,
                               interactive => 0,
                              );
}

sub execute_wait_modal {
    my ($class, $text, $code) = @_;
    my $modal_session_name = 
      create_wait_modal($class, $text);
    $poe_kernel->call($modal_session_name, 'draw');
    my @ret;
    eval { @ret = wantarray ? $code->() : scalar($code->()) };
	my $save_error = $@;
    remove_modal($class, $modal_session_name);
    $save_error and die $save_error;
    return @ret;
}

sub remove_modal {
    my ($class, $modal_session_name) = @_;
    # stop modal mode
    pop @modal_sessions;
    remove($class, $modal_session_name);
    $poe_kernel->post('key_handler', 'compute_keys');
    # if no ticket is displayed, we clear the background
    Ticket->get_current_ticket() or $class->cls();
   return;
}

# start the POE main loop
sub run {
    my ($class) = @_;
    $poe_kernel->run();
}

# display/hide a session
sub set_display {
    my ($class, $session_name, $display_state) = @_;
    $sessions{$session_name}{displayed} = $display_state ? 1 : 0;
}

=head2 remove

Removes a session

  input : a session name

=cut

sub remove {
    my ($class, $session_name) = @_;
    delete $sessions{$session_name};
    $poe_kernel->call($session_name, '_quit');
    $poe_kernel->call($session_name, '_unalias');

}

sub remove_all {
    my ($class) = @_;
    my %sessions = $class->get_sessions();
    my @sessions_names = keys(%sessions);
    foreach (@sessions_names) {
        $class->remove($_);
    }
}

sub execute_textmemo_modal {
    my $class = shift;
    my %params = validate( @_, { foreground => { type => SCALAR,
                                                 default => 'white',
                                               },
                                 background => { type => SCALAR,
                                                 default => 'blue',
                                               },
                                 border_color => { type => SCALAR,
                                                   default => 'yellow', 
                                                 },
                                 text       => { type => SCALAR, default => '' },
                                 title      => { type => SCALAR },
                               }
                         );

    my $title = "[ $params{title} ]";    
    my $text = $params{text};

	my ($fg, $bg, $cfg) = ('white', 'blue', 'yellow');

	my ($form, @lines, $max);
	my ($cols, $lines, $bx, $by);

	# Build array of buttons to display
	my @buttons = qw(OK Cancel);

	# Calculate the necessary dimensions of the message box, based
	# on both the button(s) and the length of the message.
	$max = max(15 * @buttons + 2 * $#buttons + 1, 30);
	use Curses;
	@lines = textwrap($text, $COLS - 4);

	foreach (@lines) { $max = length($_) if length($_) > $max };

	# Calculate cols and lines
	$cols = $max + 5;
	$lines = max(scalar(@lines), 10) + 3 + 5;

	# Exit if the geometry exceeds the display
	unless ($cols + 2 < $COLS && $lines + 2 < $LINES) {
		warn "dialog:  Calculated geometry exceeds display geometry!";
		return 0;
	}

	# Calculate upper-left corner of the buttons
	$bx = 10 * @buttons + 2 * $#buttons + 1;
	$bx = int(($cols - $bx) / 2);
	$by = $lines - 3;

	local *btnexit = sub {
		my $f = shift;
		my $key = shift;

		return unless $key eq "\n";
		$f->setField(EXIT => 1);
	};

	$form = Curses::Forms->new({
    AUTOCENTER    => 1,
    DERIVED       => 0,
    COLUMNS       => $cols,
    LINES         => $lines,
    CAPTION       => $title,
    CAPTIONCOL    => $cfg,
    BORDER        => 1,
    FOREGROUND    => $fg,
    BACKGROUND    => $bg,
    FOCUSED       => 'Memo',
    TABORDER      => ['Memo', 'Buttons'],
    WIDGETS       => {
      Buttons     => {
        TYPE      => 'ButtonSet',
        LABELS    => [@buttons],
        Y         => $by,
        X         => $bx,
        FOREGROUND    => $fg,
        BACKGROUND    => $bg,
        BORDER    => 1,
        OnExit    => *btnexit,
        },
      Memo       => {
        TYPE      => 'TextMemo',
        Y         => 0,
        X         => 0,
        COLUMNS   => $max ,
        LINES     => max(scalar @lines, 10) + 2,
        VALUE     => $text,
		CAPTION   => 'Enter new comment',
		CAPTIONCOL => $cfg,
        FOREGROUND => $fg,
        BACKGROUND => $bg,
        },
      },
    });
	$form->execute;

	return ( $form->getWidget('Buttons')->getField('VALUE'),
			 $form->getWidget('Memo')->getField('VALUE')
		   );
}

1;
