package rancid;
##
## $Id: rancid.pm.in 3794 2018-04-09 14:13:28Z heas $
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
#  rancid.pm - base/basic rancid procedures
#

use 5.010;
use strict 'vars';
use warnings;
use 2.006 Socket qw(AF_INET AF_INET6 inet_pton);
require(Exporter);
our @ISA = qw(Exporter);

our $VERSION;
our @commandtable;			# command lists
our %commands;
our @commands;
our $commandcnt;			# number of members in @commandtable
our $commandstr;			# command string for lscript -c
our $cmds_regexp;			# command regex for matching input
our $devtype;				# device type argument
our $filter_commstr;			# SNMP community string filtering
our $filter_osc;			# oscillating data filtering mode
our $filter_pwds;			# password filtering mode
our $aclsort;				# ACL sorting mode
our $aclfilterseq;			# ACL sequence filtering mode
our $log;				# log cmdline option
our $debug;				# debug cmdline option
our $file;				# file cmdline option
our $host;				# hostname from cmdline
our $clean_run;				# successful run
our $found_end;				# found end of the config
our $timeo;				# login script timeout in seconds
our $prompt;				# device prompt regex


use vars qw{$script $lscript @modules};	# script, login script, module name(s)
use vars qw{$inloop}		;	# inloop func
use vars qw{$command $hist_tag};	# ProcessHistory state
use vars qw{%history @history};		# ProcessHistory state
our @EXPORT = qw($VERSION $devtype $script $lscript @modules $inloop
		@commandtable
		%commands @commands $commandcnt
		$commandstr $cmds_regexp
		$filter_commstr $filter_osc $filter_pwds $aclsort $aclfilterseq
		$log $debug $file $host $clean_run $found_end $timeo $prompt
		rancidinit loadtype
		
		ProcessHistory bytes2human diskszsummary human2bytes
		ipsort ipaddrval
		keynsort keysort numerically numsort sortbyipaddr valsort
		RunCommand);

BEGIN {
    $VERSION = '3.9';
}

# initialize common rancid parameters and handle command-line arguments.
sub rancidinit {
    my($i);

    if ($main::opt_V) {
	print "rancid 3.9\n";
	exit(0);
    }

    $command = $hist_tag = "";		# ProcessHistory state
    for (keys(%history)) {
        delete $history{$_};
    }
    @history = ();

    $log = $main::opt_l;
    $debug = $main::opt_d;
    $devtype = $main::opt_t;
    $file = $main::opt_f;
    $host = defined($ARGV[0]) ? $ARGV[0] : "";
    $clean_run = 0;
    $found_end = 0;
    $timeo = 90;			# login script timeout in seconds

    $aclsort = "ipsort";		# ACL sorting mode

    # determine ACL sorting mode
    if (defined($ENV{"ACLSORT"}) && $ENV{"ACLSORT"} =~ /no/i) {
	$aclsort = "";
    }
    if (defined($ENV{"ACLFILTERSEQ"}) && $ENV{"ACLFILTERSEQ"} =~ /no/i) {
	$aclfilterseq = "0";
    } else {
	$aclfilterseq = "1";
    }

    # determine community string filtering mode
    if (defined($ENV{"NOCOMMSTR"}) && $ENV{"NOCOMMSTR"} =~ /yes/i) {
	$filter_commstr = 1;
    } else {
	$filter_commstr = 0;
    }
    # determine oscillating data filtering mode
    if (defined($ENV{"FILTER_OSC"}) && $ENV{"FILTER_OSC"} =~ /no/i) {
	$filter_osc = 0;
    } elsif (defined($ENV{"FILTER_OSC"}) && $ENV{"FILTER_OSC"} =~ /all/i) {
	$filter_osc = 2;
    } else {
	$filter_osc = 1;
    }
    # determine password filtering mode
    if (defined($ENV{"FILTER_PWDS"}) && $ENV{"FILTER_PWDS"} =~ /no/i) {
	$filter_pwds = 0;
    } elsif (defined($ENV{"FILTER_PWDS"}) && $ENV{"FILTER_PWDS"} =~ /all/i) {
	$filter_pwds = 2;
    } else {
	$filter_pwds = 1;
    }

    if (!$main::opt_C && length($host) == 0) {
	if ($main::file) {
	    print(STDERR "Too few arguments: file name required\n");
	    exit(1);
	} else {
	    print(STDERR "Too few arguments: host name required\n");
	    exit(1);
	}
    }

    if (!defined($main::opt_t) || length($main::opt_t) == 0) {
	print(STDERR "Too few arguments: -t option is required\n");
	exit(1);
    }

    # make OUTPUT unbuffered if debugging
    if ($debug) { $| = 1; }

    1;
}

