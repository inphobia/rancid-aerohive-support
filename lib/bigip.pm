package bigip;
##
## $Id: bigip.pm.in 3933 2018-11-30 19:28:47Z heas $
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
#  bigip.pm - F5 BIG-IP >= v11 rancid procedures

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
    # force a terminal type so as not to confuse the POS
    $ENV{'TERM'} = "vt100";

    0;
}

# post-open(collection file) initialization
sub init {
    # add content lines and separators
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");
    ProcessHistory("COMMENTS","keysort","A1","#\n");
    ProcessHistory("COMMENTS","keysort","B0","#\n");
    ProcessHistory("COMMENTS","keysort","C0","#\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/^Error:/) {
	    print STDOUT ("$host clogin error: $_");
	    print STDERR ("$host clogin error: $_") if ($debug);
	    $clean_run=0;
	    last;
	}
	while (/#\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^#]+#)/)[0];
		$prompt =~ s/([][}{)(\\])/\\$1/g;
		print STDERR ("PROMPT MATCH: $prompt\n") if ($debug);
	    }
	    print STDERR ("HIT COMMAND:$_") if ($debug);
	    if (! defined($commands{$cmd})) {
		print STDERR "$host: found unexpected command - \"$cmd\"\n";
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
	if (/\#\s?exit$/) {
	    $clean_run=1;
	    last;
	}
    }
}

# This routine parses a single command that returns no required info.  The
# output is discarded.
sub RunCommandTMSH {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In RunCommandTMSH: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	# Needed for when our prompt changes due to our executed command (for
	# example, after executing 'cd /')
	$prompt = ($_ =~ /^([^#]+#)/)[0];
	$prompt =~ s/([][}{)(\\])/\\$1/g;
	last if (/^$prompt/);
    }
    return(0);
}

# This routine parses "tmsh show /sys version"
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(-1) if (/command authorization failed/i);

	/^kernel:/i && ($_ = <$INPUT>) &&
	    ProcessHistory("COMMENTS","keysort","A3","#Image: Kernel: $_") &&
	    next;
	if (/^package:/i) {
	    my($line);

	    while ($_ = <$INPUT>) {
		tr/\015//d;
		last if (/:/);
		last if (/^$prompt/);
		chomp;
		$line .= " $_";
	    }
	    ProcessHistory("COMMENTS","keysort","A2",
			   "#Image: Package:$line\n");
	}

	if (/:/) {
	    ProcessHistory("COMMENTS","keysort","C1","#$_");
	} else {
	    ProcessHistory("COMMENTS","keysort","C1","#\t$_");
	}
    }
    return(0);
}

# This routine parses "tmsh show /sys hardware"
sub ShowHardware {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowHardware: $_" if ($debug);

    while (<$INPUT>) {
        tr/\015//d;
        last if (/^$prompt/);
        next if (/^(\s*|\s*$cmd\s*)$/);
        return(1) if /^\s*\^\s*$/;
        return(1) if /(Invalid input detected|Type help or )/;
        return(-1) if (/command authorization failed/i);

        s/\d+rpm//ig;
        s/^\|//;
        s/^\ \ ([0-9]+)(\ +).*up.*[0-9]/  $1$2up REMOVED/i;
        s/^\ \ ([0-9]+)(\ +).*Air\ Inlet/  $1$2REMOVED Air Inlet/i;
        s/^\ \ ([0-9]+)(\ +).*HSBe/  $1$2REMOVED HSBe/i;
        s/^\ \ ([0-9]+)(\ +).*TMP421 on die/  $1$2REMOVED TMP421 on die/i;
        s/^\ \ ([0-9]+)(\ +)[0-9]+\ +[0-9]+/  $1$2REMOVED     REMOVED/;
        /Type: / && ProcessHistory("COMMENTS","keysort","A0",
                                   "#Chassis type: $'");

        ProcessHistory("COMMENTS","keysort","B1","#$_") && next;
    }
    return(0);
}

# This routine parses "tmsh show /sys license"
sub ShowLicense {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($line) = (0);
    print STDERR "    In ShowLicense: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	# v9 software license does not have CR at EOF
	s/^#-+($prompt.*)/$1/;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if /(Invalid input detected|Type help or )/;
	return(-1) if (/command authorization failed/i);

	if (!$line++) {
	    ProcessHistory("LICENSE","","","#\n#/config/bigip.license:\n");
	}
	ProcessHistory("LICENSE","","","# $_") && next;
    }
    return(0);
}

# This routine parses "tmsh show /net route static"
sub ShowRouteStatic {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowRouteStatic: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if /(Invalid input detected|Type help or )/;
	return(-1) if (/command authorization failed/i);

	ProcessHistory("ROUTE","",""," $_") && next;
    }
    return(0);
}

# This routine parses "cat /config/ZebOS.conf"
sub ShowZebOSconf {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($line) = (0);
    print STDERR "    In ShowZebOSconf: $_" if ($debug);

    while (<$INPUT>) {
        tr/\015//d;
        last if (/^$prompt/);
        next if (/^(\s*|\s*$cmd\s*)$/);
        return(1) if /^\s*\^\s*$/;
        return(1) if /(Invalid input detected|Type help or )/;
        return(-1) if (/command authorization failed/i);

        if (!$line++) {
            ProcessHistory("ZEBOSCONF","","","#\n#/config/ZebOS.conf:\n");
        }
        ProcessHistory("ZEBOSCONF","","","# $_") && next;
    }
    return(0);
}

# This routine parses "lsof -n -i :179"
sub ShowZebOSsockets {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($line) = (0);
    print STDERR "    In ShowZebOSsockets: $_" if ($debug);

    while (<$INPUT>) {
        tr/\015//d;
        last if (/^$prompt/);
        next if (/^(\s*|\s*$cmd\s*)$/);
        return(1) if /^\s*\^\s*$/;
        return(1) if /(Invalid input detected|Type help or )/;
        return(-1) if (/command authorization failed/i);

        if (!$line++) {
            ProcessHistory("ZEBOSSOCKETS","","","#\n#lsof -n -i :179:\n");
        }
        ProcessHistory("ZEBOSSOCKETS","","","# $_") && next;
    }
    return(0);
}

# This routine processes a "tmsh -q list"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($lines) = 0;
    print STDERR "    In WriteTerm: $_" if ($debug);

    while (<$INPUT>) {
        tr/\015//d;
        next if (/^\s*$/);

        # Ignore monitor down state, save the config as up.
        s/state down$/state up/i;

        # end of config - hopefully.  f5 does not have a reliable end-of-config
        # tag.
        if (/^$prompt/) {
            $found_end++;
            last;
        }
        return(-1) if (/command authorization failed/i);

        $lines++;

        if (/(bind-pw|encrypted-password|user-password-encrypted|passphrase) / && $filter_pwds >= 1) {
            ProcessHistory("ENABLE","","","# $1 <removed>\n");
            next;
        }
        if (/(auth-password-encrypted) / && 
	    ($filter_osc || $filter_pwds > 1)) {
            ProcessHistory("ENABLE","","","# $1 <removed>\n");
            next;
        }

        # catch anything that wasnt matched above.
        ProcessHistory("","","","$_");
    }

    if ($lines < 3) {
        printf(STDERR "ERROR: $host configuration appears truncated.\n");
        $found_end = 0;
        return(-1);
    }

    return(0);
}

1;
