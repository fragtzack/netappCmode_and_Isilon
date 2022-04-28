$ID = q$Id: Util.pm,v 1.7 2020/06/24 17:14:43 midenney Exp $;
# $Revision: 1.7 $ 
# $Author: midenney $
# Description :  Util provides various small utilities.
# $Source: /tool/sysadmin/CVSROOT/makefs/makefs/lib/Util.pm,v $
#
# comment test

package Util;
use strict;
use FindBin qw($RealBin);
use Data::Dumper;
use File::Basename;
use Log::Log4perl;
use Exporter;
our @ISA = 'Exporter';

use vars qw(@EXPORT);
use subs qw(logging);

@EXPORT = qw(logging);


#use vars qw($script $log);

chdir ($FindBin::Bin);
my $VERSION = '0.1';

##  HISTORY
## 0.1  Just log4perl
sub logging{
  my $script = $FindBin::Script;
  my $logfile = $script;
  $logfile =~ s/\..*//g; ##remove .pl or any .extension from script name
  $logfile  =  '../var/log/'.$logfile.'.log';
  my $screen = "";
  my $loggerLevel = 'INFO';
    #log4perl.logger                    = DEBUG, FileApp
  if ($main::debug){
    $loggerLevel = 'DEBUG';
  }
  if ($main::verbose){
    $screen = ',ScreenApp';
  }
  my $loggerType = "$loggerLevel,FileApp$screen";
  my $log_conf ="                     
    log4perl.logger                    = $loggerType
    log4perl.appender.FileApp          = Log::Log4perl::Appender::File
    log4perl.appender.FileApp.filename = $logfile
    log4perl.appender.FileApp.layout   = PatternLayout
    log4perl.appender.FileApp.layout.ConversionPattern = %d %p> %m%n
    log4perl.appender.ScreenApp          = Log::Log4perl::Appender::Screen
    log4perl.appender.ScreenApp.stderr   = 0
    log4perl.appender.ScreenApp.layout   = PatternLayout
    log4perl.appender.ScreenApp.layout.ConversionPattern = %p> %m%n
  ";
  #log4perl.appender.ScreenApp.layout.ConversionPattern = %d> %m%n
  Log::Log4perl::init(\$log_conf);
  my $log = Log::Log4perl->get_logger();
  if ($main::parameters){
     $log->info("Start logging. Command line args=> ".$main::parameters);
  }
  return ($log);
}
1;
