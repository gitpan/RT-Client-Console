package RT::Client::Console::Cnx;

use strict;
use warnings;

use parent qw(RT::Client::Console);

use Curses::Forms::Dialog::Logon;
use Curses::Forms::Dialog::Input;
use Error qw(:try);
use Params::Validate qw(:all);
use RT::Client::REST;
use relative -aliased => qw(::Session::Ticket);


# global connection data
my %cnx_data = (
                handler => undef,    # RT handler
                servername => undef,
                username => undef,
                password => undef,
               );

sub get_cnx_data {
    return { %cnx_data };
}

# connect to the RT server. asks the needed information is missing.
sub connect {
    my $class = shift;
    my %params = validate( @_, { rt_servername => 0,
                                 rt_username => 0,
                                 rt_password => 0,
                               }
                         );

    if (!$params{rt_servername}) {
        $params{rt_servername} = $class->input_ok_cancel('Connexion', 'RT server name');
    }
    $params{rt_servername} or return;

     try {
         my $rt_handler = RT::Client::REST->new(
                                                server  => $params{rt_servername},
                                               );
        if (!(defined $params{rt_username} && defined $params{rt_password})) {
            (my $rv, $params{rt_username}, $params{rt_password}) = logon('connect to RT server', BTN_OK | BTN_CANCEL, 50, qw(white red yellow) );
        }
        $rt_handler->login(username => $params{rt_username}, password => $params{rt_password});
        $cnx_data{handler} = $rt_handler;
        $cnx_data{servername} = $params{rt_servername};
        $cnx_data{username} = $params{rt_username};
        $cnx_data{password} = $params{rt_password};

        $class->cls();
     } catch Exception::Class::Base with {
         $class->error("problem logging in: $@" . shift->message());
     };
    return;
}

# disconnect from RT, unload loaded tickets
sub disconnect {
    my ($class) = @_;
    undef $cnx_data{handler};
    undef $cnx_data{servername};
    undef $cnx_data{username};
    undef $cnx_data{password};
    my $ticket;
    while ($ticket = Ticket->get_current_ticket()) {
        $ticket->unload();
    }
    return;
}


1;
