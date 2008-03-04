package RT::Client::Console;

use strict;
use warnings;

use Carp;
use Curses;
use Curses::Forms::Dialog;
use Curses::Forms::Dialog::Input;
use Curses::Widgets::ListBox;
use List::Util qw(min max);
use Params::Validate qw(:all);
use relative -aliased => qw(Connection Session Session::Root Session::KeyHandler);

our $VERSION = '0.0.6';


=head1 NAME

RT::Client::Console - Text based RT console

=head1 SYNOPSIS

  rtconsole [OPTIONS]
  rtconsole --help

=head1 DESCRIPTION

RT::Client::Console distribution provides an executable I<rtconsole> and
modules. The executable is a full-featured curses-based interface to any RT
server that has REST interface enabled.

The modules provides comprehensive ways to connect, interact and display
informations from the RT server. A plugin mechanism is planned, and will enable
more flexibility.

=cut

# global Curses handler
my $curses_handler;
sub get_curses_handler {
    return $curses_handler;
}

# global configuration
my $configuration;
sub set_configuration {
    my $class = shift;
    my %params = validate( @_, { configuration => { type => HASHREF },
                               }
                         );
    $configuration = $params{configuration};
}

sub get_configuration {
    return $configuration;
}

# main method. effectively starts the console
sub run {
    my $class = shift;
    my %params = validate( @_, { curses_handler => { isa => 'Curses' },
                                 rt_servername => 0,
                                 rt_username => 0,
                                 rt_password => 0,
                               }
                         );

    $curses_handler = delete $params{curses_handler};
    
    Root->create();

    KeyHandler->create();

    if ( exists $params{rt_servername}) {
        Connection->connect(%params);
    }

    # starts POE runtime
    Session->run();
    
}


# curses related methods

sub restart_curses {
	endwin;
	refresh;
}

{

my $need_cls = 0;
sub cls {
    my ($class) = @_;
    $need_cls = 1;
    return;
}
sub need_cls {
    return $need_cls;
}
sub reset_cls {
    $need_cls = 0;
    return;
}

}

# draws the list of supported keys and description
sub draw_keys_label {
    my $class = shift;                         
    my %params = validate( @_, { COLUMNS     => { type => SCALAR },
                                 BACKGROUND  => { type => SCALAR,
                                                  default => 'blue',
                                                },
                                 FOREGROUND  => { type => SCALAR,
                                                  default => 'white',
                                                },
                                 FOREGROUND2 => { type => SCALAR,
                                                  default => 'yellow', 
                                                },
                                 VALUE       => { type => ARRAYREF },  # [ [ key => 'label' ], [...] ]
                                 X           => { type => SCALAR },   
                                 Y           => { type => SCALAR },
                                 erase_before => { type => SCALAR,
                                                   optional => 1,
                                                 },
                                 erase_background => { type => SCALAR,
                                                       default => 'black', 
                                                     },
                               }
                         );

    my $current_x = 0;
    my $max_length  = $params{COLUMNS};
    my $foreground  = $params{FOREGROUND};
    my $foreground2 = $params{FOREGROUND2};
    my $background  = $params{BACKGROUND};

    if ($params{erase_before}) {
        my $label = Curses::Widgets::Label->new({ BORDER      => 0,
                                                  LINES       => 1,
                                                  COLUMNS     => $max_length,
                                                  Y           => $params{Y},
                                                  X           => $params{X},
                                                  VALUE       => ' ' x $max_length,
                                                  FOREGROUND  => $foreground,
                                                  BACKGROUND  => $params{erase_background},
                                                });
        $label->draw($class->get_curses_handler());
    }
    foreach my $key_struct (@{$params{VALUE}}) {
        my ($key, $text) = @$key_struct;
        $key = " $key: ";
        $text = "$text ";
        attron(A_BOLD);
        $max_length -= length($key);
        $max_length >= 0 or last;
        my $label = Curses::Widgets::Label->new({ BORDER      => 0,
                                                  LINES       => 1,
                                                  COLUMNS     => length($key),
                                                  Y           => $params{Y},
                                                  X           => $params{X} + $current_x,
                                                  VALUE       => $key,
                                                  FOREGROUND  => $foreground2,
                                                  BACKGROUND  => $background,
                                                });
        $label->draw($class->get_curses_handler());
        $current_x += length($key);
        attroff(A_BOLD);

        $max_length - length($text) >= 0 or $text = substr($text, 0, $max_length);
        $max_length -= length($text);
        $label = Curses::Widgets::Label->new({ BORDER      => 0,
                                               LINES       => 1,
                                               COLUMNS     => length($text),
                                               Y           => $params{Y},
                                               X           => $params{X} + $current_x,
                                               VALUE       => $text,
                                               FOREGROUND  => $foreground,
                                               BACKGROUND  => $background,
                                             });
        $label->draw($class->get_curses_handler());
        $current_x += length($text);
        $current_x++;
        $max_length--;
    }
}

# display a simple error message
sub error {
    my ($class, $message) = @_;
    dialog('Error', BTN_OK, $message, 
           qw(white red yellow));
    $class->cls();
    return;
}

