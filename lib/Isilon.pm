#
# Functions for dealing with Isilon file servers from ds-tools
#

# $Revision: 1.16 $
# $Author: rdp $
# $Source: /tool/sysadmin/CVSROOT/makefs/makefs/lib/Isilon.pm,v $
#
#

sub getIsiConn {
    my ($mgt_if,$user,$pass,$port,$debug) = @_;
    
    # Not sure this is the right place for this yet
    my @ISILON_SERVICES;
    $ISILON_SERVICES[0] = 'namespace';
    $ISILON_SERVICES[1] = 'session';
    $ISILON_SERVICES[2] = 'platform';

    $ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
    my $client = REST::Client->new();
    $client->getUseragent()->ssl_opts( SSL_verify_mode => 0 ); 
    my $json = JSON::PP->new->pretty;

    my $hostString = "https://".$mgt_if.":".$port;
    $client->setHost($hostString);

    my %login = ('username'=>$user, 'password'=>$pass, 'services'=>\@ISILON_SERVICES);
    my $login_json = $json->encode(\%login);

    $client->POST('session/1/session',$login_json,{'Content-Type'=>'application/json'});
    # FIXME - need to check this worked!
    my $rawcookies = $client->responseHeader('Set-Cookie');
        
    if (defined($rawcookies)) {
        my @cookies = split(';',$rawcookies);
        my $sessioncookie = $cookies[0];
        my $rawisicsrf = $cookies[4];
        my @isicsrfarray = split('=',$rawisicsrf);
        my $isicsrf = $isicsrfarray[2];

        $client->addHeader('X-CSRF-Token', $isicsrf);
        $client->addHeader('referer', $hostString);

        return ($client,$sessioncookie);
    }
    else {
        print "ERROR:".$client->{'_res'}->{'_content'}."\n";
        #return (undef,undef);
        exit(1);
    }
}
# END

sub disconnectIsiConn {
    my ($client,$sessioncookie) = @_;
    $client->DELETE('session/1/session',{'Cookie'=>$sessioncookie});
    return 1;
}

