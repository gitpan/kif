#!/usr/bin/perl
#
# Revision History:
#
#   26-Nov-2002 Dick Munroe (munroe@csworks.com)
#       Initial version created.
#       Save and restore the configuration files around the
#       running of doClean.
#       Make doClean issue a distclean to guarantee that things
#       will get built properly.
#
#   03-Dec-2002 Dick Munroe (munroe@csworks.com)
#       Copy autoconf.h as well as .config when saving configuration
#       files.
#
#   18-May-2003 Dick Munroe (munroe@csworks.com)
#       Make sure package variables don't leak.
#
#   19-May-2003 Dick Munroe (munroe@csworks.com)
#       Use Carp.
#

package Build ;

use vars qw($VERSION @ISA) ;

our $VERSION = "1.02" ;
our @ISA = qw(
	      ) ;

use 5.8.0 ;
use strict ;

use Carp ;
use File::Basename ;
use File::Copy ;
use File::stat ;
use FileHandle ;

$Build::theBuildDirectory = undef ;
$Build::theLogFile = undef ;
$Build::theReleaseTag = undef ;
$Build::theTestFlag = undef ;
$Build::theVerboseFlag = undef ;

sub new
{
    my $thePackage = shift ;
    my %theArguments = @_ ;

    my $theObject = bless 
        {
	    bootloader=>undef,
	    logFileHandle=>undef,
	    space=>undef
	}, $thePackage ;

    if (defined($theArguments{'directory'}))
    {
	chdir $theArguments{'directory'} or croak "Can't change to directory $theArguments{'directory'}: $!" ;
    } ;

    $theObject->logFile($theArguments{'log'}) ;

    $theObject->verboseFlag($theArguments{'verbose'}) ;

    $theObject->testFlag($theArguments{'test'}) ;

    $theObject->buildDirectory(`pwd`) ;

    $theObject->_buildReleaseTag() ;

    $theObject->space($theObject->_calculateSpace()) ;

    return $theObject ;
} ;

sub bootloader
{
    my $theObject = shift ;

    $theObject->{'bootloader'} = $_[0] if (@_) ;

    return $theObject->{'bootloader'} ;
} ;

sub buildDirectory
{
    my $theObject = shift ;

    $Build::theBuildDirectory = $_[0] if (@_) ;

    chomp($Build::theBuildDirectory) ;

    return $Build::theBuildDirectory ;
} ;

sub logFile
{
    my $theObject = shift ;

    if (@_)
    {
	$Build::theLogFile = $_[0] ;
	if (defined($Build::theLogFile))
	{
	    $theObject->{'logFileHandle'} = new FileHandle "> $Build::theLogFile" or croak "Can't open log file: $Build::theLogFile" ;
	} ;
    } ;

    return $Build::theLogFile ;
} ;

sub releaseTag
{
    my $theObject = shift ;

    $Build::theReleaseTag = $_[0] if (@_) ;

    return $Build::theReleaseTag ;
} ;

sub space
{
    my $theObject = shift ;

    $theObject->{'space'} = $_[0] if (@_) ;

    return $theObject->{'space'} ;
} ;

sub testFlag
{
    my $theObject = shift ;

    $Build::theTestFlag = $_[0] if (@_) ;

    return $Build::theTestFlag ;
} ;

sub verboseFlag
{
    my $theObject = shift ;

    $Build::theVerboseFlag = $_[0] if (@_) ;

    return $Build::theVerboseFlag ;
} ;

sub _buildReleaseTag
{
    my $theObject = shift ;

    my $theFileHandle = new FileHandle "< Makefile" ;

    croak "Can't open $Build::theBuildDirectory/Makefile" if (!defined($theFileHandle)) ;

    my $theMakefile = eval { my @theFile = $theFileHandle->getlines() ; join '',@theFile ; } ;

    croak "No VERSION in $Build::theBuildDirectory/Makefile" if ($theMakefile !~ m/^[ \t]*VERSION[ \t]*=[ \t]*([^ \t\n]*)/m) ;

    my $theVersion = $1 ;

    croak "No PATCHLEVEL in $Build::theBuildDirectory/Makefile" if ($theMakefile !~ m/^[ \t]*PATCHLEVEL[ \t]*=[ \t]*([^ \t\n]*)/m) ;

    my $thePatch = $1 ;

    croak "No SUBLEVEL in $Build::theBuildDirectory/Makefile" if ($theMakefile !~ m/^[ \t]*SUBLEVEL[ \t]*=[ \t]*([^ \t\n]*)/m) ;

    my $theSublevel = $1 ;

    croak "No EXTRAVERSION in $Build::theBuildDirectory/Makefile" if ($theMakefile !~ m/^[ \t]*EXTRAVERSION[ \t]*=[ \t]*([^ \t\n]*)/m) ;

    my $theKernelRelease = $1 ;
    
    undef $theFileHandle ;

    $theObject->releaseTag("$theVersion.$thePatch.$theSublevel$theKernelRelease") ;
} ;

