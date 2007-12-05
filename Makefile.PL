use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'RT::Client::Console',
    AUTHOR              => 'Damien "dams" Krotkine <dams@zarb.org>',
    VERSION_FROM        => 'lib/RT/Client/Console.pm',
    ABSTRACT_FROM       => 'lib/RT/Client/Console.pm',
    PL_FILES            => {},
    PREREQ_PM => {
	'Config::Tiny' => 0,
	'Curses' => 0,
	'Params::Validate' => 0,
	'POE' => 0,
	'Curses::Widgets' => 0,
	'RT::Client::REST' => 0,
	'Curses::Forms' => 0,
        'Test::More' => 0,
        'version'    => 0,
	'Error' => 0,
    },
    EXE_FILES           => [ 'bin/rtconsole' ],
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'RT-Client-Console-*' },
);
