#
# Revision History:
#
#   18-May-2003 Dick Munroe (munroe@csworks.com)
#       Get the version number from script/kif.
#

use ExtUtils::MakeMaker;

require 5.8.0 ;

my @scripts = qw(kif) ;

WriteMakefile
   (NAME => "kif",
    VERSION_FROM => "./script/kif",
    EXE_FILES => [ map { "script/$_" } @scripts ], 
    PREREQ_PM => {'File::Basename' => 2.71,
		  'File::Copy' => 2.05,
		  'File::stat' => 1.00,
		  'FileHandle' => 2.01,
		  'Getopt::Long' => 2.32,
		  'StanzaFile' => 1.00
	      },
    ($[ >= 5.005) ?
        (AUTHOR   => 'Dick Munroe (munroe@csworks.com)',
         ABSTRACT => 'Kernel Installation Facility script and support modules') : (),
    'dist' => {COMPRESS=>'gzip',SUFFIX=>'gz'}
   );