# this returns all of the Isilon export policies, by filer server ID
sub isiExportPolicyGet  {
	my %exportDbData;
	
	my $dbh=get_database_handle();	
		
	my $loadExportPolicySql = $dbh->prepare("SELECT ExportPolicies.indx, ExportPolicies.`policy-id`, ExportPolicies.`policy-name`, ExportPolicies.vserver, ExportPolicies.default, ExportPolicies.active
                                                FROM ExportPolicies 
                                                LEFT JOIN FilerData ON ExportPolicies.vserver=FilerData.indx
                                                WHERE FilerData.type='isilon'")
		or die "Unable to prepare loadExportPolicySql in isiExportPolicyGet ".DBI::errstr."\n";
		
	# Build a hash of the policies
	$loadExportPolicySql->execute()
		or die "Unable to execute loadExportPolicySql  in isiExportPolicyGet ".DBI::errstr."\n";
		
	while (my $row = $loadExportPolicySql->fetchrow_hashref()) {
		$exportDbData{$$row{'vserver'}}{$$row{'policy-id'}}{'indx'} = $$row{'indx'};
		$exportDbData{$$row{'vserver'}}{$$row{'policy-id'}}{'desc'} = $$row{'policy-name'};
        $exportDbData{$$row{'vserver'}}{$$row{'policy-id'}}{'default'} = $$row{'default'};
        $exportDbData{$$row{'vserver'}}{$$row{'policy-id'}}{'active'} = $$row{'active'};
	}
	
	return (\%exportDbData);
}

# This returns the export policy used for a particular file system. First we look for an FS specific export, failing that we return the default /ifs export
sub isiFileSystemExportGet {
    my ($volId,$fsId) = @_;
    
    my $dbh=get_database_handle();	
    
    my $exportSql = "SELECT ExportPolicies.`policy-id` as pid,
                        ExportPolicies.indx as pindx,
                        ExportPolicies.`policy-name` as pname
                    FROM ExportPolicies
                        LEFT JOIN IsiExportRules ON IsiExportRules.`policy-id` = ExportPolicies.indx
                    WHERE IsiExportRules.volid=?
                    AND IsiExportRules.active=1";
                    
    my $fsExportSql = $exportSql." AND fsid=?";
    
    my $defautExportSql = $exportSql." AND fsid IS NULL";
        
    my $fsExportStmt = $dbh->prepare($fsExportSql)
        or die "Unable to prepare fsExportSql: ".DBI::errstr."\n";
        
    $fsExportStmt->execute($volId,$fsId)
        or die "Unable to execute fsExportSql: ".DBI::errstr."\n";
        
    if ($fsExportStmt->rows() > 0 ) {
        $row = $fsExportStmt->fetchrow_hashref();
        return ($row);
    }
        
    my $defaultExportStmt = $dbh->prepare($defautExportSql)
        or die "Unable to prepare defaultExportStmt: ".DBI::errstr."\n";

    $defaultExportStmt->execute($volId)
        or die "Unable to execute defaultExportStmt: ".DBI::errstr."\n";
        
    if ($defaultExportStmt->rows() > 0 ) {
        $row = $defaultExportStmt->fetchrow_hashref();
        return ($row);
    }

    return undef;

}

sub isiQuotaModify {
    my ($isiClient,$isiSessioncookie,$type,$quotaId,$newSize,$advisorySize,$debug) = @_;

    my $dirQuotaBody;
    $dirQuotaBody->{'thresholds'}->{'hard'} = $newSize*(1024*1024*1024);            
    $dirQuotaBody->{'thresholds'}->{'advisory'} = $advisorySize*(1024*1024*1024);
    my $jsonDirQuotaBody = encode_json($dirQuotaBody);
    
    $isiClient->PUT("/platform/1/quota/quotas/".$quotaId,$jsonDirQuotaBody,{'Cookie'=>$isiSessioncookie});
    my $quotaDefUserResult = $isiClient->responseContent();
    if ($quotaDefUserResult eq '') {
        return 1;
    }
    else {
        print "ERROR:\n";
        print Dumper($quotaDefUserResult);
        return 0;
    }
}

sub getIsiBackupDirSize {
    my ($path) = @_;
    my %returnHash;
    my $dbh=get_database_handle();	
    #$dbh->trace(2);
    $path.="/%";
    
    my $pathSql = $dbh->prepare("SELECT substring(qtree,1,locate(substring_index(qtree,'/',-1),qtree)-1)as fspath, 
                                        SUM(FileSystems.size)/(1024*1024) as totalGB
                                    FROM FileSystems
                                    WHERE isiDType='N' 
                                        AND qtree LIKE '$path'
                                    GROUP BY fspath ")
        or die "Unable to prepare pathSql in  getIsiBackupDirCounts".DBI::errstr."\n";
    
    $pathSql->execute()
		or die "Unable to execute pathSql  in getIsiBackupDirCounts ".DBI::errstr."\n";    
    
    while (my $row = $pathSql->fetchrow_hashref()) {
		$returnHash{$$row{'fspath'}} = ($$row{'totalGB'});
	}
	
	return (\%returnHash);
}

sub getAccessZonesForCluster {
    my ($clusterName) = @_;
    my %returnHash;
    my $dbh=get_database_handle();

    my $isiZoneLoadPerCluster = $dbh->prepare("SELECT a.indx as indx,a.name as zonename, IFNULL(a.comments,'') as comment FROM FilerData a LEFT JOIN FilerData c ON a.p_id = c.indx WHERE a.model='isizone' AND a.active=1 and c.active=1 AND c.name=?")
        or die "Unable to prepare isiZoneLoadPerCluster SQL in getAccessZonesForCluster: ".DBI::errstr."\n";

    $isiZoneLoadPerCluster->execute($clusterName)
        or die "Unable to execute isiZoneLoadPerCluster SQL in getAccessZonesForCluster: ".DBI::errstr."\n";

    while (my $zoneRow = $isiZoneLoadPerCluster->fetchrow_hashref()) {
		$returnHash{$$zoneRow{'zonename'}}{'indx'} = $$zoneRow{'indx'};
		$returnHash{$$zoneRow{'zonename'}}{'comment'} = $$zoneRow{'comment'};
		$returnHash{$$zoneRow{'zonename'}}{'name'} = $$zoneRow{'zonename'};
    }
    return (\%returnHash);
}

1;