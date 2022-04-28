#!/tool/pandora64/bin/perl5.24.0 -w
#===============================================================================
#
#         FILE:  DiskFullAlert.pl
#       $Author: midenney $
#      COMPANY:  aBiz
#      CREATED:  
#     $Revision: 1.8 $
#     $Source: /tool/sysadmin/CVSROOT/makefs/makefs/bin/DiskFullAlert.pl,v $
#
#     Orignally called hack_alert.pl
#===============================================================================

use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use strict;
use DBI;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use Config::IniFiles;
use Log::Log4perl;
use Math::Round qw/round/;
use v5.10;

use Database;
use Util;
use Rpt;

our ($help,$man,$debug,$verbose,$dry_run)  = 0;
my $alarm = 90;

my $quotaScript = "/tool/sysadmin/netapp/scripts/getquota.pl";

my $cfgFile = "$RealBin/../etc/dstools.ini";
my $qtFile = "$RealBin/../etc/qtrees.cfg";
# Basic check is to load it into Config::IniFiles and see if it parses
my $config = new Config::IniFiles(-file => $cfgFile);
defined $config or die("Config::IniFiles cannot parse $cfgFile");

# DEPRECATED This is a list of DS-Tools file system index that we want to watch
# DEPRECATED my @fsid = ("74684","74687","78430","82231");

our $parameters = join(" ",@ARGV); #record parms into global var for reading by util::logging
# Get the options, 
GetOptions('help|?' => \$help, 
	'man'  => \$man,
	'dry-run' => \$dry_run,
	'debug' =>\$debug,
	'verbose' =>\$verbose
	)
	or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-verbose => 2) && exit if defined $man;

my $log = logging($verbose,$debug);

if ($dry_run) {
	$log->warn("dry_run enabled, function calls will be printed and nothing committed!");
}

# Check we can use CVS

my $scmd = << 'END_CMD';
SELECT DFMProjects.name as projName,Sites.id,MountPoints.auto_map,MountPoints.name,DfSize.alloc,DfSize.used,DfSize.files
 FROM MountPoints
  LEFT  JOIN DfSize on MountPoints.fs_id=DfSize.fs_indx
  LEFT  JOIN Sites on MountPoints.site=Sites.indx
  RIGHT JOIN FileSystems on MountPoints.fs_id=FileSystems.indx
  LEFT  JOIN DFMProjects  on FileSystems.project_id=DFMProjects.indx
  WHERE (MountPoints.name = ?
 AND MountPoints.active = 1 AND Sites.id = ?)
 ORDER by date DESC
 LIMIT 1

  ;
  ;
