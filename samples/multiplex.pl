#!/usr/bin/perl -w

# $Header: /home/cvsroot/NetZ3950/samples/multiplex.pl,v 1.4 2003/11/17 14:29:35 mike Exp $

use Net::Z3950;
use strict;

# Feel free to modify @servers and @searches
my @servers = (['localhost', 9999],
	       ['localhost', 9998]);
my @searches = ('computer', 'data', 'survey');
my %conn2si;

my $mgr = new Net::Z3950::Manager(async => 1);
my @conn;
foreach my $spec (@servers) {
    my($host, $port, $search) = @$spec;
    my $conn = new Net::Z3950::Connection($mgr, $host, $port, \&done_init)
	or die "can't connect: $!";
}

$mgr->wait();
print "finished\n";

sub done_init {
    my($conn, $apdu) = @_;

    print $conn->name(), " - done init\n";
    $conn2si{$conn} = 0;
    $conn->startSearch($searches[0], \&done_search);
}

sub done_search {
    my($conn, $apdu) = @_;

    my $si = $conn2si{$conn};
    my $rs = $conn->resultSet();
    if (!defined $rs) {
	print $conn->name(), " - search failed: ", $conn->errmsg(), "\n";
    } else {
	print $conn->name(), " - search ", $si+1,
	      " found ", $rs->size(), " records\n";
    }
    my $search = $searches[++$conn2si{$conn}];
    if (defined $search) {
	$conn->startSearch($search, \&done_search);
    } else {
	print $conn->name(), " finished!\n";
	### We don't have the method $conn->close();
    }
}

__END__
=11,15,19
<A href="outputm.html">[output]</A>
