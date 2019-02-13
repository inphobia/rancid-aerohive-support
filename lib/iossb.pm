package iossb;
##
## $Id: iossb.pm.in 3878 2018-09-07 18:27:48Z heas $
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
#  iossb.pm - Cisco IOS small business rancid procedures

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.9;

our $proc;
our $ios;
our $found_version;
our $found_env;
our $found_diag;
our $config_register;			# configuration register value

our $C0;				# output formatting control
our $E0;
our $H0;
our $I0;
our $DO_SHOW_VLAN;

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    $proc = "";
    $ios = "IOS";
    $found_version = 0;
    $found_env = 0;
    $found_diag = 0;
    $config_register = undef;		# configuration register value

    $C0 = 0;				# output formatting control
    $E0 = 0;
    $H0 = 0;
    $I0 = 0;
    $DO_SHOW_VLAN = 0;

    # add content lines and separators
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");
    ProcessHistory("COMMENTS","keysort","B0","!\n");
    ProcessHistory("COMMENTS","keysort","D0","!\n");
    ProcessHistory("COMMENTS","keysort","F0","!\n");
    ProcessHistory("COMMENTS","keysort","G0","!\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
        # note: this match sucks rocks, but currently the cisco-sb bits are
        # unreliable about echoing the '\n' after exit.  this match might
        # really be a bad idea, but instead rely upon WriteTerm's found_end?
CMD:	if (/[>#]\s?exit(Connection( to \S+)? closed)?/ && $found_end) {
	    $clean_run = 1;
	    last;
	}
	if (/^Error:/) {
	    print STDOUT ("$host clogin error: $_");
	    print STDERR ("$host clogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[>#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^#>]+[#>])/)[0];
		$prompt =~ s/([][}{)(+\\])/\\$1/g;
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
	    if (defined($prompt)) {
		if (/$prompt/) {
		    goto CMD;
		}
	    }
	}
    }
}

# This routine parses "show system"
sub ShowSystem {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($slave, $slaveslot);
    print STDERR "    In ShowSystem: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);

	/system description:\s+(.*)$/i &&
	    ProcessHistory("COMMENTS","keysort","B0","! Chassis type: $1\n") &&
	    next;
	# # filter individual unit temperature XXX sg500 unit temps
	# if (/unit\stemperature/i) {
	#     while (<$INPUT>) {
	# 	tr/\015//d;
	# 	return(0) if (/^$prompt/);
	# 	next if (/^(\s*|\s*$cmd\s*)$/);
	# 	next if (/^\s+\^$/);
	#
	# 	last if (/^\s*$/);
	#     }
	# }
    }
    return(0);
}


# This routine parses "show version"
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($slave, $slaveslot);
    print STDERR "    In ShowVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);

	ProcessHistory("COMMENTS","keysort","E0","! Image: $_");
    }
    return(0);
}


# This routine parses "show running-config"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($comment, $linecnt) = (0,0);
    print STDERR "    In WriteTerm: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);

	# skip emtpy lines at the beginning
	if (!$linecnt && /^\s*$/) {
	    next;
	}
	$linecnt++;

	# these appear to be reversables
	# enable password level 15 encrypted z9111212555bd4b0d3bec0b98f7ddd6346
        if (/^(enable )?(password|passwd)( level \d+)? / && $filter_pwds >= 1) {
            ProcessHistory("ENABLE","","","!$1$2$3 <removed>\n");
            next;
        }
	# username cisco password encrypted z9111212555bd4b0d3bec0b98f7ddd6346 privilege 15
        if (/^username (\S+)(\s.*)? password encrypted (\S+)/) {
            if ($filter_pwds >= 1){
                ProcessHistory("USER","keysort","$1",
                               "!username $1$2 password encrypted <removed>$'");
            } else {
                ProcessHistory("USER","keysort","$1","$_");
            }
            next;
        }

	# order/prune snmp-server host statements
	# we only prune lines of the form
	# snmp-server host <ip> traps version 2c <community>
	if (/^(snmp-server host (\d+\.\d+\.\d+\.\d+) traps.* )(\S+)$/) {
            if ($filter_commstr) {
                ProcessHistory("SNMPTRAPHOST","ipsort","$2","! $1<removed>\n");
            } else {
                ProcessHistory("SNMPTRAPHOST","ipsort","$2","$_");
            }
            next;
	}
	# snmp-server community <community> ro <ip> view Default
	if (/^(snmp-server community )\S+ (\w+) (\d+\.\d+\.\d+\.\d+)(.*)$/) {
            if ($filter_commstr) {
                ProcessHistory("SNMPSERVERHOST","ipsort","$3","! $1<removed> $2 $3$4\n");
            } else {
                ProcessHistory("SNMPSERVERHOST","ipsort","$3","$_");
            }
            next;
	}

	# encrypted tacacs-server host <ip> key <keyhash> priority 1
	# encrypted tacacs-server key <keyhash>
	if (/^(encrypted (tacacs|radius)-server\s.*\s?key) (\S+)/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>$'"); next;
	}

	# catch anything that wasnt matched above.
	ProcessHistory("","","","$_");
	# end of config.
	# XXX no definitive end of config marker.
	#if (/^exit$/) {
	#    $found_end = 1;
	#    return(0);
	#}
    }

    # The ContentEngine lacks a definitive "end of config" marker.  If we
    # know that it is a CE, SAN, or NXOS and we have seen at least 5 lines
    # of write term output, we can be reasonably sure that we have the config.
    if ($linecnt > 5) {
        $found_end = 1;
        return(0);
    }

    return(0);
}

1;
