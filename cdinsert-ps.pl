#!/usr/bin/perl -Tw
use strict;
use warnings;
#-----------------------------------------------------------------------------
# cdinsert.pl - updated for hostmonster.com site
#
# Web interface to "cdlabelgen"
# March 2013 v4.00+: Now run solely on remote web hosts and only runs cdlabelgen so
# only outputs PostScript files. Does not create PDF or images or local files.
#
# Creates CD Jewel Case Inserts, files output in PostScript format.
# This script is similar to the script used for the Online Interface at:
# http://www.aczoom.com/tools/cdinsert/
# and is provided as an example. There is no documention for this script,
# other than program comments in this file itself.
# -----------------------------------------------------------------------
my $VERSION = "4.21";
# my $VERSION = "4.20"; # hostmonster final version, then moved to linode
# Updated: Apr 2021: Comments added about installing perl dependencies
# Updated: Apr 2021: ImageMagick EPS output failing, use EPSF instead
# Updated: Jul 2017: Comments added about installing perl dependencies [4.20 to 4.21]
# Updated: Mar 2013: only outputs .ps files, so can be used on most any web host
# Updated: Aug 2007: added support for barcodegen using --tray-overlay
# Updated: Oct 2008: added support for double width DVDs --double-case
# Updated: Dec 2008: add -sPAPERSIZE to ps2pdf also, for correct A4 size
# Updated: Nov 2009: add nocoverheading option
# Updated: Mar 2013: remove PDF, image, and local files, only outputs Poscript files
# Created: March 2001, by Avinash Chopde <avinash@aczoom.com>  www.aczoom.com
# -----------------------------------------------------------------------
# tar xvzf cdlabelgen-4.3.0.tgz [download from aczoom.com web site]
# cd cdlabelgen-4.3.0; sudo make install
#    [don't do this: sudo apt install cdlabelgen, it has older version]
#
# https://www.ctan.org/tex-archive/support/jpeg2ps
#   get http://mirrors.ctan.org/support/jpeg2ps/jpeg2ps-1.8.zip
#   http://gnuwin32.sourceforge.net/packages/jpeg2ps.htm
#   make will probably fail, run make -n and modify command as needed:
#   gcc  -D_LARGEFILE_SOURCE=1 -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -Wall -O3 -fms-extensions -ffast-math -mtune=native jpeg2ps.c asc85ec.c readjpeg.c -o jpeg2ps
#   May also need: sudo apt install build-essential
#   sudo cp jpeg2ps /usr/local/bin
#
# Install Perl package GD::Barcode::Image for barcodegen:
# The dependencies for this include Image::Magick and GD which are
# difficult to install.
# The following commands work, as an example. If they fail, usually because
# some image magick header file is not found, or there is no sudo access,
# an alternative to try to manually build and install Magick Perl.
#   sudo apt install imagemagick
#   sudo apt install perlmagick
#   sudo apt install libgd-perl
#   cpan -i GD::Barcode::Image
#
# jpegtran:
# sudo apt install libjpeg-progs [or jhead]
#
# -----------------------------------------------------------------------
# Note that there is bug https://rt.cpan.org/Ticket/Display.html?id=20297
# that has not been fixed in long time. It will cause QRcode generation to
# be unable to auto-select version, so a lot of input will fail.
# Fix it locally by changing to this in QRCode.pm init, make it 0 not 1:
# $oSelf->{Version} = $rhPrm->{Version} || 0;  # now auto-select works
# ----
# Files/folders in any PATH dir:
#   cdlabelgen barcodegen jpeg2ps jpegtran
# ----
# Edit the top section of this CGI script to point to files at your site.
# Edit cdlabelgen @where_is_the_template to point to 'cdlabelgen/postscript/' at your site.
#
#-----------------------------------------------------------------------------
# If need, site updates - may not need it.  If need to pick up the Perl modules
# installed using the web host cPanel or such.
BEGIN {
    # my $b__dir = (-d '/home2/aczoomco/perl'?'/home2/aczoomco/perl':( getpwuid($>) )[7].'/perl');
    # unshift @INC,$b__dir.'5/lib/perl5',$b__dir.'5/lib/perl5/x86_64-linux-thread-multi',map { $b__dir . $_ } @INC;
}
# --------------

