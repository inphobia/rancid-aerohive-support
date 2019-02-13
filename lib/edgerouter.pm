package edgerouter;
##
## $Id: edgerouter.pm.in 3878 2018-09-07 18:27:48Z heas $
##
## rancid 3.9
## Copyright (c) 1997-2018 by Henry Kilmer and John Heasley
## All rights reserved.
##
## This code is derived from software contributed to and maintained by
## Henry Kilmer, John Heasley, Andrew Partan,
## Pete Whiting, Austin Schutz, and Andrew Fort.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 1. Redistributions of source code must retain the above copyright
##    notice, this list of conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above copyright
##    notice, this list of conditions and the following disclaimer in the
##    documentation and/or other materials provided with the distribution.
## 3. Neither the name of RANCID nor the names of its
##    contributors may be used to endorse or promote products derived from
##    this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY Henry Kilmer, John Heasley AND CONTRIBUTORS
## ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
## TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
## PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COMPANY OR CONTRIBUTORS
## BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.
##
## It is the request of the authors, but not a condition of license, that
## parties packaging or redistributing RANCID NOT distribute altered versions
## of the etc/rancid.types.base file nor alter how this file is processed nor
## when in relation to etc/rancid.types.conf.  The goal of this is to help
## suppress our support costs.  If it becomes a problem, this could become a
## condition of license.
# 
#  The expect login scripts were based on Erik Sherk's gwtn, by permission.
# 
#  The original looking glass software was written by Ed Kern, provided by
#  permission and modified beyond recognition.
#
#  RANCID - Really Awesome New Cisco confIg Differ
#
#  edgerouter.pm - Ubiquity ("UBNT") EdgeRouter switch rancid procedures

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.9;

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    # add content lines and separators
    ProcessHistory("","","","#RANCID-CONTENT-TYPE: $devtype\n#\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/^Error:/) {
	    print STDOUT ("$host flogin error: $_");
	    print STDERR ("$host flogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[\$#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^\$#]+[\$#])/)[0];
		$prompt =~ s/([][}{)(\\\$])/\\$1/g;
		print STDERR ("PROMPT MATCH: $prompt\n") if ($debug);
	    }
	    print STDERR ("HIT COMMAND:$_") if ($debug);
	    if (! defined($commands{$cmd})) {
		print STDERR "$host: found unexpected command - \"$cmd\"\n";
		$clean_run = 0;
		last TOP;
	    }
	    if (! defined(&{$commands{$cmd}})) {
		printf(STDERR "$host: undefined function - \"%s\"\n",
		       $commands{$cmd});
		$clean_run = 0;
		last TOP;
	    }
	    $rval = &{$commands{$cmd}}($INPUT, $OUTPUT, $cmd);
	    delete($commands{$cmd});
	    if ($rval == -1) {
		$clean_run = 0;
		last TOP;
	    }
	}
	if (/[\#\$]\s?(exit|logout)$/) {
	    $clean_run = 1;
	    last;
	}
    }
}

# This routine parses "show version"
sub ShowVersion {
    my($INPUT, $OUTPUT) = @_;
    my($slot);

    print STDERR "    In ShowVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^\s+\^$/);
        return(1) if (/invalid (input|command) detected/i);
        return(-1) if (/^plat exception:/i);	# failure to connect?
	next if /^\s*$/;

	next if (/^(uptime|copyright):/i);

	ProcessHistory("VERSION","","","#$_");
    }
    ProcessHistory("VERSION","","","#\n");
    return(0);
}

# This routine parses "show hardware"
sub ShowHardware {
    my($INPUT, $OUTPUT) = @_;

    print STDERR "    In ShowHardware: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^\s+\^$/);
        return(1) if (/invalid (input|command) detected/i);

	ProcessHistory("HARDWARE","","","#$_");
    }
    ProcessHistory("HARDWARE","","","#\n");
    return(0);
}

# This routine parses "show ubnt Offload"
sub ShowOffload {
    my($INPUT, $OUTPUT) = @_;
    print STDERR "    In ShowEnvironment: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^\s+\^$/);
        return(1) if (/invalid (input|command) detected/i);
	next if (/^\s*$/);

	ProcessHistory("OFFLOAD","","","#$_");
    }
    ProcessHistory("","","","#\n");
    return;
}

