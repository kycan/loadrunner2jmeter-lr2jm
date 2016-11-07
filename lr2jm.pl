#!c:\perl\bin\perl.exe
#
# Changelog:
#	0.4
#		Added lr start and end transaction support
#		Added web custom request support
#		Added web add header support
#		Added web reg save paramater regular expressiono variation support
#		Various fixes and enchancements
#   0.3.1
#       Bug fixes
#       Added support for web_custom_request()
#       Added XML::Tidy for better formatting of output
#	0.3.0
#		Added basic support for parameter data files
#		Added basic support for web_reg_save_param
#	0.2.1 
#		Added support for web_submit_data()
#		Changed location of saved script to be in LR script folder
#	0.1.2 Fixed some typos with spaces in xml attributes
#	0.1.1 Initial release
#
#




use strict;
use XML::DOM;
use XML::Tidy;
use File::Util;

my $PATHSEP=File::Util->SL;
my $TRUE=1;
my $FALSE=0;

my @webrequests = ();
my $lrscript = &readArguments(@ARGV);

my %tables;
my %paramsubs;
my %dynamicParams;
my @curHTTPHeaders;

&getParametersFromLR();

my @actions = &getActionFilesFromLR();
&parseActionFiles();
&writeJM();

exit;

sub readArguments
{
	my @ARGS = @_;
	
	my $usage = <<END;
lr2jm.pl

USAGE:

lr2jm.pl <LoadRunner Script Path>
END

	die $usage if ($#ARGS < 0);
	my $script = $ARGS[0];
	die "$script: $!\r\n$usage" unless (-d $script);
	return $script;
}
sub getParametersFromLR
{
	my $f = File::Util->new();
	my $prm = $lrscript.$PATHSEP.$f->strip_path($lrscript).".prm";
	return unless (-f $prm);
	
	open (PRM, "<$prm") or die "Unable to open $prm\r\n$!\r\n$^E";

	local $/ = '[';
	my @params;
	
	while (<PRM>) {
		push (@params, $_) unless ($. == 1);
	}
	close PRM;
		
	foreach my $param (@params) {
		$_ = $param;
		my ($type) = m/Type="(.*)"/;
		my ($paramname) = m/ParamName="(.*)"/;
		my ($delimiter) = m/Delimiter="(.*)"/;
		my ($columnname) = m/ColumnName="(.*)"/;
		my ($table) = m/Table="(.*)"/;
		
		next unless ($type eq "Table");
		
		if (not exists($tables{$table})){
			$tables{$table}=$table;
			my $l2j_tablefile = $table;
			$l2j_tablefile =~ s/\./_/g;
			$l2j_tablefile = $l2j_tablefile.".csv";
			
			my @tabledata;
			push (@tabledata,$l2j_tablefile);
			
			local $/="\n";
			my @columns;
			
			my $tablefile = $lrscript.$PATHSEP.$table;
			$l2j_tablefile = $lrscript.$PATHSEP.$l2j_tablefile;
			
			open (PARAMFILE, "<$tablefile") or die "Trying to configure parameter $paramname:\r\n\tunable to open parameter data file $tablefile: $!\r\n$^E";
			open (L2JFILE,">$l2j_tablefile") or die "unable to open parameter data file $l2j_tablefile: $!\r\n$^E";
			
			while (<PARAMFILE>) {
				print L2JFILE unless ($.==1 || m/^\s*$/);
				@columns = split /,/ if $.==1;
			}
			close L2JFILE;
			close PARAMFILE;

			chomp(@columns);
			
			push (@tabledata,@columns);
			$tables{$table}=\@tabledata;
		}
		
		if ($columnname =~ m/^Col (\d+)/){
			my $col = $1;
			my $colname = ${$tables{$table}}[$col];
			$paramsubs{$paramname}=$colname;
		} else {
			$paramsubs{$paramname}=$columnname;
		}
		
	}
	
}
sub getActionFilesFromLR
{
	my $f = File::Util->new();
	my $usr = $lrscript.$PATHSEP.$f->strip_path($lrscript).".usr";
	my @actions;
	
	open (USR, "<$usr") or die "Unable to open $usr\r\n$!\r\n$^E";
	while (<USR>) {
		my $usrline = $_;
		$usrline =~ s/\s*$//;
		if ($usrline =~ m/\.c$/){
			$usrline =~ s/^.*?=//;
			push(@actions,$usrline);
		}
	}
	close USR;

	return @actions;
}

sub parseActionFiles
{	
	foreach my $action (@actions) {	
	    open (ACTION, "<${lrscript}".File::Util->SL.$action) or die "couldn't open action file: $!\r\n$^E";
	    my @actioncontents = <ACTION>;
	    close ACTION;
	    
	    for (my $i=0;$i<=$#actioncontents;$i++) {
	        my $line = $actioncontents[$i];
	        $actioncontents[$i] =~ s/^\s+//;
	        $actioncontents[$i] =~ s/\s+$//;
	        $actioncontents[$i] =~ s/^"//;
	        $actioncontents[$i] =~ s/"$//;
			
	    }
	    
		
		my $actioncontentsSTR = join("", @actioncontents);
		$actioncontentsSTR =~ /([^{]*){(.*)/;
	    my @functions = split(/\);/,$2);
	    
	    foreach (@functions) {
			
			#print "function = $_\n";
			
	        my ($lrfunc,$lrargs) = m/([^\(]*)\((.*)/;
			
			
			#my @result = extract_bracketed($1)
			
			
			
	        if (defined($lrfunc)){
			
				
				#print "function = $lrfunc\n";
	            $_ = $lrfunc;
	            &web_url($lrargs) if m/web_url/;
	            &web_submit_data($lrargs) if m/web_submit_data/;
	            &web_custom_request($lrargs) if m/web_custom_request/;
	            &web_reg_save_param($lrargs) if m/web_reg_save_param/; #and not(m/web_reg_save_param_regexp/);
				&lr_start_transaction($lrargs) if m/lr_start_transaction/; 
				&lr_end_transaction($lrargs) if m/lr_end_transaction/; 
				&web_add_header($lrargs) if m/web_add_header/; 
			}
	    }
	}
} # parseActionFile


sub lr_start_transaction
{
	my $arguments = shift;
    my @arguments = split(/,/,$arguments);
    my $transactionName = $arguments[0];
    $transactionName =~ s/"//g;
	
	my %requestdata;
	$requestdata{function} = "lr_start_transaction";
	$requestdata{transactionname} = $transactionName;
	
	my $hashref = \%requestdata;
    push(@webrequests,$hashref);
}

sub lr_end_transaction
{
	my $arguments = shift;
    my @arguments = split(/,/,$arguments);
    my $transactionName = $arguments[0];
    $transactionName =~ s/"//g;
	
	my %requestdata;
	$requestdata{function} = "lr_end_transaction";
	$requestdata{transactionname} = $transactionName;
	
	my $hashref = \%requestdata;
    push(@webrequests,$hashref);
}

sub web_url
{
    my $arguments = shift;
    my @arguments = split(/,/,$arguments);
    my $stepname = $arguments[0];
    $stepname =~ s/"//g;
    
    my %requestdata;
    $requestdata{stepname} = $stepname;
    $requestdata{method}='GET';
    
    foreach my $argument (@arguments){
        $argument =~ s/"//g;
        if ($argument =~ m/^URL=https*:\/\/(.*?)(\/.*)/) {
            $requestdata{domain}= $1;
            $requestdata{path}=$2;
        }
        if ($argument =~ m/^Mode=(.*)/) {
            if ($1 =~ /HTML/) {
                $requestdata{image_parser}='true';    
            } else {
                $requestdata{image_parser}='false';
            }
        }
    }

	my %params = %dynamicParams;
	$requestdata{params}=\%params;
	foreach my $key (keys %dynamicParams){
		delete $dynamicParams{$key};
	}
	
	
	my @headers = @curHTTPHeaders;
	$requestdata{headers}=\@headers;
	undef @curHTTPHeaders;
	
    my $hashref = \%requestdata;
    push(@webrequests,$hashref);
}

sub web_submit_data
{
    my $arguments = shift;
    my @arguments = split(/,/,$arguments);
    my $stepname = shift(@arguments);
    $stepname =~ s/"//g;
    
    my %requestdata;
    my @itemdata;
    $requestdata{stepname} = $stepname;
    
    foreach my $argument (@arguments){
        $argument =~ s/^\s*"*//g;
        $argument =~ s/"*\s*$//g;
        
        if ($argument =~ m/^Action=https*:\/\/(.*?)(\/.*)/) {
            $requestdata{domain}= $1;
            $requestdata{path}=$2;
        }
        if ($argument =~ m/^Mode=(.*)/) {
            if ($1 =~ /HTML/) {
                $requestdata{image_parser}='true';    
            } else {
                $requestdata{image_parser}='false';
            }
        }
        if ($argument =~ m/^Method=(.*)/) {
            $requestdata{method}=$1;    
        }
        # if ($argument =~ m/^Name=(.*)/) {
        	# push(@itemdata,$1);
        # }
        # if ($argument =~ m/^Value=(.*)/) {
        	# push(@itemdata,$1);
        # }
        # if (($argument =~ m/LAST/) & ($#itemdata > 0)) {
        	# $requestdata{itemdata} = \@itemdata;
        # }
    }
	
	
	my @itemDataNameSet = ( $arguments =~ m/Name=((?:[^"\\]|\\.)*)"/g );
	my @itemValueNameSet = ( $arguments =~ m/Value=((?:[^"\\]|\\.)*)"/g  );
	
	my $i = 0;
	foreach my $curName (@itemDataNameSet) {

		push(@itemdata,$curName);
		push(@itemdata,$itemValueNameSet[$i]);
		$i = $i + 1;
	}
	if ($#itemdata > 0) {

        $requestdata{itemdata} = \@itemdata;
    }
	
	my %params = %dynamicParams;
	$requestdata{params}=\%params;
	foreach my $key (keys %dynamicParams){
		delete $dynamicParams{$key};
	}
	
	my @headers = @curHTTPHeaders;
	$requestdata{headers}=[@headers];
	undef @curHTTPHeaders;
		
	
    my $hashref = \%requestdata;
    push(@webrequests,$hashref);
}

sub web_custom_request
{
    my $arguments = shift;

	
    my @arguments = split(/,/,$arguments);
    my $stepname = shift(@arguments);
    $stepname =~ s/"//g;
    
    my %requestdata;
    my @itemdata;
    $requestdata{stepname} = $stepname;
	
	$arguments =~ m/Body=((?:[^"\\]|\\.)*)"/;
	my $body = $1;
	$body =~ s/\\(["\\])/"qq|\\$1|"/gee; #remove escape character forward slash
    $requestdata{bodydata} = $body;
	
    foreach my $argument (@arguments){
        $argument =~ s/^\s*"*//g;
		
        
        $argument =~ s/"*\s*$//g;

        
        if ($argument =~ m/^URL=https*:\/\/(.*?)(\/.*)/) {
            $requestdata{domain}= $1;
            $requestdata{path}=$2;
        }
        if ($argument =~ m/^Mode=(.*)/) {
            if ($1 =~ /HTML/) {
                $requestdata{image_parser}='true';    
            } else {
                $requestdata{image_parser}='false';
            }
        }
        if ($argument =~ m/^Method=(.*)/) {
            $requestdata{method}=$1;    
        }
		
		if ($argument =~ m/^EncType=(.*)/) {
			print "EncType= $1\n";
			my @header = ("Content-Type", $1);
		
            push (@curHTTPHeaders, \@header);
        }

    }

	my %params = %dynamicParams;
	$requestdata{params}=\%params;
	foreach my $key (keys %dynamicParams){
		delete $dynamicParams{$key};
	}
	
	my @headers = @curHTTPHeaders;
	$requestdata{headers}=\@headers;
	undef @curHTTPHeaders;

	
    my $hashref = \%requestdata;
    push(@webrequests,$hashref);
}

sub web_reg_save_param
{
	
	my $arguments = shift;
    my @arguments = split(/,/,$arguments);
	shift(@arguments) =~ /ParamName=(.*)/;
    my $paramname=$1;
	
    $paramname=~s/"//g; 
    
	
	$arguments =~ m/RegExp=((?:[^"\\]|\\.)*)"/;
	my $regex = $1;
	
	
	
	if (defined $regex) {
		

		$regex =~ s/\\(["\\])/"qq|\\$1|"/gee; #remove escape character forward slash
		
		$dynamicParams{$paramname}=$regex;

	}
	else {
	
		my ($LB,$RB);
		
		$arguments =~ m/LB(\/IC)?=((?:[^"\\]|\\.)*)"/;
		$LB=$2;
		
		$arguments =~ m/RB(\/IC)?=((?:[^"\\]|\\.)*)"/;
		$RB=$2;
		
		$LB =~ s/\\(["\\])/"qq|\\$1|"/gee; #remove escape character forward slash
		$RB =~ s/\\(["\\])/"qq|\\$1|"/gee; #remove escape character forward slash
		
		# foreach my $argument (@arguments){
			# $argument =~ s/^\s*"*//g;
			# $argument =~ s/"*\s*$//g;
			
			
			
			# if ($argument =~ m/^LB(\/IC)?=(.*)/) {
				# $LB=$2;
			# }
			# if ($argument =~ m/^RB(\/IC)?=(.*)/) {
				# $RB=$2;
			# }
		# }
		
		$dynamicParams{$paramname}=$LB."(.*?)".$RB;
		
	}
	$paramsubs{$paramname}=$paramname; 
	
}


sub web_add_header
{
	
	my $arguments = shift;
    my @arguments = split(/,/,$arguments);
    
    
    foreach my $argument (@arguments){
    	$argument =~ s/^\s*"*//g;
        $argument =~ s/"*\s*$//g;
    }
	
	push (@curHTTPHeaders, \@arguments);
	
}


sub writeJM
{
	#my $jmx = $lrscript.$PATHSEP.$lrscript.".jmx";
	my $f = File::Util->new();
	my $jmx = $lrscript.$PATHSEP.$f->strip_path($lrscript).".jmx";
    open (JMETER,">$jmx") or die "couldn't open file for write: $!\r\n$^E";
    
    my $jmeter = XML::DOM::Document->new;
    my $xml_pi = $jmeter->createXMLDecl('1.0');
    my $root = $jmeter->createElement('jmeterTestPlan');
    $root->setAttribute('version','1.2');
    $root->setAttribute('properties',' 1.8');
    my $roothashtree = $jmeter->createElement('hashTree');
    my $testplan = $jmeter->createElement('TestPlan');
    my $testplanhashtree = $jmeter->createElement('hashTree');
    my $threadgroup = $jmeter->createElement('ThreadGroup');
    my $threadgrouphashtree = $jmeter->createElement('hashTree');
    my $configtestelement = $jmeter->createElement('ConfigTestElement');
    my $configtesthashtree = $jmeter->createElement('hashTree');
    my $cookiemanager = $jmeter->createElement('CookieManager');
    my $cookiemanagerhashtree = $jmeter->createElement('hashTree');
    
    my $property;
    my $elementproperty;
    
    $root->appendChild($roothashtree);
    $roothashtree->appendChild($testplan);
    $roothashtree->appendChild($testplanhashtree);
    $testplanhashtree->appendChild($threadgroup);
    $testplanhashtree->appendChild($threadgrouphashtree);
    $threadgrouphashtree->appendChild($configtestelement);
    $threadgrouphashtree->appendChild($configtesthashtree);
    $threadgrouphashtree->appendChild($cookiemanager);
    $threadgrouphashtree->appendChild($cookiemanagerhashtree);
    
    
    $testplan->setAttribute('guiclass','TestPlanGui');
    $testplan->setAttribute('testclass','TestPlan');
    $testplan->setAttribute('testname','LR2JM Test Plan: '.$lrscript);
    $testplan->setAttribute('enabled','true');
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','TestPlan.functional_mode');
        $property->addText('false');
    $testplan->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','TestPlan.comments');
    $testplan->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','TestPlan.user_define_classpath');
    $testplan->appendChild($property);
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','TestPlan.serialize_threadgroups' );
        $property->addText('false');
    $testplan->appendChild($property);
        $elementproperty = $jmeter->createElement('elementProp');
        $elementproperty->setAttribute('name','TestPlan.user_defined_variables');
        $elementproperty->setAttribute('elementType','Arguments');
        $elementproperty->setAttribute('guiclass','ArgumentsPanel');
        $elementproperty->setAttribute('testclass','Arguments');
        $elementproperty->setAttribute('testname','User Defined Variables');
        $elementproperty->setAttribute('enabled','true');
            $property = $jmeter->createElement('collectionProp');
            $property->setAttribute('name','Arguments.arguments');
        $elementproperty->appendChild($property);
    $testplan->appendChild($elementproperty);
    
    $threadgroup->setAttribute('guiclass','ThreadGroupGui');
    $threadgroup->setAttribute('testclass','ThreadGroup');
    $threadgroup->setAttribute('testname','LR2JM Thread Group');
    $threadgroup->setAttribute('enabled','true');
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','ThreadGroup.scheduler');
        $property->addText('false');
    $threadgroup->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','ThreadGroup.num_threads');
        $property->addText('1');
    $threadgroup->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','ThreadGroup.duration');
    $threadgroup->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','ThreadGroup.delay');
    $threadgroup->appendChild($property);
        $property = $jmeter->createElement('longProp');
        $property->setAttribute('name','ThreadGroup.start_time' );
        $property->addText('1187292555000');
    $threadgroup->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','ThreadGroup.on_sample_error');
        $property->addText('continue');
    $threadgroup->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','ThreadGroup.ramp_time');
        $property->addText('1');
    $threadgroup->appendChild($property);
        $elementproperty = $jmeter->createElement('elementProp');
        $elementproperty->setAttribute('name','ThreadGroup.main_controller');
        $elementproperty->setAttribute('elementType','LoopController');
        $elementproperty->setAttribute('guiclass','LoopControlPanel');
        $elementproperty->setAttribute('testclass','LoopController');
        $elementproperty->setAttribute('testname','Loop Controller');
        $elementproperty->setAttribute('enabled','true');
            $property = $jmeter->createElement('stringProp');
            $property->setAttribute('name','LoopController.loops');
            $property->addText('1');
        $elementproperty->appendChild($property);
            $property = $jmeter->createElement('boolProp');
            $property->setAttribute('name','LoopController.continue_forever' );
            $property->addText('false');
        $elementproperty->appendChild($property);
    $threadgroup->appendChild($elementproperty);
        $property = $jmeter->createElement('longProp');
        $property->setAttribute('name','ThreadGroup.end_time');
        $property->addText('1187292555000');
    $threadgroup->appendChild($property);
    
    $configtestelement->setAttribute('guiclass','HttpDefaultsGui');
    $configtestelement->setAttribute('testclass','ConfigTestElement');
    $configtestelement->setAttribute('testname','HTTP Request Defaults');
    $configtestelement->setAttribute('enabled','true');
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.domain');
        $property->addText('');
    $configtestelement->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.path');
    $configtestelement->appendChild($property);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.port');
        $property->addText('80');
    $configtestelement->appendChild($property);
        $elementproperty = $jmeter->createElement('elementProp');
        $elementproperty->setAttribute('name','HTTPsampler.Arguments');
        $elementproperty->setAttribute('elementType','Arguments');
        $elementproperty->setAttribute('guiclass','HTTPArgumentsPanel');
        $elementproperty->setAttribute('testclass','Arguments');
        $elementproperty->setAttribute('testname','User Defined Variables');
        $elementproperty->setAttribute('enabled','true');
            $property = $jmeter->createElement('collectionProp');
            $property->setAttribute('name','Arguments.arguments');
        $elementproperty->appendChild($property);
    $configtestelement->appendChild($elementproperty);
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.protocol');
    $configtestelement->appendChild($property);
              
    $cookiemanager->setAttribute('guiclass','CookiePanel');
    $cookiemanager->setAttribute('testclass','CookieManager');
    $cookiemanager->setAttribute('testname','HTTP Cookie Manager');
    $cookiemanager->setAttribute('enabled','true');
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','CookieManager.clearEachIteration');
        $property->addText('false');
    $cookiemanager->appendChild($property);
        $property = $jmeter->createElement('collectionProp');
        $property->setAttribute('name','CookieManager.cookies');
    $cookiemanager->appendChild($property);
    
    foreach my $key (keys %tables){
    	my ($datafile,@columns) = @{$tables{$key}};
    	$elementproperty = $jmeter->createElement('CSVDataSet');
    	$elementproperty->setAttribute('guiclass','TestBeanGUI');
    	$elementproperty->setAttribute('testclass','CSVDataSet');
    	$elementproperty->setAttribute('testname','LR2JM Data Set');
    	$elementproperty->setAttribute('enabled','true');
    	$property=$jmeter->createElement('stringProp');
    	$property->setAttribute('name','delimiter');
    	$property->addText(',');
    	$elementproperty->appendChild($property);
    	$property=$jmeter->createElement('stringProp');
    	$property->setAttribute('name','fileEncoding');
    	$elementproperty->appendChild($property);
    	$property=$jmeter->createElement('stringProp');
    	$property->setAttribute('name','filename');
    	$property->addText($datafile);
    	$elementproperty->appendChild($property);
    	$property=$jmeter->createElement('boolProp');
    	$property->setAttribute('name','recycle');
    	$property->addText('true');
    	$elementproperty->appendChild($property);
    	$property=$jmeter->createElement('stringProp');
    	$property->setAttribute('name','variableNames');
    	$property->addText(join(',',@columns));
    	$elementproperty->appendChild($property);
    	
    	$threadgrouphashtree->appendChild($elementproperty);
    	my $hashtree = $jmeter->createElement('hashTree');
        $threadgrouphashtree->appendChild($hashtree);
    }
    #print "tables done\r\n";
    
	my $transactionController = $jmeter->createElement('TransactionController');
	$transactionController->setAttribute('guiclass','TransactionControllerGui');
    $transactionController->setAttribute('testclass','TransactionController');
    $transactionController->setAttribute('testname','Transaction Controller');
    $transactionController->setAttribute('enabled','true');
	my $boolProp = $jmeter->createElement('boolProp');
	$boolProp->setAttribute('name','TransactionController.parent');
	$boolProp->addText('true');
	$transactionController->appendChild($boolProp);
			
	$threadgrouphashtree->appendChild($transactionController);
	my $transactionhashtree = $jmeter->createElement('hashTree');
	$threadgrouphashtree->appendChild($transactionhashtree);
	
	my $usingExplicitTransaction = 0;
	my $isEmptyTransaction = 1;
	
    foreach my $requestdata (@webrequests) {
		# Add Transactions
		my $lrfunction = ${$requestdata}{'function'};
        my $httpsampler = $jmeter->createElement('HTTPSampler');
        my $hashtree = $jmeter->createElement('hashTree');

		
		
		
		if ($lrfunction eq "lr_start_transaction") {
		
			if (not($usingExplicitTransaction) && not($isEmptyTransaction)) {
			

				$transactionController = $jmeter->createElement('TransactionController');
				$threadgrouphashtree->appendChild($transactionController);
				$transactionhashtree = $jmeter->createElement('hashTree');
				$threadgrouphashtree->appendChild($transactionhashtree);
				
				$usingExplicitTransaction = 1;
				$isEmptyTransaction = 1;
			}
			
			$transactionController->setAttribute('guiclass','TransactionControllerGui');
        	$transactionController->setAttribute('testclass','TransactionController');
        	$transactionController->setAttribute('testname',${$requestdata}{'transactionname'});
        	$transactionController->setAttribute('enabled','true');
			$boolProp = $jmeter->createElement('boolProp');
			$boolProp->setAttribute('name','TransactionController.parent');
			$boolProp->addText('true');
			$transactionController->appendChild($boolProp);
			
			
			next;
		}


		if ($lrfunction eq "lr_end_transaction") {
			
			$usingExplicitTransaction = 0;
			$isEmptyTransaction = 1;
			
			$transactionController = $jmeter->createElement('TransactionController');
			$transactionController->setAttribute('guiclass','TransactionControllerGui');
        	$transactionController->setAttribute('testclass','TransactionController');
        	$transactionController->setAttribute('testname','Transaction Controller');
        	$transactionController->setAttribute('enabled','true');
			$boolProp = $jmeter->createElement('boolProp');
			$boolProp->setAttribute('name','TransactionController.parent');
			$boolProp->addText('true');
			$transactionController->appendChild($boolProp);
			
			$threadgrouphashtree->appendChild($transactionController);
			$transactionhashtree = $jmeter->createElement('hashTree');
			$threadgrouphashtree->appendChild($transactionhashtree);
			
			next;
		}
		
		if ($isEmptyTransaction) {
			$isEmptyTransaction = 0;
		}
		
		
		
		
		if($#{ ${$requestdata}{'headers'} } >= 0) {
			
			#Add header elements uder $hashtree
			my $header = $jmeter->createElement('HeaderManager');
			$header->setAttribute('guiclass','HeaderPanel');
			$header->setAttribute('testclass','HeaderManager');
			$header->setAttribute('testname','HTTP Header Manager');
			$header->setAttribute('enabled','true');
			$hashtree->appendChild($header);
			$hashtree->appendChild($jmeter->createElement('hashTree'));
			
			my $collectionProp = $jmeter->createElement('collectionProp');
			$collectionProp->setAttribute('name','HeaderManager.headers');
			$header->appendChild($collectionProp);
			
			for my $i ( 0 .. $#{ ${$requestdata}{'headers'} } ) {
		
			
				my $elementProp = $jmeter->createElement('elementProp');
				$elementProp->setAttribute('name','');
				$elementProp->setAttribute('elementType','Header');
				$collectionProp->appendChild($elementProp);
				
				my $stringPropName = $jmeter->createElement('stringProp');
				$stringPropName->setAttribute('name','Header.name');
				$stringPropName->addText(paramSubstitution(${$requestdata}{headers}[$i][0]));
				$elementProp->appendChild($stringPropName);
				
				my $stringPropValue = $jmeter->createElement('stringProp');
				$stringPropValue->setAttribute('name','Header.value');
				$stringPropValue->addText(paramSubstitution(${$requestdata}{headers}[$i][1]));
				$elementProp->appendChild($stringPropValue);
			}
		}
		
        foreach my $dynamicparams (${$requestdata}{'params'}){
        	my %dynamicparams = %{$dynamicparams};
        	foreach my $param (keys %dynamicparams){
        		my $regex = $dynamicparams{$param};
        		my $regexextractor = $jmeter->createElement('RegexExtractor');
        		$regexextractor->setAttribute('guiclass','RegexExtractorGui');
        		$regexextractor->setAttribute('testclass','RegexExtractor');
        		$regexextractor->setAttribute('testname','LR2JM Regex Extractor');
        		$regexextractor->setAttribute('enabled','true');
        		$hashtree->appendChild($regexextractor);
        		
        		my $property = $jmeter->createElement('stringProp');
	        	$property->setAttribute('name','RegexExtractor.useHeaders');
	        	$property->addText('false');
	        	$regexextractor->appendChild($property);
        		
        		$property = $jmeter->createElement('stringProp');
	        	$property->setAttribute('name','RegexExtractor.refname');
	        	$property->addText($param);
	        	$regexextractor->appendChild($property); 
        		
        		$property = $jmeter->createElement('stringProp');
	        	$property->setAttribute('name','RegexExtractor.regex');
	        	$property->addText($regex);
	        	$regexextractor->appendChild($property); 
        		
        		$property = $jmeter->createElement('stringProp');
	        	$property->setAttribute('name','RegexExtractor.template');
	        	$property->addText('$1$');
	        	$regexextractor->appendChild($property); 
        		
        		$property = $jmeter->createElement('stringProp');
	        	$property->setAttribute('name','RegexExtractor.default');
	        	$regexextractor->appendChild($property); 
	        	
        		$property = $jmeter->createElement('stringProp');
	        	$property->setAttribute('name','RegexExtractor.match_number');
	        	$property->addText('1');
	        	$regexextractor->appendChild($property); 
	        	
	        	my $regexhashtree = $jmeter->createElement('hashTree');
        		$hashtree->appendChild($regexhashtree);
	        	
        	}
        }
        
        $transactionhashtree->appendChild($httpsampler);
        $transactionhashtree->appendChild($hashtree);
        
        $httpsampler->setAttribute('guiclass','HttpTestSampleGui');
        $httpsampler->setAttribute('testclass','HTTPSampler');
        $httpsampler->setAttribute('testname',${$requestdata}{'stepname'});
        $httpsampler->setAttribute('enabled','true');
        
        $elementproperty = $jmeter->createElement('elementProp');
        $elementproperty->setAttribute('name','HTTPsampler.Arguments');
        $elementproperty->setAttribute('elementType','Arguments');
        $elementproperty->setAttribute('guiclass','HTTPArgumentsPanel');
        $elementproperty->setAttribute('testclass','Arguments');
        $elementproperty->setAttribute('enabled','true');
        my $collectionproperty = $jmeter->createElement('collectionProp');
        $collectionproperty->setAttribute('name','Arguments.arguments');
        $elementproperty->appendChild($collectionproperty);
        $httpsampler->appendChild($elementproperty);
        
        my $itemdataref = ${$requestdata}{'itemdata'};
        
		
		if($#{$itemdataref} eq -1 ){
			
			my $boolProp = $jmeter->createElement('boolProp');
			$boolProp->setAttribute('name','HTTPSampler.postBodyRaw');
			$boolProp->addText('true');
			$httpsampler->appendChild($boolProp);
			
			my $httpargproperty = $jmeter->createElement('elementProp');
			$httpargproperty->setAttribute('name','');
        	$httpargproperty->setAttribute('elementType','HTTPArgument');
			$collectionproperty->appendChild($httpargproperty);
			
			$property = $jmeter->createElement('boolProp');
	        $property->setAttribute('name','HTTPArgument.always_encode');
	        $property->addText('false');
	        $httpargproperty->appendChild($property); 
		
        	my $value = paramSubstitution(${$requestdata}{'bodydata'});
			
			$property = $jmeter->createElement('stringProp');
	        $property->setAttribute('name','Argument.value');
	        $property->addText($value);
	        $httpargproperty->appendChild($property);

	        $property = $jmeter->createElement('stringProp');
	        $property->setAttribute('name','Argument.metadata');
	        $property->addText('=');
	        $httpargproperty->appendChild($property); 			
		}
		
        for (my $i=0;$i < $#{$itemdataref};$i+=2) {
        	my $name = paramSubstitution(${$itemdataref}[$i]);
        	my $value = paramSubstitution(${$itemdataref}[$i+1]);
        	
        	my $httpargproperty = $jmeter->createElement('elementProp');
        	$httpargproperty->setAttribute('name','');
        	$httpargproperty->setAttribute('elementType','HTTPArgument');
        	$collectionproperty->appendChild($httpargproperty);
        	
        	$property = $jmeter->createElement('boolProp');
	        $property->setAttribute('name','HTTPArgument.always_encode');
	        $property->addText('false');
	        $httpargproperty->appendChild($property); 
	        
	        $property = $jmeter->createElement('stringProp');
	        $property->setAttribute('name','Argument.value');
	        $property->addText($value);
	        $httpargproperty->appendChild($property); 
	        
	        $property = $jmeter->createElement('stringProp');
	        $property->setAttribute('name','Argument.metadata');
	        $property->addText('=');
	        $httpargproperty->appendChild($property); 
        	
        	$property = $jmeter->createElement('boolProp');
	        $property->setAttribute('name','HTTPArgument.use_equals');
	        $property->addText('true');
	        $httpargproperty->appendChild($property); 
	        
	        $property = $jmeter->createElement('stringProp');
	        $property->setAttribute('name','Argument.name');
	        $property->addText($name);
	        $httpargproperty->appendChild($property); 
        	
        }
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.domain');
        $property->addText(paramSubstitution(${$requestdata}{'domain'}));        
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.port');     
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.protocol');     
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.method');
        $property->addText(${$requestdata}{'method'}); 
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.contentEncoding');     
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.path');
        $property->addText(paramSubstitution(${$requestdata}{'path'}));        
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','HTTPSampler.follow_redirects');
        $property->addText('true');        
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','HTTPSampler.auto_redirects');
        $property->addText('true');        
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','HTTPSampler.use_keepalive');
        $property->addText('true');        
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','HTTPSampler.DO_MULTIPART_POST');
        $property->addText('false');        
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.mimetype');     
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.FILE_NAME');     
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.FILE_FIELD');     
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('boolProp');
        $property->setAttribute('name','HTTPSampler.image_parser');
        $property->addText(${$requestdata}{'image_parser'});        
        $httpsampler->appendChild($property);
    	
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.monitor');
        $property->addText('true');    
        $httpsampler->appendChild($property);
        
        $property = $jmeter->createElement('stringProp');
        $property->setAttribute('name','HTTPSampler.embedded_url_re');     
        $httpsampler->appendChild($property);
        
    }
    
    my $jmeterxml = $xml_pi->toString.$root->toString;

    print JMETER $jmeterxml;    
    close JMETER;

    my $xmltidy = XML::Tidy->new('filename' => $jmx);
    $xmltidy->tidy();
    print $xmltidy->write();
    
}
 
sub paramSubstitution
{
    my $inputstring = shift;
    foreach my $param (keys %paramsubs) {
		#print "$param\n";
        $inputstring =~ s/{$param}/\${$paramsubs{$param}}/g;
    }
    return $inputstring;
}