sub _calculateSpace
{
    my ($theObject, $theDirectory) = @_ ;

    $theDirectory = '.' if (!$theDirectory) ;

    my $theSpace = (split /\s+/,(split /\n/,`df -mP $theDirectory`)[1])[3] ;

    $theObject->_print("Space: $theDirectory => $theSpace\n", 3) ;

    return $theSpace ;
} ;

sub _print
{
    my ($theObject, $theString, $theLevel) = @_ ;

    print $theString if ($theObject->verboseFlag() >= $theLevel) ;

    $theObject->{'logFileHandle'}->print($theString) if (defined($theObject->{'logFileHandle'})) ;
} ;

sub run
{
    my ($theObject, $theCommand) = @_ ;

    $theObject->_print("$theCommand\n", 1) ;

    return if ($theObject->testFlag()) ;

    open theReadHandle, $theCommand . " 2>&1 |" or croak "Can't fork: $!" ;

    while (<theReadHandle>)
    {
	$theObject->_print($_, 2) ;
    } ;

    close theReadHandle or croak "Can't run $theCommand: $!" ;
} ;

#
# Check all the miscellaneous bits and pieces of the build environment
# to make sure they're sane before beginning.
#

sub validate
{
    my $theObject = shift ;

    croak "/boot/vmlinux must be a link" if ((-e "/boot/vmlinux") && (!-l "/boot/vmlinux")) ;
} ;

sub doDependencies
{
    my $theObject = shift ;

    $theObject->run("make dep") ;

    $theObject->space($theObject->_calculateSpace()) ;
} ;

sub doClean
{
    my $theObject = shift ;

    my $theBuildDirectory ;
    my $theReleaseTag ;

    my @theFileList = (".config", "include/linux/autoconf.h") ;
    my $theIndex ;
    my @theATimes ;
    my @theMTimes ;

    my $theBuildDirectory = $theObject->buildDirectory() ;
    my $theReleaseTag = $theObject->releaseTag() ;

    for ($theIndex = 0; $theIndex < scalar(@theFileList); $theIndex++)
    {
	$_ = $theBuildDirectory . '/' . $theFileList[$theIndex] ;

	if (-e $_)
	{
	    #
	    # Save the current configuration, if any.
	    #

	    $theMTimes[$theIndex] = stat($_)->mtime() ;
	    $theATimes[$theIndex] = stat($_)->atime() ;

	    move($_, '/tmp/' . basename($_) . "-$theReleaseTag") if (!$theObject->testFlag()) ;

	    $theObject->_print("Moved $_ => /tmp/" . basename($_) . "-$theReleaseTag\n", 1) ; 
	} ;
    } ;

    $theObject->run("make distclean") ;

    for ($theIndex = 0; $theIndex < scalar(@theFileList); $theIndex++)
    {
	$_ = '/tmp/' . basename($theFileList[$theIndex]) . "-$theReleaseTag" ;

	if (-e $_)
	{
	    #
	    # Restore the current configuration, if any.
	    #

	    move($_, $theBuildDirectory . '/' . $theFileList[$theIndex]) if (!$theObject->testFlag()) ;

	    $theObject->_print("Moved $_ => " . $theBuildDirectory . '/' . $theFileList[$theIndex] . "\n", 1) ; 

	    utime($theATimes[$theIndex], $theMTimes[$theIndex], $theFileList[$theIndex]) ;
				# Restore the file access and modified times to
				# make things look unchanged.
	} ;
    } ;

    #
    # If the configuration files are skewed, i.e., the original creation
    # dates are out of order, then reconstruct the autoconf.h file by running
    # old config.
    #

    if (-e "$theBuildDirectory/.config")
    {
	if (-e "$theBuildDirectory/include/linux/autoconf.h")
	{
	    for ($theIndex = 0; $theIndex < scalar(@theFileList)-1; $theIndex++)
	    {
		if ($theMTimes[$theIndex] > $theMTimes[$theIndex+1])
		{
		    #
		    # The files generated from .config are skewed and need to
		    # be regenerated.
		    #

		    $theObject->run("make oldconfig") ;
		    last ;
		} ;
	    } ;
	}
	else
	{
	    #
	    # autoconf.h doesn't exists and must be built.
	    #

	    $theObject->run("make oldconfig") ;
	} ;
    } ;

    $theObject->space($theObject->_calculateSpace()) ;
} ;

