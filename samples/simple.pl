#!/usr/bin/perl -w

# $Header: /home/cvsroot/perlZ3950/samples/simple.pl,v 1.4 2000/10/06 10:01:03 mike Exp $

use Net::Z3950;

die 'Usage: simple.pl <host> <port> <db> <@prefix-search>' unless @ARGV == 4;
$conn = new Net::Z3950::Connection($ARGV[0], $ARGV[1],
				   databaseName => $ARGV[2]);
$rs = $conn->search($ARGV[3])
    or die $conn->errmsg() . " (" . $conn->addinfo() . ")";

my $n = $rs->size();
print "found $n records:\n";

for (my $i = 0; $i < $n; $i++) {
    my $rec = $rs->record($i+1);
    if (!defined $rec) {
	print STDERR "record", $i+1, ": error #", $rs->errcode(),
	    " (", Net::Z3950::errstr($rs->errcode()), "): ",
	    $rs->addinfo(), "\n";
    }
    print "=== record ", $i+1, " ===\n", $rec->render();
}