use CGI 3.21 qw(escapeHTML); # at least 2.47 for upload, 2.50 for Vars, 3.21 for POST_MAX fix
$CGI::POST_MAX=1024 * 1024 * 2;  # max size posts accepted, bytes
use CGI::Carp qw(fatalsToBrowser);
use POSIX qw(floor);
use Socket qw(:DEFAULT :crlf);
use IO::File;
use File::Temp; # File::Temp->new files get removed when object goes out of context

#-----------------------------------------------------------------------------
# Change these variables to match your site
# Following vars need to be set specifically for each site 
# $HOMEDIR/tmp needs to be writeable by web script. Use a path outside public_html
my $HOMEDIR="/var/www/aczoom.com"; # linode.aczoom.com
# my $HOMEBIN="$HOMEDIR/bin";

# Need to run programs: barcodegen cdlabelgen jpegtran jpeg2ps
# security blanket (make sure all folders/files are non-writeable by others!)
# $ENV{'PATH'}="$HOMEBIN:$HOMEDIR/perl5/bin:/usr/bin:"; # hostmonster
$ENV{'PATH'}="/usr/bin:/usr/local/bin"; # linode

my $TMPDIR = "$HOMEDIR/tmp";
my $LOGFILENAME = "$TMPDIR/cgi-bin-log.txt";

# Nothing below this needs changing, usually
#-----------------------------------------------------------------------------
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};   # Make %ENV safer

my $start_time = time();

my $SCRIPT = "cdinsert-ps.pl"; # name of this script
my $DEBUG = 0; # 0 no debug messages, 1 some messages, 2 more.
$SIG{HUP} = $SIG{INT} = $SIG{QUIT} = $SIG{PIPE} = $SIG{TERM} = \&sighandler;

# Create the CGI object
my $QUERY = new CGI;

# logfile gets two lines per job - start time, and ending time.
# Keep track of jobs run ... Important: need to manually truncate/clean out this log file.
my $LOGFILE = IO::File->new($LOGFILENAME, ">>") # open LOGFILE in append mode
   or &errorexit("Could not open logfile $LOGFILENAME: $!");

# verbose logging - script progress as well as error messages are here
# these will be inserted in a PostScript file - so they should always be single lines each
my @MESSAGES = ();

# input form text is stored in this file, file needed to pass as argument to cdlabelgen
my $SAVINPUT = File::Temp->new(TEMPLATE => 'cdlIXXXXX', DIR => $TMPDIR, SUFFIX => '.txt');

# Name this job
# my $TDATE = sprintf("%02d%02d%1d", (localtime($start_time))[3], (localtime($start_time))[2], (localtime($start_time))[1]/10); # current date hour minute(tens)
my $TDATE = sprintf("%02d%02d", (localtime($start_time))[3], (localtime($start_time))[2]); # current date hour
my $WORKID = "cd$TDATE-" . floor(rand(1e4)); # max 4 digits

my $REDIRECT="< /dev/null 2>&1";
# -- cmd 1:
my $CDLBL_E = "cdlabelgen $REDIRECT";
# -- cmd 2:
# barcodegen - from GD::Barcode::Image to be available
my $BCODEFILE = 0; # will be created only if needed
# 2021: ImageMagick convert --format=EPS returns Uninitialized while EPS2,
# EPS3, ESPF work. EPSF is 7bit ASCII
my $BCODE_E = "barcodegen $REDIRECT  --format=EPSF --border=7 --write="; # append: $BCODEFILE
my $CDL_BCODE_ARGS=" --tray-overlay-scaleratio=1,-0.1,0.1 --tray-overlay "; # append $BCODEFILE

# -- cmd 3: support for jpeg input files - handle it like barcodegen above
# PostScript cannot handle Progressive JPEG's, so have to run
# jpegtran on every input JPG file to convert it to baseline JPEG
# replace the following words below:
#   UPLOADEDFILE with the .jpg file name uploaded from form
#   TEMPFILE with a temp file name
#   OUTPUTFILE with the .eps file to create
my $JPG2PS_E = "(jpegtran -outfile TEMPFILE UPLOADEDFILE && jpeg2ps -r 72 -o OUTPUTFILE TEMPFILE) $REDIRECT";

#-----------------------------------------------------------------------------
# Start the work, read in web form http POST data

# select((select(STDOUT), $| = 1)[0]); # autoflush, not needed since we don't output HTML

exit(&main());