# display an input box. returns the entered value on success, or empty list on
# failure. 
sub input_ok_cancel {
    my ($class, $title, $message, $length) = @_;
    my ($rv, $value) = input("[ $title ]", BTN_OK | BTN_CANCEL, $message, $length || 256,
                             qw(white blue yellow));
    # XXX bug, if one doesn't enter anything, or an empty string or 0 or '0'...
    $class->cls();
    if ( $rv == 0) {
        return $value
    }
    return;
}

# display a list box
sub input_list {
    my $class = shift;
    my %params = validate( @_, { items => { type => ARRAYREF }, # list items, array of (values or (hashrefs of text => value))
                                 title => { type => SCALAR },   # list box title
                                 value => { type => SCALAR },   # initial value
                               }
                         );
    my @items = @{$params{items}};

    my $list_style = 1; #simple
    ref $items[0] eq 'HASH' and $list_style = 0; #complex

    my @display_items = $list_style ? @items : map { $_->{text} } @items;
    my @value_items = $list_style ? @items : map { $_->{value} } @items;

    my $i; 
    my %index_of = map { $_ => $i++ } @value_items;
    my %name_of = reverse %index_of;
    my $value_idx = $index_of{$params{value}};
    my $title = $params{title};

    # get screen size
    my ($screen_w, $screen_h);
    $curses_handler->getmaxyx($screen_h, $screen_w);

    my $height = min(@display_items + 2, $screen_h - 20);
    my $width = min( max( map { length } (@display_items, $title) ) + 2, $screen_w - 20 );

    my $list_box = Curses::Widgets::ListBox->new({ LINES       => $height,
                                                   COLUMNS     => $width,
                                                   Y           => $screen_h/2-($height+2)/2,
                                                   X           => $screen_w/2-($width+2)/2,,
                                                   LISTITEMS   => \@display_items,
                                                   MULTISEL    => 0,
                                                   VALUE       => $value_idx,
                                                   FOCUSSWITCH => "\n",
                                                   SELECTEDCOL => 'red',
                                                   CAPTION     => $title,
                                                   CAPTIONCOL  => 'yellow',
                                                   CURSORPOS   => $value_idx,
                                                 });
    $class->my_execute($list_box, $curses_handler);
    my $new_value = $name_of{$list_box->getField('VALUE')};
    $class->cls();
    return $new_value;
}


{

my %label_widgets;
my $widget_name_index = 0;

# from a Perl structure, draw labels
sub struct_to_widgets {
    my ($class, $header_labels, $max_lines, $max_columns) = @_;
    my @header_labels = @$header_labels;

    my $x = 0;
    my %label_widgets;
    foreach my $group (@header_labels) {
        my $y = 0;
        my $key_width = max( map { length } map { $_->[0] } @$group );
        $x + $key_width > $max_columns
          and $key_width = $max_columns - $x;
        $key_width > 0 or last;

        my $value_width = max( map { length } map { $_->[1] || '' } @$group );
        $x + $key_width + 1 + $value_width > $max_columns
          and $value_width = $max_columns - ($x + $key_width + 1);
        
        foreach my $element (@$group) {
            
            $y > $max_lines and last;

            $label_widgets{"label$widget_name_index"} =
              {
               TYPE        => 'Label',
               X           => $x,
               Y           => $y,
               COLUMNS     => $key_width,
               LINES       => 1,
               FOREGROUND  => 'yellow',
               BACKGROUND  => 'blue',
               VALUE       => $element->[0],
               ALIGNMENT   => 'R',
              };
            $widget_name_index++;

            if ($value_width) {

                $label_widgets{"label$widget_name_index"} =
                  {
                   TYPE        => 'Label',
                   X           => $x + $key_width + 1,
                   Y           => $y,
                   COLUMNS     => $value_width,
                   LINES       => 1,
                   FOREGROUND  => 'white',
                   BACKGROUND  => 'blue',
                   VALUE       => $element->[1],
                   ALIGNMENT   => 'L',
                  };
                $widget_name_index++;
            }
            $y++;
        }
        $x += $key_width + 1 + $value_width +2;
    }
    return %label_widgets;
}

}

# temporary pause POE events and run the widget in modal mode
sub my_execute {
  my ($class, $self, $mwh) = @_;
  my $conf = $self->{CONF};
  my $func = $conf->{INPUTFUNC} || \&Curses::Widgets::scankey;
  my $regex = $conf->{FOCUSSWITCH};
  my $key;

  $self->draw($mwh, 1);

  while (1) {
    $key = $func->($mwh);
    if (defined $key) {
      $self->input_key($key);
      if (defined $regex) {
        return $key if ($key =~ /^[$regex]$/);
      }
    }
    $self->draw($mwh, 1);
  }
}

1; # Magic true value required at end of module
__END__

=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

=over

=item Config::Tiny

=item Curses

=item Params::Validate

=item POE

=item Curses::Widgets

=item RT::Client::REST

=item Curses::Forms

=item Test::More

=item version

=item Error

=back

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-rt-client-console@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 AUTHOR

Damien "dams" Krotkine  C<< <dams@cpan.org> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Damien "dams" Krotkine C<< <dams@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