# This routine processes a "write running-config"
sub WriteTerm {
    my($INPUT, $OUTPUT) = @_;
    print STDERR "    In WriteTerm: $_" if ($debug);
    my($comment, $linecnt) = (0, 0);

    # reset our end marker, if WriteTerm is called multiple times, eg: bird vers
    $found_end = 0;

    ProcessHistory("CMD","","","# $_");

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^\s+\^$/);
        return(1) if (/invalid (input|command) detected/i);
	return(0) if ($found_end);		# Only do this routine once
	last if (/^$prompt/);

	$linecnt++;

	/^\s*$/ && next;					# blank lines

	# filter out any RCS/CVS tags to avoid confusing local CVS storage
	s/\$(Revision|Id):/ $1:/;

	# XXX TBD
	## order access-lists
	#/^access-list\s+(\d\d?)\s+(\S+)\s+([a-zA-Z]\S+)/ &&
	#    ProcessHistory("ACL $1 $2","$aclsort","-1","$_") && next;
	#/^access-list\s+(\d\d?)\s+(\S+)\s+(\S+)/ &&
	#    ProcessHistory("ACL $1 $2","$aclsort","$3","$_") && next;
	## order extended access-lists
	#/^access-list\s+(\d\d\d)\s+(\S+)\s+ip\s+host\s+(\S+)/ &&
	#    ProcessHistory("EACL $1 $2","$aclsort","$3","$_") && next;
	#/^access-list\s+(\d\d\d)\s+(\S+)\s+ip\s+(\d\S+)/ &&
	#    ProcessHistory("EACL $1 $2","$aclsort","$3","$_") && next;
	#/^access-list\s+(\d\d\d)\s+(\S+)\s+ip\s+any/ &&
	#    ProcessHistory("EACL $1 $2","$aclsort","0.0.0.0","$_") && next;
	## oreder ip routes
	#/^ip route\s+(\S+)\s+/ &&
	#    ProcessHistory("ROUTE","ipsort","$1","$_") && next;
	## order/prune snmp-server host/community statements
	## snmp-server host ip.add.r "public"
	## snmp-server host ip.add.r informs "public"
	## snmp-server host ip.add.r informs retries 1 "public"
	#if (/^(snmp-server host )(\d+\.\d+\.\d+\.\d+ ([^"]*)?)/) {
	#    if ($filter_commstr) {
	#	ProcessHistory("SNMPSERVERHOST","ipsort","$2","#$1$2<removed>\n") && next;
	#    } else {
	#	ProcessHistory("SNMPSERVERHOST","ipsort","$2","$_") && next;
	#    }
	#}

	if (/^(\s*community)\s+(\S+)/) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_","#$1 <removed>$'") && next;
	    } else {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_","$_") && next;
	    }
	}
	## filter tacacs key statements
	#if (/^(tacacs-server key )/ && $filter_pwds >= 1) {
	#    ProcessHistory("","","","# $1<removed>\n");
	#    next;
	#}

	# filter ssh public keys
	if (/^(\s*key) \S+\s*$/ && $filter_pwds >= 2) {
	    ProcessHistory("","","","#$1 <removed>\n");
	    next;
	}
	# filter user plaintext password
	if (/^(\s*plaintext-password)\s+\S+$/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("","","","#$1 <removed>\n");
	    next;
	}
	# filter user encrypted password
	if (/^(\s*encrypted-password)\s+\S+$/ &&
	    $filter_pwds >= 2) {
	    ProcessHistory("","","","#$1 <removed>\n");
	    next;
	}
	# filter protocol (bgp, etc) password
	if (/^(\s*password)\s+\S+$/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("","","","#$1 <removed>\n");
	    next;
	}

	ProcessHistory("","","","$_");
    }

    # The Edgemax lacks a definitive "end of config" marker.  If we have at
    # least 5 lines of output, we can be reasonably sure that we have the
    # config.
    if ($linecnt > 5) {
	$found_end = 1;
	return(0);
    }

    return(0);
}

1;