sub main {
    my $cepsfile; # temp file for .eps version of uploaded cover .jpg file
    my $tepsfile; # temp file for .eps version of uploaded tray .jpg file
    my $tranfile; # temp file for both cover/tray jpegtran conversion

    my $hostname = $QUERY->remote_host() || '';
    my $hostaddr = $QUERY->remote_addr() || '';

    my $message = "$WORKID v$VERSION [" . localtime($start_time) . "] Starting job for $hostname\n";
    push @MESSAGES, $message;
    print $LOGFILE  $message;

    #----------------------------------------------------------------
    my $cgierror = $QUERY->cgi_error(); # post too big, or user hit STOP, etc...
    if ($cgierror) {
        if ($cgierror =~ /413/) {
            &errorexit("Uploaded files too large?<br/> Received too much data - got <b>" . int($ENV{'CONTENT_LENGTH'}/1024) . "</b> KBytes, can only receive maximum of <b>" . int($CGI::POST_MAX/1024) . "</b> KBytes.");
        } else {
            &errorexit($cgierror);
        }
    }

    # collect form variables, untainting as needed (// operator returns list, so assign to my list)
    # untaint everything even  if not used in expresses - perl cannot handle modifiers correctly
    # https://rt.perl.org/rt3/Public/Bug/Display.html?id=17867 [bug] taint mode and instruction modifier
    # Also see explanation in http://perldoc.perl.org/perlsec.html :
    # For efficiency reasons, Perl takes a conservative view of whether data is tainted. If an expression contains tainted data, any subexpression may be considered tainted, even if the value of the subexpression is not itself affected by the tainted data. An exception is ?: operator, so use that to untaint things.
    # And a "if modifier" suffix to a statement is all one expression, so best to untaint everything.
    #
    my $useragent = $QUERY->user_agent() || 'CGI query - no useragent';
    my $referer = $QUERY->referer() || '';
    my $intitle = $QUERY->param('title') || '';
    my $insubtitle = $QUERY->param('subtitle') || '';
    my $inclogo = $QUERY->param('clogo') || '';
    my $intlogo = $QUERY->param('tlogo') || '';
    my ($incimage) = ($QUERY->param('cimage') || '') =~ /([\d\w\-\.]+)/; # no / allowed in name
    my ($intimage) = ($QUERY->param('timage') || '') =~ /([\d\w\-\.]+)/; # no / allowed in name

    my $incimagefile = $QUERY->param('cimagefile');
    $incimagefile = $QUERY->tmpFileName($incimagefile) if ($incimagefile); # get actual temp file name
    $incimagefile = ($incimagefile || '') =~ /(.*)/; # yes, really need this, is local file path of uploaded temp file
    $incimagefile = $1;
    my $intimagefile = $QUERY->param('timagefile');
    $intimagefile = $QUERY->tmpFileName($intimagefile) if ($intimagefile); # get actual temp file name
    $intimagefile = ($intimagefile || '') =~ /(.*)/; # yes, really need this, is local file path of uploaded temp file
    $intimagefile = $1;
    my $incontents = $QUERY->param('contents') || '';
    $incontents =~ s/$CR?$LF/\n/g; # fix all CR/LF chars
    # for many of the booleans below, need to untaint them even though not passing them to `cmd`
    # due to perl optimizations https://rt.perl.org/rt3/Public/Bug/Display.html?id=17867
    my ($incdcase) = ($QUERY->param('cdcase') || '') =~ /([\d\w\-\.]+)/; # untaint
    my $innotrayhd = $QUERY->param('notrayheading') ? 1 : 0;
    my $innocoverhd = $QUERY->param('nocoverheading') ? 1 : 0;
    my $inscaleitems = $QUERY->param('scaleitems') ? 1 : 0;
    my $ina4paper = $QUERY->param('a4paper') ? 1 : 0;
    my $insplititems = $QUERY->param('splititems') ? 1 : 0;
    my $infilename = $QUERY->param('filename') || '';
    my $infile = $QUERY->upload('filename') || ''; # get file handle
    my ($inbcodetype) = ($QUERY->param('bcodetype') || '') =~ /([\d\w\-\.]*)/; # no / allowed in name
    my $inbcodetext = $QUERY->param('bcodetext') || '';

    my $gotstring = ($incontents =~ /\S+/);
    my $gotfile = ($infilename =~ /\S+/);

    if ($DEBUG > 1) {
        push @MESSAGES, "Got these values from the form:\n";
        my ($key, $value);
        my %params = $QUERY->Vars();
        while (($key, $value) = each %params) {
            # assuming value is single string - if multi-valued, need
            # to split on \0 to get array of values...
            $value = "<supplied string>" if ( $key =~ /^string$/ );
            push @MESSAGES, "  $key = '$value'\n";
        }
        push @MESSAGES, "Some environment vars:\n";
        push @MESSAGES, "  user_agent = '$useragent'\n";
        push @MESSAGES, "  referer = '$referer'\n";
    }

    # Jan02: accept empty input, most common error, so better to accept it
    # don't quit, even on no gotstring or file .. may have inlogo or incimagefile for example.
    # ($gotstring || $gotfile || $intitle || $insubtitle || $incimage || $intimage)
    #     or errorexit("Nothing to do - empty input - no fields entered!");

    my $null_in_contents = 0;
    my $num_items = 0; # number of items or lines in the input text
    if ($gotfile) { # ignore $gotstring, file takes precedence
        if ($gotstring) {
            push @MESSAGES, "** Warning: user entered text as well as filename, ignoring text.\n",
        }
        while (<$infile>) {
            # read each line to get correct EOLN value for this platform (works?)
            s/$CR?$LF/\n/; # variables from Socket package
            print $SAVINPUT $_;
            $null_in_contents += (index($_, "\000") + 1);
            $num_items += 1;
        }
        close $infile; # now $SAVINPUT string has the input text it - from form, or file
        push @MESSAGES, "... read in uploaded file: $infile\n" if ($DEBUG >= 1);
    } else {
        print $SAVINPUT $incontents;
        $null_in_contents += (index($incontents, "\000") + 1);
        my @items = split(/\n/, $incontents);
        $num_items = $#items + 1;
    }
    $SAVINPUT->close(); # close and flush file so it can passed as argument to cdlabelgen

    # now exit if file was bad - NULLs in it, etc.
    # some people post binary files here, and ghostscript gs hangs on
    # such text, so have to remove invalid characters
    # don't really know a sure-fire way of detecting binary files or
    # deleting all non-printable chars (ISO-Latin1, ASCII, etc??)
    # so, doing something that is probably good enough in most cases
    # this is just more protection - there may be code above to return
    # errors if a non-text file is uploaded for the list of items.
    if ($null_in_contents > 0) {
        errorexit("'$infilename' - not ASCII or Latin1 text. Found null character in input ($null_in_contents).");
    }
    my $start_processing_time = time();
    # ----------------------------------------------------------------------

    # untaint variables...
    # Title and Subtitle should use entire string as entered by user
    # but - do escape any non-alphanumeric character, this should take
    # care of shell metacharacters such as " $ etc
    # Don't quote the title or subtitle:
    #   single quotes are a problem since another \' inside the string gets ignored.
    #   double quotes are a problem since most \ 's are preserved \) remains \)
    # s/([`"\$\\])/\\$1/g;   # use this if enclosing title in double quotes "
    # s/(\W)/\\$1/g;   # use this if NOT enclosing title in any quotes " or ',
    #     is safest since every non-alpha-numeric character is escaped.
    $intitle =~ /(.*)/; # yes, really need this.
    $intitle = $1;
    $intitle =~ s/(\W)/\\$1/g;

    $insubtitle =~ /(.*)/; # yes, really need this.
    $insubtitle = $1;
    $insubtitle =~ s/(\W)/\\$1/g;

    $inbcodetext =~ /(.*)/; # yes, really need this.
    $inbcodetext = $1;
    $inbcodetext =~ s/(\W)/\\$1/g;

    push @MESSAGES, "after untaint: title($intitle) subtitle($insubtitle) clogo($inclogo) tlogo($intlogo)\n"
      if ($DEBUG >= 1);

    # jpg file conversions handle incimage incimagefile and intimage intimagefile
    if ($incimagefile || $intimagefile) {
        # jpegtran output temp file to be used by both cover and/or tray conversions
        $tranfile = File::Temp->new(TEMPLATE => 'cdlTXXXXX', DIR => $TMPDIR, SUFFIX => '.jpg');
        $tranfile->close(); # we only need file name so can close this handle

        if ($incimagefile) {
            if ($incimage) {
                push @MESSAGES, "** Warning: user selected built-in Cover Image and uploaded Image, ignoring built-in.\n";
            }

            $cepsfile = File::Temp->new(TEMPLATE => 'cdlCXXXXX', DIR => $TMPDIR, SUFFIX => '.eps');
            $incimage = $cepsfile->filename(); # replace incimage with .eps file to use

            my $cmd = $JPG2PS_E;
            #   UPLOADEDFILE with the .jpg file name uploaded from form
            #   TEMPFILE with a temp file name
            #   OUTPUTFILE with the .eps file to create
            $cmd =~ s/UPLOADEDFILE/$incimagefile/g;
            $cmd =~ s/TEMPFILE/$tranfile/g;
            $cmd =~ s/OUTPUTFILE/$cepsfile/g;

            &do_cmd($cmd);
        }
        if ($intimagefile) {
            if ($intimage) {
                push @MESSAGES, "** Warning: user selected built-in Tray Image and uploaded Image, ignoring built-in.\n";
            }

            $tepsfile = File::Temp->new(TEMPLATE => 'cdlYXXXXX', DIR => $TMPDIR, SUFFIX => '.eps');
            $intimage = $tepsfile->filename(); # replace intimage with .eps file to use

            my $cmd = $JPG2PS_E;
            #   UPLOADEDFILE with the .jpg file name uploaded from form
            #   TEMPFILE with a temp file name
            #   OUTPUTFILE with the .eps file to create
            $cmd =~ s/UPLOADEDFILE/$intimagefile/g;
            $cmd =~ s/TEMPFILE/$tranfile/g;
            $cmd =~ s/OUTPUTFILE/$tepsfile/g;

            &do_cmd($cmd);
        }
    }

    # compute -S and -T scale factors.
    # use the special value "0.0" if image is to be printed as background,
    # otherwise use no scaling (1.0 scale factor).
    my $clogoscale = ($inclogo) ? "1.0" : "0.0";
    my $tlogoscale;
    $incdcase = '' unless ($incdcase);
    if ($incdcase =~ /^normal/) {
      $tlogoscale = ($intlogo) ? "1.0" : "fill2"; # fill2: fill endcaps too
    } else {
      $tlogoscale = ($intlogo) ? "1.0" : "fill1"; # fill1: just fill tray
    }

    # ---- compute page offset for A4 and gs command modifications
    if ($ina4paper) {
      $ina4paper = "-y 1.5"; # default
      $ina4paper = "-y 0.8" if ($incdcase =~ /^(dvd)|(envelope)|(double)/);
    }
    #-----------------------------------------------------------------------------
    # check if barcode generation has to be performed - this requires
    # barcodegen - from GD::Barcode::Image to be available
    if ($inbcodetype && $inbcodetext) {

        $BCODEFILE = File::Temp->new(TEMPLATE => 'cdlBXXXXX', DIR => $TMPDIR, SUFFIX => '.eps');
        $BCODE_E .= $BCODEFILE . " --type '$inbcodetype' $inbcodetext";
        $CDL_BCODE_ARGS .= $BCODEFILE;

        &do_cmd($BCODE_E);
        $BCODEFILE->close();
    }
    #-----------------------------------------------------------------------------

    # 1: run cdlabelgen to create .ps file

    my @cmdargs = ();
    push(@cmdargs, "-c $intitle") if ($intitle); # no quotes around title...
    # don't use single quotes, embedded \' causes problems in title/subtitle
    push(@cmdargs, "-s $insubtitle") if ($insubtitle); # no quotes around title...
    push(@cmdargs, "-e '$incimage'") if ($incimage);
    push(@cmdargs, "-S '$clogoscale'") if ($incimage);
    push(@cmdargs, "-E '$intimage'") if ($intimage);
    push(@cmdargs, "-T '$tlogoscale'") if ($intimage);
    push(@cmdargs, "-f $SAVINPUT");
    push(@cmdargs, "-D");
    push(@cmdargs, "-m") if ($incdcase =~ /^slimcase/); 
    push(@cmdargs, "-M") if ($incdcase =~ /^envelope/);
    push(@cmdargs, "--create-dvd-inside") if ($incdcase =~ /^dvdinside/);
    push(@cmdargs, "--create-dvd-outside") if ($incdcase =~ /^dvdoutside/);
    push(@cmdargs, "--double-case") if ($incdcase =~ /^doublecase/);
    push(@cmdargs, "-p") if (! $inscaleitems); 
    push(@cmdargs, "-b") if ($innotrayhd);
    push(@cmdargs, "-C") if ($innocoverhd);
    push(@cmdargs, $ina4paper) if ($ina4paper);
    push(@cmdargs, $CDL_BCODE_ARGS) if ("$BCODEFILE");

    # if number of items is very large, print some items on the cover also
    # Note: even though it should not matter, this requires $insplititems to be untainted
    push(@cmdargs, "-v " . int($num_items/2)) if ($num_items > 250 || $insplititems);

    # push(@cmdargs, "-o $WORKFILE.ps"); # not this, just print to stdout

    # cdlabelgen arguments:
    # -c <category>    Set the category (title) for the CD
    # -s <subtitle> 
    # -d <date>    default: YYCC-MM-YY
    # -D don't print date
    # -f <filename>    input filename
    # -e <cover_epsfile>
    # -E <tray_epsfile>
    # -m   for slim cd cases
    # --create-dvd-inside   for inside inserts for DVD cases
    # -M   for CD envelope
    # -p   clip text - don't scale down item (if required to fit to a column)
    # -b   don't print the plaque (title/subtile) on tray_card
    # -y 1.5 or -y 0.8 for A4 paper

    my $cmd = join(' ', $CDLBL_E, @cmdargs);
    my $output_str = &do_cmd($cmd);

    # -----
    my $end_time = time();
    my $time_taken = $end_time - $start_time;
    my $receive_time_taken = $start_processing_time - $start_time;
    my $time_taken_units = ($time_taken <= 1) ? "1 second" : "$time_taken seconds";
    $message = "$WORKID took $time_taken secs";
    $message .= " (download $receive_time_taken) " if ($incimagefile || $intimagefile);
    # $message .= " [error]"  if ($errflag);
    $message .= "\n";
    push @MESSAGES, $message;

    # Output the .ps file to stdout
    # Include the messages from this script as comments in the Postscript file
    my $ps_messages = join('% ', @MESSAGES);

    # Insert the messages in the output string
    # Line "% WEB-SCRIPT-MESSAGES-HERE\n" from the cdlabelgen template.ps is replaced
    $output_str =~ s/% WEB-SCRIPT-MESSAGES-HERE\n/\% ${ps_messages}/;

    # If we didn't exit, we can output the .ps file
    # return the .ps file as result of this submit button execution
    # output HTML headers for sending the postscript file - only if no error occured.
    print STDOUT $QUERY->header(-type => 'application/postscript',
        -charset => "ISO-8859-1",
        -expires => "now",
        -content_disposition => "inline; filename=cdinsert.ps");
    print STDOUT $output_str; # Output PS file. All done with STDOUT and this script.

    # Log file update with the last message sent
    print $LOGFILE $message;

    return (0);
}