sub doKernel
{
    my $theObject = shift ;

    croak "Need at least 30MB to build a kernel" if ($theObject->space() < 30) ;

    $theObject->run("make kernel") ;

    $theObject->space($theObject->_calculateSpace()) ;
} ;

sub doModules
{
    my $theObject = shift ;

    croak "Need at least 40MB in " . $theObject->buildDirectory() . " to build modules." if ($theObject->space() < 40) ;

    $theObject->run("make modules") ;

    $theObject->space($theObject->_calculateSpace()) ;
} ;

sub doModules_install
{
    my $theObject = shift ;

    croak "Need at least 20MB in /lib/modules/ to install modules" if ($theObject->_calculateSpace("/lib/modules/") < 20) ;

    $theObject->run("make modules_install") ;

    $theObject->_calculateSpace("/lib/modules/") ;

    $theObject->space($theObject->_calculateSpace()) ;
} ;

sub doMovefiles
{
    my $theObject = shift ;

    my $theBuildDirectory = $theObject->buildDirectory() ;
    my $theReleaseTag = $theObject->releaseTag() ;

    my %theFiles =
    (
	"$theBuildDirectory/.config"    => "/boot/config-$theReleaseTag",
	"$theBuildDirectory/include/linux/autoconf.h" => "/boot/autoconf.h-$theReleaseTag",
	"$theBuildDirectory/System.map" => "/boot/System.map-$theReleaseTag",
	"$theBuildDirectory/vmlinux"    => "/boot/vmlinux-$theReleaseTag"
    ) ;
    my %theMode =
    (
	"/boot/vmlinux-$theReleaseTag"  => 0755
    ) ;

    foreach (keys %theFiles)
    {
	if (-e $_)
	{
	    copy($_, $theFiles{$_}) ;
	    $theObject->_print("Moved $_ => " . $theFiles{$_} . "\n", 1) ;
	} ;

	if (defined($theMode{$theFiles{$_}}))
	{
	    chmod($theMode{$theFiles{$_}}, $theFiles{$_}) ;
	} ;
    } ;

    return $theObject ;
} ;

sub doBootloader
{
    my $theObject = shift ;

    $theObject->bootloader->modify($theObject) ;
} ;

sub doLinks
{
    my $theObject = shift ;

    if (!@_)
    {
	$theObject->doLinks('vmlinuz') ;
	$theObject->doLinks('vmlinux') ;
	return ;
    } ;

    my $theKernel = shift ;

    #
    # Make all the soft links that might be needed for the default
    # boot case.
    #

    chdir('/boot') or croak "Can't chdir to /boot: $!" ;

    $theObject->_print("chdir('/boot')\n",3) ;

    if (-e "$theKernel-" . $theObject->releaseTag())
    {
	if (-e "$theKernel")
	{
	    if (-l "$theKernel")
	    {
		unlink("$theKernel") ;
		symlink("$theKernel-" . $theObject->releaseTag(), "$theKernel") ;
		$theObject->_print("Making symbolic link from $theKernel to $theKernel-" . $theObject->releaseTag() . "\n",1) ;
	    }
	    else
	    {
		croak "/boot/$theKernel isn't a symbolic link." ;
	    } ;
	}
	else
	{
	    symlink("$theKernel-" . $theObject->releaseTag(), "$theKernel") ;
	    $theObject->_print("Making symbolic link from $theKernel to $theKernel-" . $theObject->releaseTag() . "\n", 1) ;
	} ;
    } ;
    
    chdir($theObject->buildDirectory()) ;

    $theObject->_print("chdir('" . $theObject->buildDirectory() . "')\n",3) ;
} ;

sub doInitrd
{
    my $theObject = shift ;

    #
    # The default action is to rebuild initrd files if they already
    # exist for this kernel.
    #

    my $theInitrdFile ;
    my $theReleaseTag = $theObject->releaseTag() ;

    if (-e ($theInitrdFile = '/boot/initrd-' . $theReleaseTag . '.img'))
    {
	$theObject->run("mkinitrd -v $theInitrdFile $theReleaseTag") ;
    }
    elsif (defined($theInitrdFile = $theObject->bootloader()->initrdFile()))
    {
	$theObject->run("mkinitrd -v /boot/$theInitrdFile $theReleaseTag") ;
    } ;
} ;

sub doDepmod
{
    my $theObject = shift ;

    $theObject->run('depmod -a -F /boot/System.map-' . $theObject->releaseTag() . " " . $theObject->releaseTag()) ;
} ;

1;
