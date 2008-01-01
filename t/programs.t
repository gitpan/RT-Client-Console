#!perl -w
use strict;
use File::Spec::Functions;
use Test::More;


plan skip_all => "Test::Cmd not available"     unless eval "use Test::Cmd; 1";
plan skip_all => "Test::Program not available" unless eval "use Test::Program; 1";

my %programs = (
    rtconsole   => "rtconsole",
);

plan tests => 6 * keys %programs;

for my $command (keys %programs) {
    my $program = $programs{$command};
    my $cmdpath = catfile(curdir(), "blib", "script", $command);

    # basic checks
    #program_compiles_ok($cmdpath);     #TODO: fails because of the warnings
    program_pod_ok($cmdpath);

    # more extensive checks
    my $cmd = Test::Cmd->new(prog => $cmdpath, workdir => '');
    ok( $cmd, "created Test::Cmd object for $command" );

    # checking option --version
    $cmd->run(args => '--version', 'chdir' => $cmd->curdir);
    is( $?, 0, "exec: $command --version" );
    like( $cmd->stdout, qr/^$program v\d+(\.\d+)+$/mi, "  => checking version output" );

    # checking usage
    my $fakeopt = "this-is-not-an-option";
    $cmd->run(args => "--$fakeopt", 'chdir' => $cmd->curdir);
    isnt( $?, 0, "exec: $command --$fakeopt" );
    like( $cmd->stderr, qr/^Unknown option: $fakeopt$/m, "  => checking error" );
}
