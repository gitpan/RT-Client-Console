package RT::Client::Console;

use warnings;
use strict;
use Carp;
our $VERSION = '0.0.2';

use Params::Validate qw(:all);

# global heap to keep an application-level state
my %GLOBAL_HEAP = ( curses => { 
								handler => undef, 
							    need_clear => 0,
							   },
					rt => { cnx => {
									handler => undef,
									servername => undef,
									username => undef,
									password => undef,
								   },
							tickets => {
										current_id => undef, # current ticket id
										list => [], # arrayref containing the ordered tickets objects list
										
#										attachments => {
#													   current => undef,
#													   total => 0,
#													  },
#										total => 0,
									   },
						  },
					server => {
							   id_to_queue => {},
							   name_to_queue => {},
							  },
					ui => {
						   tab => {
								   current => undef,
								   total => 0,
								  },
						   modal_sessions => [],
						  },
#					current_atta => undef,
#					total_tab => 0,
#					current_tab => undef,
					sessions => {},
				  );
sub GLOBAL_HEAP { \%GLOBAL_HEAP }

sub run {
	my ($class, @args) = @_;
	my %params = validate( @args, { curses_handler => { isa => 'Curses' },
									rt_servername => 0,
									rt_username => 0,
									rt_password => 0,
									queue_ids => 0,
								  }
						 );


	$class->GLOBAL_HEAP->{curses}{handler} = delete $params{curses_handler};

	use RT::Client::Console::Session::Root;
	RT::Client::Console::Session::Root->create();

	use RT::Client::Console::Session::KeyHandler;
	RT::Client::Console::Session::KeyHandler->create();

	if ( exists $params{rt_servername}) {
		use RT::Client::Console::Cnx;
		RT::Client::Console::Cnx->connect(%params);
	}

	use RT::Client::Console::Session;
	RT::Client::Console::Session->run();
	
}

sub cls {
    my ($class) = @_;
	$class->GLOBAL_HEAP->{curses}{need_clear} = 1;
	return;
}


use Curses::Forms::Dialog;
sub error {
    my ($class, $message) = @_;
    dialog('Error', BTN_OK, $message, 
           qw(white red yellow));
	$class->cls();
    return;
}

use Curses::Forms::Dialog::Input;
sub input_ok_cancel {
    my ($class, $title, $message, $length) = @_;
    my ($rv, $value) = input($title, BTN_OK | BTN_CANCEL, $message, $length || 256,
                             qw(white blue yellow));
    # XXX bug, if one doesn't enter anything, or an empty string or 0 or '0'...
	$class->cls();
    if ( $rv == 0) {
        return $value
    }
	return;
}

use Curses::Widgets::ListBox;
sub input_list {
    my ($class, %args) = @_;
	my @items = @{$args{items}};

	my $list_style = 1; #simple
	ref $items[0] eq 'HASH' and $list_style = 0; #complex

	my @display_items = $list_style ? @items : map { $_->{text} } @items;
	my @value_items = $list_style ? @items : map { $_->{value} } @items;

	my $i; 
	my %index_of = map { $_ => $i++ } @value_items;
	my %name_of = reverse %index_of;
	my $value_idx = $index_of{$args{value}};
	my $title = $args{title};

	my ($screen_w, $screen_h);
	my $curses_handler = $class->GLOBAL_HEAP->{curses}{handler};
	$curses_handler->getmaxyx($screen_h, $screen_w);

	use List::Util qw(min max);
	my $height = min(@display_items + 2, $screen_h - 20);
	my $width = min( max( map { length } (@display_items, $title) ) + 2, $screen_w - 20 );

	my $list_box = Curses::Widgets::ListBox->new({
												  LINES       => $height,
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

sub struct_to_widgets {
    my ($class, $header_labels, $max_lines, $max_columns) = @_;
    my @header_labels = @$header_labels;

    my $x = 0;
    my %label_widgets;
    foreach my $group (@header_labels) {
        my $y = 0;
		use List::Util qw(max);
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

sub my_execute {
  my $class = shift;
  my $self = shift;
  my $mwh = shift;
  my $conf = $self->{CONF};
  my $func = $$conf{'INPUTFUNC'} || \&Curses::Widgets::scankey;
  my $regex = $$conf{'FOCUSSWITCH'};
  my $key;

  $self->draw($mwh, 1);

  while (1) {
    $key = &$func($mwh);
    if (defined $key) {
      $self->input_key($key);
      if (defined $regex) {
        return $key if ($key =~ /^[$regex]/);
      }
    }
    $self->draw($mwh, 1);
  }
}

1; # Magic true value required at end of module
__END__

=head1 NAME

RT::Client::Console - [One line description of module's purpose here]


=head1 VERSION

This document describes RT::Client::Console version 0.0.1


=head1 SYNOPSIS

    use RT::Client::Console;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE 

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
RT::Client::Console requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-rt-client-console@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Damien "dams" Krotkine  C<< <dams@zarb.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Damien "dams" Krotkine C<< <dams@zarb.org> >>. All rights reserved.

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
