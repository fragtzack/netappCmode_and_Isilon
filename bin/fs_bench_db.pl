#!/tools/pandora/bin/perl

use strict;
use warnings;
use Getopt::Long;
use DBI;
use Data::Dumper;
use Pod::Usage;
use File::Basename;
use Sys::Hostname;
use sigtrap qw/handler signal_handler normal-signals error-signals/;

use subs qw/vprint signal_handler safe_system/;

my $version = 2; 
my $cut = "/bin/cut";
my $grep = "/bin/grep";

my $n_files = 1024;
my $n_lines = 1024;
my ($i, $j);

my $cmd;
my $path;
my $filer;
my $filer_id;
my $help;
my $verbose;
my $iter = 10; #iteractions of vmstat to use for average
my $testid; #used to associate tests executed at same time from multiple hosts in the database
my $dry;
my $bench_dir;

my $runhost = hostname;

sub signal_handler{
   vprint "signal_handler() Received signal $!";
   if ($bench_dir and -d $bench_dir) {
      vprint "signal_handler() removing $bench_dir directory and all files";
      safe_system( "/bin/rm -rf $bench_dir" );
   }
   die "$!\n";
}

my $fname = fileparse($0);
# Get the options, make sure we have a path, if not give the help text and bail out!
GetOptions('help!' => \$help,
           'path|p=s' => \$path,
           'testid|t=s' => \$testid,
           'dry|d' => \$dry,
           'verbose|v' => \$verbose
           )
 or pod2usage("Try $fname --help for more information");
my $htext = <<"EOT";
NAME
   $fname - Perform file system test and upload results to db.

SYNOPSIS
   $fname [--help]
   $fname [--verbose|-v] [--testid testid] --path path

DESCRIPTION
   $fname is a tool to perform simple testing of NFS shares. 
   $fname will perform a timed test of read/write operations on a filesystem  path and record the results into a DB.
   $fname will time the following actions:
          Create a directory called fs_bench_<hostname>_<testid>  in the specified --path path.
          Create 1000 files of 1000 lines  in fs_bench directory.
          Read the files.
          Delete the files.
          Remove the fs_bench directory.

   The results of the test will then get uploaded to the dataservices DB along with some stats about the client 
   running the test. 

OPTIONS
   --test testid is an arbitary string used to populate a field in the database. The purpose of this id is to 
     associate multiple tests from different hosts into an average result. The testid format should
          be : arrayName_EpochSeconds. For example: hydra_1561393119
   --dry|-d  Dry run, do not update database.
   --verbose|-v Normally run silent. Verbose will display status messages.
   
EOT
if ($help){ pod2usage($htext) };
unless ($path){ 
   $path = '.';
}
#pod2usage($htext) };

sub vprint{
   return unless ($verbose);
   print "@_\n";
}
sub dateprint{
   my $d = qx/date/;chomp $d;
   print "$d - @_\n";
}


vprint "Changing to directory $path \n";
my $result = chdir ($path);

if ($result ne '1') {
	dateprint "Unable to change directory to $path.";
	exit 1;
}

my @dfOut; my $dfPath;
$cmd =  'df -P .';
@dfOut = qx/$cmd/ ; chomp @dfOut;

my $rawFiler;
($rawFiler,$dfPath) = $dfOut[-1] =~ /^(\S+):\S+\s+\d+\s.+%\s+(\S+)/;
($filer) = $rawFiler =~ /^([a-zA-Z0-9]+)?([-_].*)?$/;

dateprint("Start: filer = $filer.");


vprint "Raw filer name=>$rawFiler ,filtered filer name=>$filer  dfPath is $dfPath";
unless ($testid){
   my $usr = getpwuid($<);
   $testid = $usr."_".$filer."_".time();
}

$bench_dir = "fs_bench_db_${runhost}_${testid}";
# Is test already running on this host for a testid, if so need to abort.
if (-d $bench_dir){
   dateprint("Directory already exists!");
   exit 1;
}
# Sometimes LSF queues job on same host in serial, so search the log file to see if already ran with same testid.

my $hname = qx/hostname/;chomp $hname;
my $tst = "grep -q 'testid = $testid.' log/$hname".'.log 2>/dev/null';

my $retCode = system($tst);
#dateprint("grep tst = $tst");
#dateprint("Ret CODE = $retCode");
if ($retCode == 0){
   dateprint("Test already ran or running for testid $testid on this host");
   exit 1;
}

vprint "making $bench_dir";
safe_system( "/bin/mkdir $bench_dir" );

dateprint("Info : Gathering host info. testid = $testid.");

my $filer_ip= 'NA';
my  $re=qr/$dfPath/;
$cmd = "mount -l";
my @mountOut = qx/$cmd/; chomp @mountOut;
if (@mountOut){
   for my $line (@mountOut){
      if ($line  =~ /^\S+\s+on\s+$re\s+type\s+nfs\s+.+addr=(\d+\.\d+\.\d+\.\d+).+$/){
         $filer_ip = $1;
      }
   }
}
vprint "filer_ip=>$filer_ip";

