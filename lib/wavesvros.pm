package wavesvros;
##
## $Id: wavesvros.pm.in 3860 2018-08-11 12:02:29Z heas $
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
#  wavesvros.pm - Ciena Waveserver rancid procedures
#

use 5.010;
use strict 'vars';
use warnings;
require(Exporter);
our @ISA = qw(Exporter);
$Exporter::Verbose=1;

use rancid 3.9;

@ISA = qw(Exporter rancid main);
#our @EXPORT = qw($VERSION)

# load-time initialization
sub import {
    $timeo = 120;			# jlogin timeout in seconds

    0;
}

# post-open(collection file) initialization
sub init {
    # add content lines and separators
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while (<$INPUT>) {
	tr/\015//d;
	if (/^Error:/) {
	    print STDOUT ("$host hlogin error: $_");
	    print STDERR ("$host hlogin error: $_") if ($debug);
	    $clean_run=0;
	    last;
	}
	if (/System shutdown message/) {
	    print STDOUT ("$host shutdown msg: $_");
	    print STDERR ("$host shutdown msg: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	if (/error: cli version does not match Managment Daemon/i) {
	    print STDOUT ("$host mgd version mismatch: $_");
	    print STDERR ("$host mgd version mismatch: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[>#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$_ =~ /^([^>#*^]+)([*^])?([>#])/;
		$prompt = $1;
		my($tail) = $3;
		$prompt =~ s/([][}{)(\\])/\\$1/g;
		# prompt changes when config is unsaved - "foo*> " and may be
		# "foo$> " for some unknown reason.
		$prompt .= "[*^]?" . $tail . " ?";
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
	if (/[>#]\s*exit/) {
	    $clean_run=1;
	    last;
	}
    }
}

# This routine parses a few commands generically
sub GenericCmd {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In GenericCmd: $_" if ($debug);

    # include the command
    s/^[a-z]+@//; s/^([^ ]+)\*([>#])/$1$2/;
    ProcessHistory("","","","! $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);

	ProcessHistory("","","","! $_");
    }
    ProcessHistory("","","","!\n");

    return(0);
}

# This routine parses "chassis show"
sub ShowChassis {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($PSW) = 0;
    print STDERR "    In ShowChassisClocks: $_" if ($debug);

    # include the command
    s/^[a-z]+@//; s/^([^ ]+)\*([>#])/$1$2/;
    ProcessHistory("","","","! $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	/no matching entry found/ && return(-1);	# unknown cmd

	# skip fan status/chassis power draw
	if (/(cfu fan status|chassis power summary)/i) {
	    while (<$INPUT>) {
		tr/\015//d;
		return(-1) if (/^$prompt/);
		last if (/^\s*$/);
	    }
	}
	# filter PS wattage from power supply status
	if (/power supply status/i) {
	    ProcessHistory("","","","! $_");
	    while (<$INPUT>) {
		tr/\015//d;
		goto EndShowChassis if (/^$prompt/);
		$PSW = 1 if (/power \(w\)/i);
		if ($PSW && /^((?:\|[^|]+){7,})\|\s+(?:[0-9.]+ \|)/) {
		    ProcessHistory("","","","! $1|\n");
		} else {
		    ProcessHistory("","","","! $_");
		}
		last if (/^\s*$/);
	    }
	}

	ProcessHistory("","","","! $_");
    }
EndShowChassis:
    return(0);
}

# This routine parses "software show"
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVersion: $_" if ($debug);

    # include the command
    s/^[a-z]+@//; s/^([^ ]+)\*([>#])/$1$2/;
    ProcessHistory("","","","! $_");
    # skip software state info
    while (<$INPUT>) {
	tr/\015//d;
	return(0) if (/^$prompt/);
	/no matching entry found/ && return(-1);	# unknown cmd

	last if (/^\s*$/);
    }

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);

	ProcessHistory("","","","! $_");
    }
    ProcessHistory("","","","!\n");

    return(0);
}

# This routine parses "configuration show"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($snmp) = 0;
    print STDERR "    In ShowConfiguration: $_" if ($debug);

    # include the command
    s/^[a-z]+@//; s/^([^ ]+)\*([>#])/$1$2/;
    ProcessHistory("","","","! $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	/no matching entry found/ && return(-1);	# unknown cmd

	next if (/^! created( by)?: /i);
	next if (/^! on terminal: /i);
	next if (/^! defaults: /i);

#	# filter snmp community, when in snmp { stanza }
#	/^snmp/ && $snmp++;
#	/^}/ && ($snmp = 0);
#	if ($snmp && /^(\s*)(community|trap-group) [^ ;]+(\s?[;{])$/) {
#		if ($filter_commstr) {
#		    $_ = "$1$2 \"<removed>\"$3\n";
#		}
#	}
#	if (/(\s*authentication-key )[^ ;]+/ && $filter_pwds >= 1) {
#	    ProcessHistory("","","","#$1<removed>$'");
#	    next;
#	}
	if (/(user create user \S+ access-level \S+ secret) / &&
	    $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1<removed>\n");
	    next;
	}
#	if (/(\s*hello-authentication-key )[^ ;]+/ && $filter_pwds >= 1) {
#	    ProcessHistory("","","","#$1<removed>$'");
#	    next;
#	}
#	# don't filter this one - there is no secret here.
#	if (/^\s*permissions .* secret /) {
#	    ProcessHistory("","","","$_");
#	    next;
#	}
#	if (/^(.*\s(secret|simple-password) )[^ ;]+/ && $filter_pwds >= 1) {
#	    ProcessHistory("","","","#$1<removed>$'");
#	    next;
#	}
#	if (/(\s+encrypted-password )[^ ;]+/ && $filter_pwds >= 2) {
#	    ProcessHistory("","","","#$1<removed>$'");
#	    next;
#	}
#	if (/(\s+ssh-(rsa|dsa) )\"/ && $filter_pwds >= 2) {
#	    ProcessHistory("","","","#$1<removed>;\n");
#	    next;
#	}
#	if (/^(\s+(pre-shared-|)key (ascii-text|hexadecimal) )[^ ;]+/ && $filter_pwds >= 1) {
#	    ProcessHistory("","","","#$1<removed>$'");
#	    next;
#	}
	if (/^! END OF CONFIG:/) {
	    $found_end = 1;
	}
	ProcessHistory("","","","$_");
    }

    return(0);
}

1;
