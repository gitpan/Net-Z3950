#!/usr/bin/perl -w

# $Id: scan.pl,v 1.2 2004/05/06 13:06:08 mike Exp $
#
# e.g. run as follows:
#	cd /usr/local/src/z39.50/NetZ3950
#	PERL_DL_NONLAZY=1 /usr/bin/perl "-Iblib/lib" "-Iblib/arch" \
#		samples/scan.pl bagel 210 gils x preferredPositionInResponse 5
# OR gondolin.hist.liv.ac.uk 210 l5r foo stepSize 4

use Net::Z3950;
use strict;

die "Usage: scan.pl <host> <port> <db> <scan-query> [<option> <value>] ...\n"
    unless @ARGV >= 4;
my $host = shift();
my $port = shift();
my $db = shift();
my $scanQuery = shift();
my $mgr = new Net::Z3950::Manager();
while (@ARGV) {
    my $type = shift();
    my $val = shift();
    $mgr->option($type, $val);
}

my $conn = new Net::Z3950::Connection($mgr, $host, $port, databaseName => $db)
    or die "can't connect: ". ($! == -1 ? "init refused" : $!);

# "$sra" means scan-response APDU
my $sra = $conn->scan($scanQuery)
    or die("scan: " . $conn->errmsg(), 
	   defined $conn->addinfo() ? ": " . $conn->addinfo() : "");

my $status = $sra->{scanStatus};
if ($status != 0) {
    print "Scan-status is $status: ";
    if ($status == 6) {
	print "scan failed\n";
	my $diag = $sra->diag();
	my $code = $diag->condition();
	my $addinfo = $diag->addinfo();
	print "error $code: ", Net::Z3950::errstr($code);
	print " ($addinfo)" if $addinfo;
	print "\n";
	exit;
    }
    print "only partial results included\n";
}

my $n = $sra->numberOfEntriesReturned();
my $ss = $sra->stepSize();
my $pos = $sra->positionOfTerm();

print "Scanned $n entries";
print " with step-size $ss" if defined $ss;
print ", position=$pos\n";
for (my $i = 1; $i <= $n; $i++) {
    my $entry = $sra->entries()->[$i-1];
    ### should check for NSD, and for term of type other than general
    print($i == $pos ? "-->" : "", "\t",
	  $entry->termInfo()->term()->general(),
	  " (" . $entry->termInfo()->globalOccurrences() . ")\n");
}

$conn->close();
