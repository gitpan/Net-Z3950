#!/usr/bin/perl -w

# $Header: /home/cvsroot/NetZ3950/samples/multiplex.pl,v 1.1.1.1 2001/02/12 10:53:55 mike Exp $

### this does not work with the current version of the library

use Net::Z3950;
$mgr = new Net::Z3950::Manager(mode => 'async');
my @conn;
foreach $host ('indexdata.dk', 'tecc.co.uk') {
	push @conn, $mgr->connect($host);
}
foreach $conn (@conn) {
	$conn->startSearch('au=kernighan');
}
while ($conn = $mgr->wait()) {
	$op = $conn->op();
	if ($op == Net::Z3950::Op::Error) {
		die "error " . $conn->errcode() .
			"( " . $conn->addinfo() . ")" .
			" in " . $conn->where();
	} elsif ($op == Net::Z3950::Op::Search) {
		$rs = $conn->resultSet();
		$size = $rs->size();
		$rs->startGet(1, $size);
	} elsif ($op == Net::Z3950::Op::Get) {
		foreach $rec ($conn->records()) {
			print $rec->render();
		}
	}
}
