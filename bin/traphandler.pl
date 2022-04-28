#!/tool/pandora64/bin/perl5.24.0 -w
use warnings;
use strict;
my $based;
BEGIN{ 
   $based = "/tools/sysadmin/netapp/makefs/bin";
   chdir($based);
}
use DBI;
use Data::Dumper;
use POSIX;
use Config::IniFiles;
use NetSNMP::TrapReceiver;
use List::MoreUtils qw(uniq);
use File::Path qw(make_path);
use POSIX;
use Time::Local;
use HTML::Strip;
use Try::Tiny;
use lib "/tool/sysadmin/netapp/sdk/9.4/lib/perl/NetApp";
# Production, we're putting the keys in /tool/sysadmin - these are the read only keys
my $cert_file = "/tool/sysadmin/netapp/keys.aBiz.dminCert.pem";
my $key_file = "/tool/sysadmin/netapp/keys.aBiz.dmin.key";
use NaServer;
use NaElement;
chdir($based);
use lib "../lib";
use Rpt;
#########################################################
##  GLOBAL VARS
my $version = "4.3"; #4.3 = fixed $BASED
my $sendEmail = 1;
my $debug = 1;
my $verboseDebug = 1;
my $maxUsers = 10;
my $cfgFile = "$based/../etc/dstools.ini";
my $qtFile = "$based/../etc/qtrees.cfg";
my $config = new Config::IniFiles(-file => $cfgFile);
defined $config or die("Config::IniFiles cannot parse $cfgFile");
my %gloc; #global configs
foreach my $p ($config->Parameters('global')){
   $gloc{$p} = $config->val('global',$p)
}
my %isic; #isi configs
foreach my $p ($config->Parameters('isiauth')){
   $isic{$p} = $config->val('isiauth',$p)
}
my %timeHash;
my $alertTime=1800;
##########################################################
sub logit{
   return unless $verboseDebug;
   return unless (@_);
   #my $logd =  "/tools/sysadmin/netapp/makefs/dev/var/log";
   #my $logd =  "$based/../var/log";
   my $logd =  "/var/log/ds-tools";
   my $logf = "$logd/traphandler.log";
   if ( ! -d $logd) {
        make_path $logd or die "Failed to create path: $logd";
   }
   #my @pary = grep defined, @_; #array with undef elements removed
   my ($lwday,$lmon,$lmday,$lhour,$lmin,$lsec,$lyear,$ltz)= split(/ /,strftime "%a %b %d %H %M %S %Y %Z",localtime());
   my $now_string = "$lmday$lmon$lyear $lhour:$lmin:$lsec";
   open (LOGIT,">>$logf") or die "Unable to open $logf $!";
   #print LOGIT "$now_string : @pary\n";
   print LOGIT "$now_string : @_\n";
   close LOGIT;
   return 1;
} #end sub logit
#########################################################
sub getDatabaseHandle {
   my $dbi = 'dbi:mysql:database=DataServices;host=atlmysql03.aBiz.com;user=ds_user;password=ds_passwd';
   # Make the DB connection
   my $dbh = DBI->connect("$dbi")
             or print "Couldn't make mysql database connection. ".DBI::errstr;
   return $dbh;
}
#########################################################
BEGIN{
   package Isilon;
   use warnings;
   use strict;
   use Data::Dumper;
   use LWP::UserAgent ();
   use HTTP::Request::Common;
   use Cpanel::JSON::XS;
   ###################
   sub new{
      my ($class,$options) = @_;
      my $self = {};
      #perldoc perlstyle recommends private variables(to object) start with _
      foreach (keys %$options){
         $$self{'_'.$_}=$$options{$_};
      }
      bless ($self, $class) if defined $self;
      $self->{_created} = 1;
      return $self;
   }#end new
   ###################
   sub rawGET{
      #http GET with basic authentication. 
      my $self=shift;
      my $epoint=shift;
      my $ep = "https://$$self{_host}:8080/$epoint";
      #print "$ep\n";
      undef $$self{rawContent};undef $$self{rawStatus}; undef $$self{rawCode}; undef $$self{is_success};
      my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 }); #This doesn't work with my perl libs, but does with pandora
      #my $ua = LWP::UserAgent->new();
      $ua->timeout(30);
      $ua->env_proxy;
      my $request = GET $ep;
      $request->authorization_basic($$self{_login},$$self{_passwd});
      #print("GET $ep\n");
      my $response = $ua->request($request);
      $$self{rawContent} = $response->decoded_content; # last GET response
      $$self{rawStatus} = $response->status_line;  # last HTTP code and msg status
      $$self{rawCode} = $response->code;  # last HTTP code
      $$self{is_success} = $response->is_success; 
      #print($$self{rawStatus}."\n");
   } #end sub rawGEt
   ###################
   sub rGET{
      #wrap around rawGET to deal with ?resume and json decode.
      my $self=shift;
      my $epoint=shift;
      my @fields=split /\?/,$epoint;
      my $ebase = $fields[0];
      my $equery = $fields[1] || "";
      my $keyQuery = (split /\//,$ebase)[-1];#keyword used for json key
      #print("ebase=>$ebase equery=>$equery keyQuery=>$keyQuery\n");
      undef $$self{rContent};
      $$self{rContent} = ();
      my $count=0;
      do { #while $equery
         $count++;
         $self->rawGET("$ebase?$equery");
         if (($$self{rawCode} ne 200) and ($$self{rawCode} ne 201)){
             return 1;
         }
         $$self{lastContent} = decode_json($self->rawContent);
         if ($$self{lastContent}{resume}){
             $equery = "resume=$$self{lastContent}{resume}";
         } else {$equery = ""}
         push(@{$$self{rContent}},@{$$self{lastContent}{$keyQuery}});
         #if ($count == 3){$equery="";}
      } while ($equery);
      return 1;
   } #end sub rGET
   ################### object variable access methods
   sub rawContent{ my $self=shift; return $$self{rawContent}; }
   sub rawStatus{ my $self=shift; return $$self{rawStatus}; }
   sub rContent{ my $self=shift; return $$self{rContent}; }
   sub rStatus{ my $self=shift; return $$self{rStatus}; }
   sub rawCode{ my $self=shift; return $$self{rawCode}; }
   sub is_success{ my $self=shift; return $$self{is_success}; }
   sub status_line{ my $self=shift; return $$self{status_line}; }
1; #END Isilon package
}#END BEGIN
sub checkStatus{
   #Return False if non 200 HTTP response code
   my $isi = shift @_;
   logit("success ".$isi->is_success);
   unless ($isi->is_success){
      logit("HTTP Response ".$isi->rawStatus);
      logit("Aborting because of HTTP Response");
      return 1;
   }
   return 0;
}
#########################################################
sub getIsiQuotas{
   my $qD = shift;
   logit("getIsiQuotas() qtree=>$$qD{qtree}");
   unless ($$qD{qtree}) {
      logit("getIsiQuotas() No qtree");
      return 1
   };
   unless (exists $$qD{host}){
      logit('getIsiQuotas() No host key in %$qD');
      return 1
   }
   if ($debug) { logit('getIsiQuotas $qD => '.Dumper(%$qD)); }
   my $ISI=Isilon->new($qD);
   my $ep = "platform/5/quota/quotas?type=directory&path=$$qD{qtree}";
   logit("getIsiQuotas() rGET $ep");
   $ISI->rGET($ep);
   if (checkStatus($ISI)) { return 0; }
   foreach my $Dquota (@{$ISI->rContent}){
      if ( $$Dquota{path} == $$qD{qtree}){
         $$qD{limit}  = sprintf("%.2f", $$Dquota{thresholds}{hard}/1024/1024/1024);
         $$qD{used} = sprintf("%.2f", $$Dquota{usage}{logical}/1024/1024/1024);
         $$qD{files} = $$Dquota{usage}{inodes}||0;
      }
   }
   $ep = "platform/5/quota/quotas?path=$$qD{qtree}&type=user&resolve_names=True";
   logit("getIsiQuotas() rGET $ep");
   $ISI->rGET($ep);
   if (checkStatus($ISI)) { return 0; }
   my %uD;
   foreach my $quota (@{$ISI->rContent}){
      my $name = $$quota{persona}{name}||'NA';
      $name  = (split /\\/, $name)[-1];
      $uD{$name} = {};
      $uD{$name}{used} =  $$quota{usage}{logical}||0;
      if ($$quota{usage}{logical} != 0){
          $uD{$name}{used} = sprintf("%.2f", $$quota{usage}{logical}/1024/1024/1024);
      }
      $uD{$name}{files} = $$quota{usage}{inodes}||0;
      $uD{$name}{limit} = $$quota{thresholds}{hard}/1024/1024/1024||0;
   }
   return $qD,\%uD;
}
#########################################################
sub sendMessage{
   my $qD = shift; #qtree Data and info from DB
   my $uD = shift; #just the user quota data
   my $fs = (split /\//,$$qD{qtree})[-1];
   my ($cc,$numNotify) = customQtree($$qD{site},$fs);
   my $rptU =  $maxUsers; 
   my $starfish = "";
   if (! $$qD{user} and $$qD{projName} and $$qD{sfscan}){
      $$qD{projName} = lc($$qD{projName});
      $$qD{projName} =~ s/\.er$//g;
      #my $surl = "https://seastar.aBiz.com/#/browser/tree?volume=$$qD{site}_$$qD{projName}&path=%2F&selected= $$qD{fs}";
      my $surl = "https://seastar.aBiz.com/#/browser?mode=tree&volume=$$qD{site}_$$qD{projName}";
      $starfish = "<a href=\"$surl\">StarFish disk details for $$qD{projName}.</a><br>\n" ;
      logit("StarFish URL => $surl");
   }
   if ($numNotify){
      $rptU = $numNotify;
   }
   my @sorted = keys %$uD;
   if (@sorted gt 1){
      @sorted = sort { $$uD{$b}{used} <=> $$uD{$a}{used} }  keys %$uD;
   }
   if (scalar(@sorted) < $rptU){
       $rptU = scalar(@sorted);
   }
   my $msg = shift; 
   my $rpto = Rpt->new(\%gloc);
   logit("prepMesssage() site=>$$qD{site} path=>$$qD{qtree} fs=>$fs cc=>$cc numNotify=$numNotify");
   my $percFull = 100;
   #logit("uD=>",Dumper %$uD);
   if ( $$qD{used} != 0 ){
      eval{ $percFull = sprintf("%3.2f", ($$qD{used}/$$qD{limit})*100); };
   }
   my $subject = "$$qD{site} Filesystem  $fs is $percFull% Full!";
   my $message = "$$qD{site} filesystem $fs (/proj/$$qD{qtree}) is $percFull% full.";
   my $msg2 ="$$qD{site} filesystem $$qD{qtree} is size $$qD{limit}"."GB with $$qD{used}"."GB used<br>\n";
   my $cutOff = 1; #Only send email for diectory quota emails if individual user GB used is this amount
   if ($$qD{user}) {
      $cutOff = 0;
      #eval for sprintf cause divide by zero errors
      my $userLimit = 0;
      eval { $userLimit = sprintf("%.0f", $$uD{$$qD{user}}{limit}/1024/1024);};
      my $userPerc = 999;
      eval{ $userPerc =  sprintf("%.0f", ($$uD{$$qD{user}}{used}/$$uD{$$qD{user}}{limit})*100);};
      $subject = "$$qD{user} user quota in $$qD{site}:$$qD{qtree} is $userPerc% Full! \n";
      $message ="$$qD{user} user quota in $$qD{site} filesystem $$qD{qtree} ";
   }
   $message.="\n<br>$starfish\n<br>" if ($starfish);
   logit("Subject=>",$subject);
   logit("Message=>",$message);
   $rpto->mailhost($config->val('global','mailhost'));
   $rpto->email_from($config->val('global','email_from'));
   $rpto->email_subject($subject);
   my @headers=("Username","Space Used (GB)","Files Used","Space Limit (GB)","% of FileSystem Used");
   my $t = ("$message<br>\n$msg2<br>\nThe top $rptU  user(s) of disk space are listed below\n");
   $rpto->MakeEmailBodyHeaders($t);
   #rptU = report users count. 
   #rptU to be 1 less than maxUsers or sizeof @sorted, but don't want to modify maxUsers which is global.
   my @erpt; 
   my @eusers;
   $rptU--;
   logit("Before foreach rptU => $rptU");
   logit(Dumper %$uD);
   foreach my $name (@sorted[0..$rptU]) {
     if (($$uD{$name}{used} > $cutOff) and ($name ne 'root')){
        push @eusers,$name;
     }
     my $pu = 0;
     if ( $$uD{$name}{used} != 0 ){
        $pu = sprintf("%10.2f",($$uD{$name}{used} / $$qD{used})*100)||0;
     }
     if ($$uD{$name}{limit} =~ /^\-0\.00/){
        $$uD{$name}{limit} = '-';
     }
     push @erpt,[$name,$$uD{$name}{used},$$uD{$name}{files},$$uD{$name}{limit},$pu];
   } #END foreach my $name
   if (scalar @eusers eq 0) { 
      logit('No users in @eusers. Exit early because no users to email.');
      return 1;
   }
   $rpto->email_to(join(",",@eusers));
   if ($cc){
      $rpto->append_email_to(",$cc");
   }
   $rpto->MakeEmailBody(\@headers,\@erpt);
   $rpto->email_body("<center>\n");
   $rpto->email_body("<br>To find files you own:<br>\n");
   $rpto->email_body("$$qD{site}_host> find &lt;dir&gt; -type f -user `whoami` -print<br>\n");
   $rpto->email_body("<br>Please do not respond to this email as it was generated from an automated system.<br>\n");
   $rpto->email_body("For questions or issues with this email please file a service central ticket for the engineering ");
   $rpto->email_body("storage group: https:/.aBiz.service-now.com  \n<br>");
   $rpto->email_body("Thank you for your attention,<br>\nData Services<br>\n");
   my @footer = ("traphandler.pl $version");
   $rpto->MakeEmailFooter(\@footer);
   #$sendEmail = 0;
   #$rpto->email_to('michael.denney.aBiz.com');
   if ($sendEmail){
       logit("Sending SMTP for $$qD{qtree} to  : ".$rpto->email_to);
       if ($rpto->SendEmail){
           logit("SMTP success");
           return 1;
       } else {
           logit("SMTP failed");
           return 1;
       }
   } else {
       my $hs = HTML::Strip->new();
       my $clean_text = $hs->parse( $rpto->email_body);
       $hs->eof;
       print "$clean_text\n";
       logit("$clean_text");
   } #END if ($sendEmail){
} #END sendMessage
###########################################################
sub timeCheck{
   #If we've alerted on this vserver:volume combination in the last 
   #$alertTime seconds, just log a message
   #Return 1 if want to send alert, return 0 if not send alert
   my $event = shift;
   my $vserver = shift;
   my $volume = shift;
   my $now = time();
   logit("timeCheck() $vserver $event on volume $volume");
   unless (defined($timeHash{$vserver}{$volume})){
      $timeHash{$vserver}{$volume} = $now;
      return 1;
   }
   if ($timeHash{$vserver}{$volume} > ($now - $alertTime)) {
      logit("Status:too soon, not alarming for event: $vserver $event on volume $volume");
      return 1;
   } 
   $timeHash{$vserver}{$volume} = $now;
   return 1;
}
#########################################################
sub naServerGet ($$$$$) {
	my ($fileServer,$isCmode, $debug,$ontapiVersion, $connType) = @_;
		
	# Default to a read only connection if not defined
	$connType = $connType ? $connType : 'ro';
	
	my $response;
	
	my $s = NaServer->new ($fileServer, 1, $ontapiVersion);
	if ($isCmode) {
		$response = $s->set_style('CERTIFICATE');
		 $response =$s->set_server_cert_verification(0);
		if ($response) {
			print $response->results_reason() . "\n";
			return undef;
		}
	}
	# 7mode uses hosts.equiv auth
	else {
		$s->set_admin_user('root');
		$response = $s->set_style('HOSTS');
	}
	
	if (ref ($response) eq "NaElement" && $response->results_errno != 0)  {
		my $r = $response->results_reason();
		if ($debug) { print "Unable to set authentication style $r for $fileServer\n"; }
		
	}
	else {
		$response = $s->set_transport_type('HTTPS');

		if ($isCmode) {
			if ($connType eq 'ro') {
				$response = $s->set_client_cert_and_key($cert_file, $key_file, undef);
			}
			else {
				print "Unknown connection type in naServerGet() \n";
				return undef;
			}
		}
				
		if (ref ($response) eq "NaElement" && $response->results_errno != 0)  {
			my $r = $response->results_reason();
			if ($debug) { print "Unable to get ontapi connection to $fileServer. Error:$r  \n"; }
			return undef;
		}
	}
	return $s;	
}
#########################################################
sub getCmodeSiteQ{
    ##Get and return the cmode Site, mgmtif  and qtree name
    my (%qD) = %{(shift)};
    logit("getCmodeSiteQ: Vserver UUID:$qD{vserver} Volume:$qD{volume} Tree ID:$qD{treeid}");
    my $dbh = getDatabaseHandle();
    # This will get us the qtree name
     my $qtreeSql =  $dbh->prepare(
                                  "SELECT sfscan,FileSystems.qtree, FileSystems.fileserver,
 vs.name as vsname, c.mgt_if, Sites.id as site, DFMProjects.name as projName, crawl
                                   FROM FileSystems 
				   LEFT JOIN Vols ON FileSystems.vol_id=Vols.indx
				   LEFT JOIN FilerData vs ON Vols.vServer_indx=vs.indx
				   LEFT JOIN FilerData c ON vs.p_id=c.indx
				   LEFT JOIN Sites ON FileSystems.site=Sites.indx
                                   LEFT JOIN DFMProjects on FileSystems.project_id=DFMProjects.indx
				   WHERE Vols.name=?
				   AND FileSystems.id=?
				   AND vs.uuid = ?
				   AND FileSystems.active=1")
		or logit("Unable to prepare qtreeSql: ".DBI::errstr);
	
	$qtreeSql->execute($qD{volume},$qD{treeid},$qD{vserver})
		or logit("Unable to execute qtreeSql: ".DBI::errstr); 
	my $dbData=$qtreeSql->fetchrow_hashref();
	if ($debug) { logit('getCmodeSiteQ() Dumper dbData', Dumper %$dbData); } 
        unless($dbData and %$dbData){
           logit('"getCmodeSiteQ() No %$dbData, exiting early');
           return;
        }
       $qD{site} = $$dbData{site}||'UNKNOWN';
       if ($debug) {logit("dbData => ".Dumper(%$dbData)); }
       if ($$dbData{projName} and $$dbData{sfscan}){
          $qD{projName} = $$dbData{projName};
          $qD{fs} = (split '/', $$dbData{qtree})[-1];
          logit("projName => $$dbData{projName} fs => $qD{fs}");
        }
        my %mH = (%qD, %$dbData); #merged hash
        $mH{qtree} = (split /\//,$mH{qtree})[-1]; #strip the qtree parth to just the qtree name
	logit("getCmodeSiteQ() siteId:$$dbData{site} mgtIf:$$dbData{mgt_if} qtree:$$dbData{qtree}");
        return \%mH;
}
###########################################################
sub isiHandle{
   logit("isiHandle()");
   my @ay = @{$_[0]};
   my %hsh = %{$ay[0]};
   my %tH=%isic; #trap hash, will include the configs from %isic
   $tH{host} = $1 if ( $hsh{'receivedfrom'} =~ /.+\s\[(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\].+/);
   logit("isiHandle() trap received from $tH{host}");
   my $denied = 0;
   my $thresh = 0;
   foreach my $x (@{$ay[1]}) {
       my ($data1,$data2) = split("::",$x->[0]);
       my $v = $x->[1];
       $v =~ s/STRING: \"(.+)\"/$1/;
       chomp($v);
       if ($data2 eq 'enterprises.12124.250.50.10'){
          logit("isiHandle() data2=$data2 v=>$v");
          if ($v =~ m/^(user\s+(\w+\\+)?(\w+)\s+on\s+)?directory\s+(\/.+)/){
              $tH{user} = $3;
              $tH{qtree} = $4;
          }
          if ($v =~ m/^denied$/) {     ##hard quotas
             $denied = 1;
          }
          if ($v =~ m/^exceeded$/) {   ##advisory quotas
             $denied = 1;
          }
       } #end ($data2 eq 'enterprises.12124.250.50.10'){
       if (($data2 eq 'enterprises.12124.250.50.20') and ($v eq 'QUOTA_THRESHOLD_VIOLATION')){
         $thresh = 1;
       }
       if ($data2 eq 'enterprises.12124.1.1.1') {
           $tH{vserver} = $v;
       }
   }#END foreach my $x (@{$ay[1]}) {
   logit("isiHandle() - vserver->$tH{vserver} host->$tH{host} denied-=>$denied dir=> $tH{qtree} thresh=>$thresh user=>$tH{user}");
   unless ($tH{host} and $denied and $tH{qtree} and $thresh){
       logit("END isiHandle() - NOT proceeding because missing variable");
       return 1;
   }
   my $event = "Quota hard limit";
   unless ($tH{user}){
      unless (timeCheck($event,$tH{vserver},$tH{qtree})){
          return 1;
      }
   }
   unless (%isic){
       logit("Missing %isic");
       return 2;
   }
   my ($qD,$uD) = getIsiQuotas(\%tH);
   unless ($uD and %$uD){
       logit("Error: Found no user quotas from the Isilon, aborting");
       return 2;
   }
   unless ($qD and %$qD){
       logit("Error: Found no quota directory info from the Isilon, aborting");
       return 2;
   }
   my $dbh = getDatabaseHandle();
   my $scmd = << 'END_CMD';
   Select Sites.id as site, DFMProjects.name as projName
	FROM FileSystems
	LEFT JOIN Sites on FileSystems.site=Sites.indx
        LEFT JOIN DFMProjects on FileSystems.project_id=DFMProjects.indx
	WHERE FileSystems.qtree = ?  AND
	FileSystems.fileserver =  ?
END_CMD
	
   my $sql = $dbh->prepare($scmd) or do {
       logit("Couldn't prepare Sql statement: " . DBI::errstr);
       return 0;
   };
   $sql->execute($tH{qtree},$tH{vserver})
		or logit("Unable to execute qtreeSql: ".DBI::errstr);
   my $dbData=$sql->fetchrow_hashref();
   $$qD{site} = $$dbData{site}||'UNKNOWN';
   if ($debug) { logit("dbData => ".Dumper(%$dbData)); }
   if ($$dbData{projName} and $$dbData{sfscan}){
      $$qD{projName} = $$dbData{projName};
      $$qD{projName} =~ s/\.er$//g;
      $$qD{projName} =~ lc($$qD{projName});
      $$qD{fs} = (split '/', $tH{qtree})[-1];
      logit("projName => $$dbData{projName} fs => $$qD{fs}");
   }
   if ( $$qD{user}) {
      my %uH;
      $uH{$$qD{user}} = $$uD{$$qD{user}};
      %$uD = %uH;
   }
   sendMessage($qD,$uD);
   logit("END isiHandle() - Success");
   return 1;
}
###########################################################
sub getCmodeQtree{
   #get qtree quota stats
   #quota tree type stats gets added to %$qD
   #quota user type stats gets added to %uD
   my $qD  = shift;  #quota Data
   my %uD; #user Data
   unless ($$qD{mgt_if}){
       logit('getCmodeQtree{} Error: no management interface found in %$qD , exit early');
       return;
   }
   logit("getCmodeQtree: mgt_if:$$qD{mgt_if} qtreePath:$$qD{qtree}");
   #logit('%$qD ', Dumper %$qD);
   # get a connection to the filer, assume cmode for now
   my $sC=naServerGet($$qD{mgt_if},'1','0','1.30','ro'); #$sC = server conection
   if (!(defined($sC))) {
      logit("getCmodeQtree() :ERROR:Quota event: Unable to get NaServer connection to file server");
      return 2;
   }

   my $quotaCmd = NaElement->new('quota-report-iter');
   my $quotaMax = NaElement->new('max-records');
   $quotaMax->set_content('250');
   $quotaCmd->child_add($quotaMax);

   my $quotaQuery = NaElement->new('query');
   my $quotaEntry = NaElement->new('quota');

    #if ($$qD{user}) {
        #my $quotaUsers = NaElement->new('quota-users');
        #my $quotaUser = NaElement->new('quota-user');
        #$quotaUser->child_add_string('quota-user-id',$$qD{user});
        #$quotaUser->child_add_string('quota-user-type','uid');
        #$quotaEntry->child_add($quotaUsers);
        #$quotaUsers->child_add($quotaUser);
    #}

   $quotaEntry->child_add_string('volume',$$qD{volume});
   $quotaEntry->child_add_string('vserver',$$qD{vsname});
   $quotaEntry->child_add_string('tree',$$qD{qtree});

   $quotaQuery->child_add($quotaEntry);
   $quotaCmd->child_add($quotaQuery);

   my $tagText="";
   my $nextQuotaElement = NaElement->new("tag");
   $quotaCmd->child_add($nextQuotaElement);
   while (defined($tagText)) {
        $nextQuotaElement->set_content($tagText);
        my $quotaData = $sC->invoke_elem($quotaCmd);
        if ($quotaData->results_status() eq 'failed') {
            logit("getCmodeQtree(): API call to file server failed. Reason:".$quotaData->results_reason());
            return 2;
        }
        $tagText=$quotaData->child_get_string('next-tag');
        logit("getCmodeQtree():Records returned from API call:".$quotaData->child_get_string('num-records'));
        if (defined($quotaData->child_get('attributes-list'))) {
           foreach my $qE ($quotaData->child_get('attributes-list')->children_get()) {
              #logit("qE ",Dumper $qE);
              my $type = $qE->child_get_string('quota-type');
              my $target = $qE->child_get_string('quota-target');
              if ($qE->child_get_string('quota-target') eq '*'){
                 next;
              }
              my $name;
              if ($type eq 'user'){
                 my $users = $qE->child_get('quota-users');
                 $name = $users->child_get('quota-user')->child_get_string('quota-user-name');
                 $uD{$name} = {}; 
                 $uD{$name}{used}  =  sprintf("%.2f", $qE->child_get_string('disk-used') /1024/1024)||0 ;
                 $uD{$name}{files}  = $qE->child_get_string('files-used') ;
                 $uD{$name}{limit}  = sprintf("%.2f", $qE->child_get_string('disk-limit') /1024/1024)||'-';
                 if ($uD{$name}{used} eq '-') { 
                    $uD{$name}{used} = 0 ; 
                 }
                 next;
              }
              $$qD{limit} =  sprintf("%.2f", $qE->child_get_string('disk-limit') /1024/1024)||0;
              $$qD{used} = sprintf("%.2f",$qE->child_get_string('disk-used') /1024/1024)||'-';
              $$qD{files} = $qE->child_get_string('files-used');
           }
        }# if (defined($quotaData->child_get('attributes-list'))) {
   }# while (defined($tagText))
   return ($qD,\%uD); 
}
###########################################################
sub cmodeHandle {
   #Handle a cmode event
   logit("cmodeHandle()");
   my @ay = @{$_[0]};
   my %hsh = %{$ay[0]};
   my $host = "";
   $host = $1 if ( $hsh{'receivedfrom'} =~ /.+\s\[(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\].+/);
   #$host = '10.180.128.220' if ($host == '127.0.0.1');
   logit("cmodeHandle() trap received from $host");
   my %tH;
   foreach my $x (@{$ay[1]}) {
       my ($data1,$data2) = split("::",$x->[0]);
       my $v = $x->[1];
       if ($data2 eq 'enterprises.789.1.1.12.0'){
          logit("cmodeHandle() data2=$data2 v=>$v");
 if ( $v =~ m/STRING:\s+"Quota Event:.+status=(\w+),.+type=(\w+),.+volume=(\w+)\@\w+:(\S+),.+limit_value=(\d+)(,\s+user=(\d+))*,\s+treeid=(\d+)/){
             $tH{status}      = $1;
             $tH{type}        = $2;
             $tH{volume}      = $3;
             $tH{vserver}     = $4;
             $tH{limit_value} = $5;
             $tH{user}        = $7;
             $tH{treeid}      = $8;
             if ($debug) { logit("DUMPER %tH- ".Dumper(%tH)); }
          }
       } #end ($data2 eq 'enterprises.789.1.1.12.'){
   } # foreach my $x (@{$ay[1]}) {
   unless (%tH){
      logit("Exiting because no keys found in %tH ,probably not a Quota Event of type hard.");
      return 2;
   }
   #Don't alert people on normal events, ex: when a disk returns to a non-full state
   if ($tH{status} eq 'normal'){
      logit("Status:normal, not alarming for event: Quota Event");
      return 2;
   } 
   # Automatically handle hard quota events, we won't want to throttle these as the file server will only alert every hour anyway
   if (($tH{type} eq 'hard') or (timeCheck($tH{event},$tH{vserver},$tH{volume}))) {
      my $qD = getCmodeSiteQ(\%tH);
      my $uD;
      ($qD,$uD) = getCmodeQtree($qD);
      if ( $$qD{user}) {
          $$qD{user} = getpwuid($$qD{user});
          my %uH;
          $uH{$$qD{user}} = $$uD{$$qD{user}};
          %$uD = %uH;
      }

      sendMessage($qD,$uD);
      logit("END cmodeHandle() - Success");
   }
   return 1;
}#end cmodeHandle()
###########################################################
sub sendAdminEmail{
  #For when something goes wrong.
   my $rO = Rpt->new(\%gloc);
   $rO->mailhost($config->val('global','mailhost'));
   $rO->email_from($config->val('global','email_from'));
   $rO->email_subject("Issue with traphandler.pl");
   my $e = $@;
   $rO->email_body("Something went wrong->$e");
   logit("Something went wrong->$e");
   logit("Sending SMTP for script issue to  : ".$rO->email_to);
   if ($rO->SendEmail){
      logit("SMTP success");
      return 1;
   } else {
      logit("SMTP failed");
      return 1;
   }
}
###########################################################
sub customQtree{
   #add custom email addresses  tdo an alert
   my $site = shift;
   my $fs = shift;
   unless (-f $qtFile){
      logit("customQtree()->$qtFile not found");
      return;
   }
   unless ($site and $fs){
      logit('customQtree() $site or $fs missing');
      return; 
   }
   logit("customQtree{} $site $fs");
   open(CFG,$qtFile) or die $!;
   while(<CFG>){
     chomp;
     s/#.*//;
     next unless /\S+/;
     s/ //g;
     my ($Fsite,$trees,$cc,$numnotify)=split(/:/);
     $Fsite=~tr/a-z/A-Z/;
     unless ($site eq $Fsite){
        next;
     }
     foreach my $tree (split(/,/,$trees)){
       if ($fs eq $tree){
          return $cc,$numnotify;
       }
     }
  } #while CFG
}
###########################################################
  sub my_receiver {      
     eval{
        logit("traphandler my_receiver() called");
        chdir($based);
        foreach my $x (@{$_[1]}) { 
           my ($data1,$data2) = split("::",$x->[0]);
           logit("my_receiver() data2=>$data2");
           if ($data2 eq "enterprises.12124.250.50.10") { 
              return isiHandle(\@_);
           }
	   if ($data2 eq "enterprises.789.1.1.12.0"){
              return cmodeHandle(\@_);
           }
        }
        logit("END my_receiver() - Not a recognized Cmode or Isilon event");
        return 1;
        1;
     } or do { ##eval or
        sendAdminEmail;
     } #end eval
  } #end my_receiver


  NetSNMP::TrapReceiver::register("all", \&my_receiver) || 
    warn "failed to register our perl trap handler\n";

  print STDERR "\nLoaded the traphandler.pl quota snmptrapd handler\n";
  logit("Loaded the traphandler.pl quota snmptrapd handler");
