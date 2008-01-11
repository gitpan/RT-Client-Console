use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'RT::Client::Console',
    LICENSE             => 'perl',
    AUTHOR              => 'Damien "dams" Krotkine <dams@zarb.org>',
    VERSION_FROM        => 'lib/RT/Client/Console.pm',
    ABSTRACT_FROM       => 'lib/RT/Client/Console.pm',
    EXE_FILES           => [ 'bin/rtconsole' ],
    PREREQ_PM           => {
        # prereqs
	'Config::Tiny'      => '2.03',
	'Curses'            => '1.20',
	'Curses::Forms'     => '1.997',
	'Curses::Widgets'   => '1.997',
	'Error'             => '0.17011',
	'Params::Validate'  => '0.89',
	'parent'            => '0.218',
	'POE'               => '0.9999',
	'RT::Client::REST'  => '0.32',
	'relative'          => '0.03',
	'version'           => '0.74',

        # build/test prereqs
	'Test::More'        => 0,
    },
    PL_FILES            => {},
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'RT-Client-Console-*' },
);