# load rancid device-type spec/info from etc/rancid.types.* config files, then
# load modules & handle -C option, if present.
# usage: loadtype(device_type)
sub loadtype {
    my($devtype) = @_;
    my($file, $line, $matched);

    @commandtable = ();
    $commandcnt = 0;

    if (!defined($devtype) || length($devtype) == 0) {
	print STDERR "loadtype(): device_type is empty\n";
	return 1;
    }
    print STDERR "loadtype: device type $devtype\n" if ($debug);

    # which device type configuration file has the definition of $devtype?
    foreach $file ("/home/testranc/etc/rancid.types.base",
		   "/home/testranc/etc/rancid.types.conf") {
	$line = 0;
	open(INPUT, "< $file") || die "Could not open $file: $!";
	while (<INPUT>) {
	    $line++;
	    chomp;
	    next if (/^\s*$/ || /^\s*#/);
	    my($type, $directive, $value, $value2) = split('\;');
	    $type =~ tr/[A-Z]/[a-z]/;
	    $directive =~ tr/[A-Z]/[a-z]/;

	    next if ($type ne $devtype);
	    if (!$matched) {
		$matched++;
		printf(STDERR "loadtype: found device type %s in %s\n",
		       $devtype, $file) if ($debug);
	    }
	    if ($directive eq "script") {
		$script = $value;
	    } elsif ($directive eq "login") {
		$lscript = $value;
	    } elsif ($directive eq "module") {
		push(@modules, $value);
	    } elsif ($directive eq "inloop") {
		$inloop = $value;
	    } elsif ($directive eq "command") {
		push(@commandtable, {$value2, $value});
	    } elsif ($directive eq "timeout") {
		$timeo = $value;
	    } else {
		printf(STDERR "loadtype: unknown directive %s at %s:%s\n",
		       $directive, $file, $line);
		close(INPUT);
		return(-1);
	    }
	}
	close(INPUT);

	# do not parse rancid.types.conf if we found any device type matches
	# in rancid.types.base.
	last if ($matched);
    }

    # load device-type specific modules
    if (length($#modules)) {
	my($module);

	foreach $module (@modules) {
	eval {
	    (my $file = $module) =~ s/::/\//g;
	    require $file . '.pm';
	    # call module->import(); we expect 0 as success, as god intended it
	    # XXX how the fuck is this done w/o the eval and w/o a temp var?
	    eval($module ."::import();") ? 0 : 1;
	} or do {
	    # Module load failed
	    my($error) = $@;
	    print STDERR "loadtype: loading $module failed: ".
			 "$error\n";
	    return(-1);
	};
	}
    }

    # Use an array to preserve the order of the commands and a hash for mapping
    # commands to the subroutine and track commands that have been completed.
    @commands = map(keys(%$_), @commandtable);
    %commands = map(%$_, @commandtable);
    $commandcnt = scalar(keys(%commands));

    $commandstr = join(";", @commands);
    $cmds_regexp = join("|", map quotemeta($_), @commands);

    # check that the functions exist
    if ($commandcnt) {
	my($func);
	foreach $func (values(%commands)) {
	    if (! defined(&{$func})) {
		printf(STDERR "loadtype: undefined function in %s: %s\n",
		       $devtype, $func);
		close(INPUT);
		return(-1);
	    }
	}
    }

    if ($main::opt_C) {
	my($cmd);
	if (!defined($lscript)) {
	    printf(STDERR "$devtype: login script not defined\n");
	    exit(1);
	}
	$cmd = $lscript;
	if (defined($timeo)) {
	    $cmd .= " -t $timeo";
	}
	print "$cmd -c \'$commandstr\' $host\n";
	exit(0);
    }

    0;
}

# This routine is used to print out the router configuration.  Each line is
# fed to ProcessHistory([tag], [output/sort func], [func argument], line/string)
# which outputs the line/strings if there is no tag or sort function, else it
# accumulates the lines/strings until either the optional tag changes or the
# optional output function changes.
sub ProcessHistory {
    my($new_hist_tag, $new_command, $command_string, @string) = (@_);

    if ((($new_hist_tag ne $hist_tag) || ($new_command ne $command))
	&& scalar(%history)) {
	print eval "$command \%history";
	undef %history;
    }
    if (($new_hist_tag) && ($new_command) && ($command_string)) {
	if ($history{$command_string}) {
	    $history{$command_string} = "$history{$command_string}@string";
	} else {
	    $history{$command_string} = "@string";
	}
    } elsif (($new_hist_tag) && ($new_command)) {
	$history{++$#history} = "@string";
    } else {
	print "@string";
    }
    $hist_tag = $new_hist_tag;
    $command = $new_command;

    1;
}

# convert bytes to human-readable format (ie GB/MB/KB/etc)
sub bytes2human {
    my($cnt) = @_;

    if ($cnt >= (1024 * 1024 * 1024)) {
	$cnt = int($cnt / (1024 * 1024 * 1024));
	return("$cnt GB");
    } elsif ($cnt >= (1024 * 1024)) {
	$cnt = int($cnt / (1024 * 1024));
	return("$cnt MB");
    } elsif ($cnt >= (1024)) {
	$cnt = int($cnt / 1024);
	return("$cnt KB");
    } elsif ($cnt > 0) {
	return("<1KB");
    } else {
	return("0 KB");
    }
}

# summarize total flash/disk space as human-readable form and remaining space
# as a percentage.  unknown variables should be 'undef'.  returns a string,
# without a trailing <CR>.
sub diskszsummary {
    my($total, $free, $used) = @_;
    my($pcnt);

    # remove commas
    $total = human2bytes($total) if (defined($total));
    $free = human2bytes($free) if (defined($free));
    $used = human2bytes($used) if (defined($used));

    if (defined($free)) {
	$pcnt = int($free / $total * 100);
    } elsif (defined($used)) {
	$pcnt = int(($total - $used) / $total * 100);
    } else {
	$total = $free + $used;
	$pcnt = int($free / $total * 100);
    }

    $total = bytes2human($total);

    return("$total total ($pcnt% free)");
}

# convert human-readable format (like "300,024 GB/MB/KB/etc") to bytes
sub human2bytes {
    my($cnt) = @_;
    my($mp);

    $cnt =~ s/,//g;

    if ($cnt =~ /gb/i) {
	$mp = 1024 * 1024 * 1024;
    } elsif ($cnt =~ /mb/i) {
	$mp = 1024 * 1024;
    } elsif ($cnt =~ /kb/i) {
	$mp = 1024;
    } else {
	$mp = 1;
    }
    $cnt =~ /(\d+)/;
    return($1 * $mp);
}

sub numerically { $a <=> $b; }

# keynsort(%hash) is a sort routine that will sort numerically on the
# keys of the hash as if it were a normal array.
sub keynsort {
    my(%lines) = @_;
    my($i) = 0;
    my($key, @sorted_lines);
    foreach $key (sort numerically keys(%lines)) {
	$sorted_lines[$i++] = $lines{$key};
    }
    @sorted_lines;
}

# keysort(%hash) is a sort routine that will sort alpha-numerically on the
# keys of the hash as if it were a normal array.
sub keysort {
    my(%lines) = @_;
    my($i) = 0;
    my($key, @sorted_lines);
    foreach $key (sort keys(%lines)) {
	$sorted_lines[$i++] = $lines{$key};
    }
    @sorted_lines;
}

# valsort(%hash) is a sort routine that will sort on the values of the hash
# as if it were a normal array.
sub valsort {
    my(%lines) = @_;
    my($i) = 0;
    my($key, @sorted_lines);
    foreach $key (sort values(%lines)) {
	$sorted_lines[$i++] = $key;
    }
    @sorted_lines;
}

# numsort(%hash) is a numerical sort routine (ascending).
sub numsort {
    my(%lines) = @_;
    my($i) = 0;
    my($num, @sorted_lines);
    foreach $num (sort {$a <=> $b} keys(%lines)) {
	$sorted_lines[$i++] = $lines{$num};
    }
    @sorted_lines;
}

# ipsort(%hash) is a sort routine that will sort on the IPv4/v6 address keys
# of the hash as if it were a normal array.
sub ipsort {
    my(%lines) = @_;
    my($i) = 0;
    my($addr, @sorted_lines);
    foreach $addr (sort sortbyipaddr keys(%lines)) {
	$sorted_lines[$i++] = $lines{$addr};
    }
    @sorted_lines;
}

# ipaddrval(IPaddr) converts and IPv4/v6 address to a string for comparison.
# Some may ask why not use Net::IP; performance.  We tried and it was horribly
# slow.
sub ipaddrval {
    my($a) = @_;
    my($norder);

    if ($a =~ /:/) {
	my($l);
	($a, $l) = split(/\//, $a);
	if (!defined($l)) {
	    $l = 128;
	}
	$norder = inet_pton(AF_INET6, $a);
	if (defined($norder)) {
	    return unpack("H*", $norder) . unpack("H*", pack("C", $l));
	}
    } else {
	my($l);
	($a, $l) = split(/\//, $a);
	if (!defined($l)) {
	    $l = 32;
	}
	$norder = inet_pton(AF_INET, $a);
	if (defined($norder)) {
	    return(unpack("H*", $norder) . unpack("H*", pack("C", $l)));
	}
    }

    # otherwise return the original key value, so as not to sort on null
    return($_[0]);
}

# sortbyipaddr(IPaddr, IPaddr) compares two IPv4/v6 addresses like strcmp().
sub sortbyipaddr {
    &ipaddrval($a) cmp &ipaddrval($b);
}

# This routine parses a single command that returns no required info.  The
# output is discarded.
sub RunCommand {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In RunCommand: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
    }
    return(0);
}

1;