END_CMD
my $dbh = get_database_handle();
my $dfSql = $dbh->prepare($scmd) or die "Couldn't prepare Sql statement: " . DBI::errstr."\n";
########################################################
sub get_alert_{
   #get the ALERt_<site> lines from qtrees.cfg
   unless (-f $qtFile){
      log->error("customQtree()->$qtFile not found");
      return;
   }
   my @fileSystems;
   open(CFG,$qtFile) or die $!;
   while(<CFG>){
     chomp;
     s/#.*//;
     next unless /\S+/;
     s/ //g;
     next unless ( /^\s*ALERT_.+/);
     $log->debug("get_alert_() => Considering line $_");
     my ($Fsite,$trees,$cc,$numnotify)=split(/:/);
     $Fsite=~tr/a-z/A-Z/;
     $Fsite=~s/^ALERT_//g;
     foreach my $tree (split(/,/,$trees)){
       push @fileSystems,("$Fsite $tree $cc");
     }
  } #while CFG
  return \@fileSystems;
}
########################################################
sub determineAlarm{
   ##if detrmine Alarm, return $percUsed else return 0
   my ($dfData) = @_;
   $log->debug("sub determineAlarm ->".Dumper(%$dfData));
   if ($$dfData{alloc} == 0) { return 0; }
   my $percUsed = round(($$dfData{used}/$$dfData{alloc})*100);
   $log->info("sub determineAlarm: percent used = $percUsed .");
   if ($percUsed > $alarm ) {
      $log->info("percUsed $percUsed is above alarm $alarm.");
      return $percUsed;
   }
   return 0;
}
########################################################
sub getQuotas{
   #get qtree quotas info and return $path \@topInfo,  \@headers and \@table contents:.
   my ($dfData) = @_;
   my ($junk,$mapName) = split('\.',$$dfData{auto_map});
   my $path = "/".$mapName."/".$$dfData{name};
   my $cmd = "$quotaScript -s $$dfData{id} -p $path";
   $log->info("Get quotas Command is => $cmd");
   my $quotaData = qx/$cmd/;
   unless ($quotaData){
      $log->error("No results from $cmd");
   }
   $log->debug('quotaData from cmd =>'.$quotaData);
   my @headers = qw(User UID Used Limit Files File_Limit Account_Status);
   my @table; 
   my @quotas;
   my @rawquotas = split("\n",$quotaData);
   $$dfData{projName} =~ s/.er$//;
   $$dfData{projName} = lc($$dfData{projName});
   #my $surl = "https://seastar.aBiz.com/#/browser/tree?volume=$$dfData{id}_$$dfData{projName}&path=%2F&selected=$$dfData{name}";
   my $surl = "https://seastar.aBiz.com/#/browser?mode=list&volume=ATL_persephone&path=$$dfData{name}";
   $log->info("StarFish URL => $surl");
   my @topInfo;
   push(@topInfo,"<a href=\"$surl\">StarFish disk details for  $$dfData{name}.</a><br>\n");
   push(@topInfo,"Choose network login.<br>\n");
   push (@topInfo,$rawquotas[2]."\n<br>");
   push (@topInfo,$rawquotas[3]."\n<br>");
   #@rawquotas = splice @rawquotas,7;
   @rawquotas = splice @rawquotas,3;
   $log->debug('@rawquotas dumper =>'.Dumper(@rawquotas));
   for my $line (@rawquotas){
       if ($line =~ m/^(\S+)\s?\((\d+)\)\s+(\-|(\d+\.\d+\s+\S+))\s+(\-|(\d+\.\d+\s+\S+))\s+(\-|\d+)\s+(\-|\d+)(\s+(\S+))?/){
          my @tline = ($1,$2,$3,$5,$7,$8,$10);
          push @quotas,[@tline];
       }
   }
   $log->debug("Cooked quotas Dumper =>".Dumper(@quotas));
   return $path, \@topInfo, \@headers, \@quotas;
}
########################################################
sub sendEmail{
   my ($dfData,$cc,$path,$topinfo,$headers,$quotas,$percUsed) = @_;
   for my $line (@$quotas){
      my $qname = $$line[0];
      if ($qname =~ 'root'){
         next;
      }
      $cc .= ",$qname\.aBiz.com";
   }
   my ($junk,$mapName) = split('\.',$dfData->{'auto_map'});
   my %opts = (
      email_to => $cc,
      email_from => 'DISK MONITOR.aBiz.com',
      email_subject => "WARNING:Disk Usage for $path $percUsed% used",
      styleheader => $config->val( 'global', 'styleheader' ),
      mailhost => $config->val( 'global', 'mailhost'),
   );
   my $rpto = Rpt->new(\%opts);
   unless (@$topinfo){
      $log->error('Missing @$topinfo , not sending email');
      return 0;
   }
   unless (@$quotas){
      $log->error('Missing @$quotas , not sending email');
      return 0;
   }
   $rpto->MakeEmailBodyHeaders(join("\n",@$topinfo));
   $rpto->MakeEmailBody($headers,$quotas);
   my $msg = "SMTP success";
   unless ($dry_run){
       $log->info("Sending SMTP for $path to  : ".$rpto->email_to);
       foreach my $chk (split(",",$rpto->email_to)){
          if ( not $chk =~ /.+@.+/){
             $log->error("email address missing @ : $chk" );
          }
       }
       unless ($rpto->SendEmail){
           $msg = "SMTP failed";
       }
   } else { $msg = "Not sending email because of dry_run"; }
   $log->info($msg);
}
########################################################
sub TestEmail{
   my %opts = (
      email_to => 'michael.denney.aBiz.com',
      email_from => 'DISK MONITOR.aBiz.com',
      email_subject => "Testemail",
      styleheader => $config->val( 'global', 'styleheader' ),
      mailhost => $config->val( 'global', 'mailhost'),
   );
   my $rpto = Rpt->new(\%opts);
   $rpto->email_body("Insert text here");
   my $msg = "SMTP success";
   unless ($dry_run){
       $log->info("Sending SMTP to  : ".$rpto->email_to);
       foreach my $chk (split(",",$rpto->email_to)){
          if ( not $chk =~ /.+@.+/){
             $log->error("email address missing @ : $chk" );
          }
       }
       unless ($rpto->SendEmail){
           $msg = "SMTP failed";
       }
   } else { $msg = "Not sending email because of dry_run"; }
   $log->info($msg);
}
########################################################
###############      main()      #########################
#TestEmail();exit;
my $fileSystems  = get_alert_;
$log->debug('dumper @fileSystems '. Dumper(@$fileSystems));
foreach my $line (@$fileSystems) {
    my ($site,$fs,$cc) = split(' ',$line);
    $log->info("Working with filesystem $fs at $site, executing SQL");
    $log->info("Executing SQL");
    $log->debug("SQL statement  => ".$$dfSql{Statement});
    unless ( $dfSql->execute($fs,$site) ) {
       $log->error("Unable to execute fsSql: ".DBI::errstr);
       continue;
    }
    my $dfData = $dfSql->fetchrow_hashref();
    $log->debug('%$dfData Dumper =>'.Dumper $dfData);
    unless ($dfData) {
       $log->error("No row returned from SQL call for filesystem:$fs site:$site"); 
       next;
    }
    my $percUsed = "";
    unless ($percUsed =  determineAlarm($dfData)){
       next;
    }
    $log->info("FileSystem $fs percent used => $percUsed");
    my ($path, $topinfo, $headers, $quotas) = getQuotas($dfData);
    sendEmail($dfData,$cc,$path,$topinfo,$headers,$quotas,$percUsed);  
}

$log->info("End");
