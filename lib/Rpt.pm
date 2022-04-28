$ID = q$Id: Rpt.pm,v 1.8 2020/06/12 17:28:42 midenney Exp $;
# $Revision: 1.8 $
# $Author: midenney $
# Description : Rpt provides methods for sending emails and creating spreadsheets
# $Source: /tool/sysadmin/CVSROOT/makefs/makefs/lib/Rpt.pm,v $

package Rpt;
use strict;
use Excel::Writer::XLSX;
use Data::Dumper;
use File::Basename;
use File::Path;
use File::Copy;
use Sys::Hostname;
use Email::Sender;

use vars qw($VERSION);
use subs qw (determine_format);
$VERSION = '0.1';
##  HISTORY
## 0.1 hacked off from nas scripts lib/Rpt.pm
###################################################################
sub new{
###################################################################
    my ($class_name,$configs) = @_;
    my $self = {
		_email_to => $$configs{email_to},
		_append_email_to => $$configs{append_email_to},
		_email_from => $$configs{email_from},
		_email_subject => $$configs{email_subject},
		_daily_rpt_dir => $$configs{daily_rpt_dir},
		_mailhost => $$configs{mailhost},
		_styleheader => $$configs{styleheader},
    };
    #print Dumper $self;exit;
    $self->{_html_max_field_size}  = '40';
    bless ($self, $class_name) if defined $self;
    $self->{_created} = 1;
    return $self;
}
###################################################################
sub styleheader{
   my $self = shift;
   if (@_) { $self->{_styleheader} = shift }
   return $self->{_styleheader};
}
###################################################################
sub daily_rpt_dir{
   my $self = shift;
   if (@_) { $self->{_daily_rpt_dir} = shift }
   return $self->{_daily_rpt_dir};
}
###################################################################
sub cp_to_daily{
   my $self = shift or return undef;
   my $sfile = shift or return undef;
   my $nfile = shift;#optional new file name
   unless ($self->{_daily_rpt_dir}){
      print "_daily_rpt_dir required\n";
      return undef;
   }
   mkpath ($self->{_daily_rpt_dir});
   return undef unless (-f $sfile);
   if ($nfile){
      #print "saving $sfile to ".$self->{daily_rpt_dir}."/$nfile\n";
      copy ($sfile,$self->daily_rpt_dir."/$nfile") or warn "Copy failed:$!\n";
      chmod 0664,$self->daily_rpt_dir."/$nfile";
      return 1;
   }
   #print "saving $sfile to ".$self->{daily_rpt_dir}."\n";
   copy ($sfile,$self->daily_rpt_dir) or warn "Copy failed:$!\n";
   chmod 0444,$self->daily_rpt_dir."/$sfile";
   return 1;
}
###################################################################
sub email_attachment{
   my $self = shift;
   if (@_) { 
       push @{$self->{_email_attachment}},@_;
   }
   return \@{$self->{_email_attachment}};
}
###################################################################
sub email_from{
   my $self = shift;
   if (@_) { $self->{_email_from} = shift }
   return $self->{_email_from};
}
###################################################################
sub email_body{
   my $self = shift;
   if (@_) { $self->{_email} .= shift } ##append, dont over write!
   return $self->{_email};
}
###################################################################
sub hosts_file{
   my $self = shift;
   if (@_) { $self->{_host_file} = shift }
   return $self->{_hosts_file};
}
###################################################################
sub html_max_field_size{
   my $self = shift;
   if (@_) { $self->{_html_max_field_size} = shift }
   return $self->{_html_max_field_size};
}
###################################################################
sub email_subject{
   my $self = shift;
   if (@_) { $self->{_email_subject} = shift }
   return $self->{_email_subject};
}
###################################################################
sub email_to{
   my $self = shift;
   if (@_) { $self->{_email_to} = shift }
   return $self->{_email_to};
}
###################################################################
sub append_email_to{
   my $self = shift;
   if (@_) { $self->{_email_to} .= shift }
   return $self->{_email_to};
}
###################################################################
sub mailhost{
   my $self = shift;
   if (@_) { $self->{_mailhost} = shift }
   return $self->{_mailhost};
}
###################################################################
sub excel_file{
   my $self = shift;
   if (@_) { $self->{_excel_file} = shift }
   return $self->{_excel_file};
}
##############################################################################
sub pad_array_of_arrays{
##This sub takes 2 parameters: \@table_headers, \@table_body
##Pad array of arrays with "-" to make each line
##equal to the length of the table headers.
##Arrays is meant to be used with MakeEmailBody or
##where ever table data(array of arrays) needs to match up with headers
my @table_headers=@{$_[0]};
my @table_body=@{$_[1]} or die "table_body required";

               my $header_size=scalar @table_headers;
	       foreach my $aref (@table_body){
		       my $line_size=scalar @$aref;
	               my $diff_size=$header_size-$line_size;
		       #say "header_size=>$header_size line_size=>$line_size diff_size => $diff_size";
		       if ( $diff_size != 0 ) {
		           foreach (my $cnt=0;$cnt<$diff_size;$cnt++) {
			       push @$aref,"-";
                           }
	               }
               }
    return(\@table_headers,\@table_body);
}
##############################################################################
sub MakeEmailNote {
    my $self=shift;
    my @notes=@{$_[0]};
    my $emailbody.='<p class=SB_Note>';
    foreach (@notes) {
        $emailbody.="$_<br>\n";
    }
    $emailbody.="</p>\n";

    $self->email_body($emailbody);
    return($emailbody);
}
##############################################################################
sub MakeEmailFooter {
    my $self=shift;
    my @footer=@{$_[0]};
    my $emailbody.="<p class=SB_Footer><br><br>\n";
    foreach (@footer) {
        $emailbody.="$_<br>\n";
    }
    $emailbody.="</p>\n";

    $self->email_body($emailbody);
    return($emailbody);
}
##############################################################################
sub MakeEmailNoteLight {
    my $self=shift;
    my @notes=@{$_[0]};

    my $emailbody.='<p class=SB_Note_Light>';
    foreach (@notes) {
        $emailbody.="$_<br>\n";
    }
    $emailbody.="</p>\n";

    $self->email_body($emailbody);
    return($emailbody);
}
##############################################################################
sub MakeEmailBodyHeaders {
    my $self=shift;
    my $report_title=$_[0];
    use File::Slurper qw(read_text);
    my $emailbody = read_text($self->styleheader);
    $emailbody.='<body leftmargin="0" topmargin="0" marginwidth="0" marginheight="0">';
    if ($report_title){ $emailbody.="$report_title"; }
    $emailbody.="</p></center>\n";
    $self->email_body($emailbody);
    return($emailbody);
}
##############################################################################
sub MakeEmailBody {
    my $self=shift;
    my @report_header=@{$_[0]};
    my @report_body=@{$_[1]} or die "Rpt::MakeEmailBody need to pass \@report_body $!";
    ##NEed to to check of the report_body element lines are equal to the report_header elements size
    ##And pad if not equal
    my ($header_ref,$body_ref)=pad_array_of_arrays(\@report_header,\@report_body);
    $body_ref = undef_to_blank($body_ref); 
    @report_header=@$header_ref;
    @report_body=@$body_ref; 
    #####Below here is the header for the table 
    my $emailbody="<center><TABLE class=SB_Table><THEAD><TR>\n";
    foreach my $header (@report_header) {
         $emailbody.="<TH class=SB_TableHeading>$header</TH>\n";
    }
    ######Below here is the body of the table
    $emailbody.=" </TR></THEAD><TBODY>\n";
    my $row_count=0;
    foreach my $aref (@report_body) {
	$row_count++;
        $emailbody.= "<TR>\n";
        my $field_count=0;
        foreach my $field (@$aref) {
            $field_count++;
            next if ($field_count > scalar(@report_header)); 
            $emailbody.="<TD class=SB_TableRow$row_count nowrap>$field</TD>\n";
        }
        $emailbody.="</TR>\n";
        $row_count=0 if ($row_count == 3);
    }
        $emailbody.="</TBODY></TABLE></center>\n";
 $self->email_body($emailbody);
 return($emailbody);
}
##############################################################################
sub SendEmail {
   my $self=shift;
   #some reason these 2 "use " doesnt work at class level
   use Email::Sender::Simple qw(try_to_sendmail);
   use Email::Sender::Transport::SMTP;
   unless ($self->email_from){
      $self->email_from('root@'.`hostname`);
   }
   my $hostname=hostname;
   my $transport = Email::Sender::Transport::SMTP->new({
     host => $self->mailhost,
   });
   my $email = Email::Simple->create(
     header => [
         To      => $self->email_to,
         From    => $self->email_from,
         Subject => $self->email_subject,
         'Content-Type' => 'text/html',
               ],
         body    => $self->email_body,
   );
   my @toArray = split(',',$self->email_to); 
   my %sHash = (
            transport => $transport,
            to =>  [@toArray] ,
   );
   my $sentE = try_to_sendmail($email,\%sHash);
   return $sentE;
} #end sub SendEmail
###################################################################
sub undef_to_blank{
   ##converts any elements in array of arrays to a space if undef
   my $array = shift;
   foreach my $aref(@$array){
      foreach (@$aref){
         $_ = " " unless ($_);
      }
   }
   return $array;
}
##############################################################################
sub excel_formats{
    my $workbook=shift;
    my $worksheet=shift;
    my $tab=shift;
    my %formats;
    if ($$tab{input_formats}{filter_column}){
       foreach (keys %{$$tab{input_formats}{filter_column}}){
           $worksheet->filter_column($_,$$tab{input_formats}{filter_column}{$_});
       }
    }
    
    ####  Add and define a format  ####
    my $format_head = $workbook->add_format(); # Add a format
    $format_head->set_bold();
    $format_head->set_color('white');
    $format_head->set_bg_color('grey');
    $format_head->set_align('center');
    $formats{format_head}=$format_head;
    my $format_row = $workbook->add_format(); # Add a format
    $format_row->set_color('black');
    $format_row->set_bg_color('silver');
    $format_row->set_align('center');
    $formats{format_row}=$format_row;
    my $default= $workbook->add_format(); # Add a format
    $default->set_color('black');
    $default->set_align('center');
    $formats{default}=$default;
    my $yellow_bg = $workbook->add_format(); #add a format
    $yellow_bg->set_bg_color('yellow');
    $yellow_bg->set_align('center');
    $formats{yellow_bg}=$yellow_bg;
    my $green_bg = $workbook->add_format(); #add a format
    $green_bg->set_bg_color('green');
    $green_bg->set_align('center');
    $formats{green_bg}=$green_bg;
    my $orange_bg = $workbook->add_format(); #add a format
    $workbook->set_custom_color(40, '#FFCC99' ); 
    $orange_bg->set_bg_color(40);
    $orange_bg->set_align('center');
    $formats{orange_bg}=$orange_bg;
    my $light_green_bg= $workbook->add_format(); #add a format
    $light_green_bg->set_bg_color(0x26);
    $light_green_bg->set_align('center');
    $formats{light_green_bg}=$light_green_bg;
    my $integer = $workbook->add_format();
    $integer->set_num_format('#');
    $formats{integer}=$integer;
    my $numeric= $workbook->add_format();
    $integer->set_num_format('#.#');
    $formats{numeric}=$numeric;
    return \%formats;
}
##############################################################################
sub excel_tabs{
    my $self=shift;
    if (@_) {
       die "Excel tab name must be passed\n" unless ($_[0]); 
       my %hoh;
       $hoh{name}=$_[0] or die "tab name must be passed $!\n";
       $hoh{header}=$_[1] or die "header array must be passed $!\n";
       $hoh{rpt}=$_[2] or die "array reference to rpt required$!\n";
       $hoh{FRZ_COL}=$_[3]||'NA';
       $hoh{input_formats}=$_[4];
       push @{$self->{excel_tabs}},{%hoh};
    }
    return \@{$self->{excel_tabs}};
}
##############################################################################
sub write_excel_tabs{
    my $self=shift;
    my $workbook = Excel::Writer::XLSX->new($self->excel_file);
    foreach my $tab (@{$self->excel_tabs}){
      my $worksheet = $workbook->add_worksheet($$tab{name});
      $worksheet->keep_leading_zeros;
      my $max_rows=scalar (@{$$tab{rpt}});
      my $max_cols=scalar (@{$$tab{header}});
      $worksheet->autofilter(0,0,$max_rows,$max_cols-1);
      if ($$tab{FRZ_COL} =~ /^\d+$/){
        $worksheet->freeze_panes(1,$$tab{FRZ_COL});
      }
      my $formats=excel_formats($workbook,$worksheet,$tab);
      my $row=0;my $col=0;
      foreach (@{$$tab{header}}) {
          $worksheet->write($row,$col,$_,$$formats{format_head});
          $col++;
      }#;print "\n";
      $row++;
      foreach my $aref (@{$$tab{rpt}}) {
         $col=0;
         if ($$tab{input_formats}{$row}{all}{hide} ){
             #say "hiding $row";
             $worksheet->set_row($row,undef,undef,1);
        }
        foreach my $field (@$aref) {
            if ($col < 0){
                $worksheet->write($row,$col,$field,$$formats{default}); 
            } else{ 
                my $cel_format=determine_format($row,$col,$formats,$$tab{input_formats},$worksheet);
                $worksheet->write($row,$col,$field,$cel_format); 
                #$worksheet->write_string($row,$col,$field,$cel_format); 
            }#else if ($col < 0)
            $col++;
        }#foreach my $field
        $row++;
      }#foreach my $aref
      my %col_widths=determine_col_widths($$tab{header},$$tab{rpt});
      foreach (keys %col_widths){
         #say "row=>$row col=>$_ width=>".$col_widths{$_};
         if ($$tab{input_formats}{'all'}{$_}{'width'}){
            #say "CHANGE TO=>".$$formats{'all'}{$_}{'width'};
            $col_widths{$_}=$$tab{input_formats}{'all'}{$_}{'width'};
         }
         $worksheet->set_column($_,$_,$col_widths{$_}) if $col_widths{$_};
      }#foreach keys %col_widths
    }#foreach my $tab
}
##############################################################################
sub write_excel_file{
    my $self=shift;
    my $excelfile=$_[0] or die "excel file must be passed $!\n";
    my $header=$_[1] or die "header array must be passed $!\n";
    my $excel_rpt=$_[2] or die "array reference must be passed $!\n";
    my $FRZ_COL=$_[3]||'NA';
    my $input_formats=$_[4];
    ###### Create a new Excel workbook #####
    my $workbook = Spreadsheet::WriteExcel->new($excelfile);
    # Add a worksheet
    my $worksheet = $workbook->add_worksheet();
    $worksheet->keep_leading_zeros;
    my $max_rows=scalar @$excel_rpt;
    my $max_cols=scalar @$header;
    $worksheet->autofilter(0,0,$max_rows,$max_cols);
    #$worksheet->add_write_handler(qr[\w],\&store_string_widths);
   #Freeze first row and first FRZ_COL columns\&store_string_widths);
    if ($FRZ_COL =~ /^\d+$/){
        $worksheet->freeze_panes(1,$FRZ_COL);
    }
    my $formats=excel_formats($workbook);
    
    my $row=0;my $col=0;
    #######Header for main Excel file #######
    foreach (@$header) {
        $worksheet->write($row,$col,$_,$$formats{format_head});
        $col++;
    }
    $row++;
    ######## Create Excel File contents using the array of arrays @excel_rpt
    foreach my $aref (@$excel_rpt) {
        $col=0;
        foreach my $field (@$aref) {
            if ($col < 0){
                $worksheet->write($row,$col,$field,$$formats{default}); 
            } else{ 
                my $cel_format=determine_format($row,$col,$formats,$input_formats);
                $worksheet->write($row,$col,$field,$cel_format); 
            }#else if ($col < 0)
            $col++;
        }
        $row++;
    }
    my %col_widths=determine_col_widths($header,$excel_rpt);
    foreach (keys %col_widths){
       if ($$input_formats{'all'}{$_}{'width'}){
          $col_widths{$_}=$$input_formats{'all'}{$_}{'width'};
       }
       $worksheet->set_column($_,$_,$col_widths{$_}) if $col_widths{$_};
    }
}
##############################################################################
sub determine_format{
   my $row=shift;
   my $col=shift;
   my $formats=shift;
   my $f_inputs=shift;
   my $worksheet=shift;

   if ($$f_inputs{$row}{'all'}{'bg_color'} ){
      if ($$formats{$$f_inputs{$row}{'all'}{'bg_color'}}){
         return $$formats{$$f_inputs{$row}{all}{bg_color}};
      }
   }#end if ($$formats{$row}
   if ($$f_inputs{all}{$col}{type} ){
      if ($$formats{$$f_inputs{all}{$col}{type}}){
      #say "f_inputs col=>$col type=>".$$f_inputs{all}{$col}{type};
         return $$formats{$$f_inputs{all}{$col}{type}};
      }
   }#end if ($$formats{$row}
   return $$formats{default};
}
##############################################################################
sub determine_col_widths{
    my $header=$_[0] or die "WARN header array must be passed $!\n";
    my $excel_rpt=$_[1] or die "WARN array reference must be passed $!\n";
    my %col_widths;
    my $col_cnt=0;
    foreach (@$header){
       $col_widths{$col_cnt}=length($_);
       $col_cnt++;
    }
    foreach my $line (@$excel_rpt){
       $col_cnt=0;
       foreach my $field (@$line){
             $field=' ' unless (defined $field);
             $col_widths{$col_cnt}=length($field) if (length($field) > $col_widths{$col_cnt});
          $col_cnt++;
       }
    }
    foreach my $cols (keys %col_widths){
       $col_widths{$cols}=$col_widths{$cols} * 1.4;
    }
    return %col_widths;
}
1;
