#!/usr/bin/perl -w

# $Header: /home/cvsroot/NetZ3950/samples/fetch1.pl,v 1.1.1.1 2001/02/12 10:53:55 mike Exp $

use strict;
use Net::Z3950;

my $mgr = new Net::Z3950::Manager(mode => 'async');

my $conn = $mgr->connect('localhost', 9999);
my $check = $mgr->wait();
die "wrong connection" unless $check eq $conn;
die "wrong op (expected init)" unless $conn->op() == Net::Z3950::Op::Init;
# Ignore the Init response

$conn->startSearch('@attr 1=4 kernighan');
$mgr->wait();
die "wrong op (expected search)" unless $conn->op() == Net::Z3950::Op::Search;

my $rs = $conn->resultSet();
my $size = $rs->size();
print "found $size records\n";

my $which = 2;
my $rec = $rs->record($which);
if (!defined $rec) {
    die "real error" if $rs->errcode() != 0;
    # This is most likely the case: record not piggy-backed
    $mgr->wait();
    die "wrong op (expected get)" unless $conn->op() == Net::Z3950::Op::Get;
    $rec = $rs->record($which);
    die "can't fetch record" if !defined $rec;
}

print "record $which is:\n";
print $rec->render();
