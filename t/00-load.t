#!perl -Tw
use strict;
use File::Spec::Functions;
use lib curdir();
use Test::More;


my @modules = qw(
    RT::Client::Console
    RT::Client::Console::Connection
    RT::Client::Console::Session
    RT::Client::Console::Session::KeyHandler
    RT::Client::Console::Session::Progress
    RT::Client::Console::Session::Root
    RT::Client::Console::Session::Status
    RT::Client::Console::Session::TabBar
    RT::Client::Console::Session::Ticket
    RT::Client::Console::Session::Ticket::Attachments
    RT::Client::Console::Session::Ticket::CustFields
    RT::Client::Console::Session::Ticket::Header
    RT::Client::Console::Session::Ticket::Links
    RT::Client::Console::Session::Ticket::Transactions
);

my @programs = qw(
    rtconsole
);

plan tests => @modules + @programs;

# try to load all modules
for my $module (@modules) {
    use_ok( $module );
}

# try to load the programs, which should at this stage be in blib/
for my $program (@programs) {
    require_ok( catfile(curdir(), "blib", "script", $program) );
}