my $dbi = 'dbi:mysql:database=DataServices;host=atlmysql03.aBiz.com;user=ds_user;password=ds_passwd';
# Make the DB connection, and prepare the sql
my $dbh = DBI->connect("$dbi")
	or die "Couldn't make mysql database connection. $DBI::errstr\n";
	
my $insert_sql = $dbh->prepare("INSERT INTO FsBench (filer_indx,filer_ip,path,time,runhost,testid,netRateBytes,load1,load5,load15,freemem,swapUsed,avgRun,avgBlocked,avgIdle) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
	or die "Unable to prepare insert_sql.".$dbh->errstr;
my $filer_id_sql = $dbh->prepare("SELECT indx from FilerData WHERE name = ?")
	or die "Unable to prepare filer_id_sql.".$dbh->errstr;

unless ($dry){
   vprint "Getting filer id from DB";
   $filer_id_sql->execute($filer)
	or die "Unable to execute filer_id_sql.".$filer_id_sql->errstr;
   my $row = $filer_id_sql->fetchrow_hashref();
   $filer_id = $$row{'indx'};
   unless ($filer_id){
      print "filer_id not found in FilerData table. Setting -dry mode.\n";
      $filer_id = 'dry';
      $dry = 1;
   } 
   vprint "filer_id=>$filer_id";
} #unless $dry

vprint "Getting free mem and swap";
$cmd = "egrep '^MemFree|^Buffers|^Cached|^SwapTotal|^SwapFree' /proc/meminfo|awk '{print \$2}'";
#print "$cmd\n";exit;
my @stdout = qx/$cmd/;chomp @stdout;
my $freemem = int ( ($stdout[0] + $stdout[1] + $stdout[2])/1024 );
my $swapUsed= int ( ($stdout[3] - $stdout[4])/1024 );
vprint "free mem -> $freemem";
vprint "swapUsed -> $swapUsed";

vprint "getting network throughput";
$cmd = '/sbin/ip route|awk \'/^default/ {print $NF}\'';
my $interface = qx/$cmd/; chomp $interface;
$cmd = "/bin/awk \'/$interface".':/ {print $2+$10}\' /proc/net/dev';
my $startBytes = qx/$cmd/; chomp $startBytes;
sleep 10;
my $endBytes = qx/$cmd/; chomp $endBytes;
my $periodBytes = $endBytes - $startBytes;
my $netRateBytes = $periodBytes / 10;
vprint "startBytes=>$startBytes endBytes=>$endBytes netRateBytes=>$netRateBytes";

vprint "Getting load average";
my $uptime = qx/uptime/;chomp $uptime;
my ($load1,$load5,$load15) = $uptime =~ /.+\sload average:\s(\d+\.\d+),\s+(\d+\.\d+),\s+(\d+\.\d+)/;
vprint "load1=>$load1 load5=>$load5 load15=>$load15";


vprint "Getting vmstat info";
$cmd = "vmstat -S m 1 $iter".'|tail -n +3|awk \'{rsum+=$1;bsum+=$2;cpusum+=$15}END{print rsum/NR," ",bsum/NR," ",cpusum/NR}\'';
my ($avgRun,$avgBlocked,$avgIdle) = split " ",qx/$cmd/;
vprint "avgRun=>$avgRun avgBlocked=>$avgBlocked avgIdle=>$avgIdle";




my $start = time;

dateprint("Info : running test.");

# Write $n_files files, $n_lines lines each.
vprint "creating files";
for( $i=0; $i<$n_files; $i++ ) {
  open( FILE, ">$bench_dir/f${i}" ) || die "Cannot write f${i}\n";
  for ( $j=0; $j<$n_lines; $j++ ) {
    print FILE "lalala\n";
  }
  close( FILE );
}

# Read them all.
vprint "reading files";
for( $i=0; $i<$n_files; $i++ ) {
  safe_system( "cat $bench_dir/f${i} > /dev/null" );
}

# Remove them all
vprint "removing $bench_dir directory and all files";
safe_system( "/bin/rm -rf $bench_dir" );

my $end = time;
my $elapsed = $end-$start;

dateprint("Took $elapsed seconds to create, write, read, and remove ${n_files} files of ${n_lines} lines each on $runhost");

dateprint("SQL UPDATE data: => filer_id>$filer_id,filer_ip>$filer_ip,path>$path,elapsed>$elapsed,runhost>$runhost,testid>$testid,netRateBytes>$netRateBytes,load1>$load1,load5>$load5,load15>$load15,freemem>$freemem,swapUsed>$swapUsed,avgRun>$avgRun,avgBlocked>$avgBlocked,avgIdle>$avgIdle");

unless ($dry){
   vprint "inserting row into DB";
   $insert_sql->execute($filer_id, $filer_ip,$dfPath,$elapsed,$runhost,$testid,$netRateBytes,$load1,$load5,$load15,$freemem,$swapUsed,$avgRun,$avgBlocked,$avgIdle)
	or die "Unable to insert new row into DB. ".$insert_sql->errstr;
}

exit 0;

sub safe_system {
  my ($cmd)= @_;
  #vprint "safe_system excuting => $cmd";
  if( 0!= system( $cmd ) ) {
    signal_handler "Failed to execute command:\n$cmd\n\n";
  }
}
