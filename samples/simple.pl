#!/usr/bin/perl -w

# $Header: /home/cvsroot/NetZ3950/samples/simple.pl,v 1.8 2003/05/02 09:17:36 mike Exp $

use Net::Z3950;
use strict;

die "Usage: simple.pl <host> <port> <db> <\@query> [<option> <value>] ...\n"
    unless @ARGV >= 4;
my $host = shift();
my $port = shift();
my $db = shift();
my $query = shift();
my $mgr = new Net::Z3950::Manager();
$mgr->option(preferredRecordSyntax => Net::Z3950::RecordSyntax::USMARC);
while (@ARGV) {
    my $type = shift();
    my $val = shift();
    $mgr->option($type, $val);
}

my $conn = new Net::Z3950::Connection($mgr, $host, $port, databaseName => $db)
    or die "can't connect: $!";

my $rs = $conn->search($query)
    or die $conn->errmsg();

my $n = $rs->size();
print "found $n records:\n";

for (my $i = 0; $i < $n; $i++) {
    my $rec = $rs->record($i+1);
    if (!defined $rec) {
	print STDERR "record ", $i+1, ": error #", $rs->errcode(),
	    " (", $rs->errmsg(), "): ", $rs->addinfo(), "\n";
	next;
    }
    print "=== record ", $i+1, " ===\n", $rec->render();
}