#-----------------------------------------------------------------------------
# Subroutines
# They may add status messages to @MESSAGES and in rare cases, write to $LOGFILE

sub do_cmd {
    # Runs given command, and returns command output
    my ($cmd) = @_;

    push @MESSAGES, "$WORKID cmd: $cmd\n";

    my $out = `$cmd`;
    my $returncode = ($? >> 8); 
    if ($returncode != 0) {
	push @MESSAGES, "cmd failed $returncode: $out\n";
        &errorexit("Command $cmd failed: $out");
    }
    $out;
}
#-----------------------------------

sub sighandler {
    my $str = "$WORKID user or system terminated --\n";
    print $LOGFILE  $str;
    exit(1);
}

#-----------------------------------

sub errorexit {
    # Report the given message using full HTML headers , and exit with error status
    my($mesg) = @_;
    my $str = "Error running cdlabelgen: $mesg";

    print $LOGFILE  $str if $LOGFILE; # to this script's logfile
    print STDERR $str; # goes to Apache error_log

    # We never print CGI headers in the main script except at the very end, so
    # if we are quitting earlier, need to output full HTML headers.
    print STDOUT $QUERY->header, # create the HTTP header
        $QUERY->start_html('Error running cdlabelgen'), # start the HTML
        $QUERY->h1($str), # level 1 header
        $QUERY->h2("Script messages:"), # level 1 header
        $QUERY->pre(escapeHTML(join('', @MESSAGES))), # display the collected status messages too
        $QUERY->p("---"), # display the collected status messages too
        $QUERY->end_html; 

    exit(2);
}
#----------------------------------------
