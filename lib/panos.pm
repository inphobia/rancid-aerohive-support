package panos;
##
## $Id: panos.pm.in 3928 2018-11-16 18:50:36Z heas $
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
# Amazingly hacked version of Hank's rancid - this one tries to
# deal with Palo Altos
#
#  RANCID - Really Awesome New Cisco confIg Differ
#
#  panos.pm - Palo Alto Networks rancid procedures
#
# 2013-01-05 - fix to put cli pager after scripting-mode is off - doug
#			   hughesd@deshawresearch.com
#

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
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

    # Paloalto buffers commands and prints them twice, once while buffering,
    # and once while executing. It's a bit weird and causes default rancid
    # code a bit of a conniption, so we need to only execute the callbacks
    # on second discovery.

TOP: while(<$INPUT>) {
	tr/\015//d;
	if  (/[>#]\s?exit$/) {
	    $clean_run = 1;
	    print STDERR "exiting\n" if ($debug);
	    # because exit occurs implicitly, too
	    delete($commands{exit});
	    last;
	}
	print STDERR ("line: $_") if ($debug);
	if (/^Error:/) {
	    print STDOUT ("$host panlogin error: $_");
	    print STDERR ("$host panlogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/\w+@\S+[>#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^>]+>)/)[0];
		$prompt =~ s/>/\[#>\]/;
		$prompt =~ s/\(/\\(/;
		$prompt =~ s/\)/\\)/;
		print STDERR ("PROMPT MATCH: $prompt\n") if ($debug);
	    }
	    print STDERR ("HIT COMMAND:$_\n") if ($debug);
	    print STDERR ("COMMAND is: $cmd|$commands{$cmd}\n") if ($debug);
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
    }
}

# This routine parses "show system info"
sub ShowInfo {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($slot);

    print STDERR "    In ShowInfo:: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(time:|uptime:)/);
	next if (/^(app|av|global-protect-datafile|threat|wf-private|wildfire|url-filtering)-(version|release-date):/);

	ProcessHistory("INFO","","","#$_");
    }
    ProcessHistory("INFO","","","#\n");
    return(0);
}

# This routine parses "show chassis inventory"
sub ShowInventory {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($slot);

    print STDERR "    In ShowInventory:: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (/^Invalid syntax/);

	ProcessHistory("INV","","","#$_");
    }
    ProcessHistory("INV","","","#\n");
    return(0);
}

# This routine parses "show config running"
sub ShowConfig {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowConfig: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	if (/^}\s*$|\[edit\]/) {
	    $found_end = 1;
	    return(1);
	}

	ProcessHistory("","","","$_");
	# end of config
    }
    return 0;
}

1;
