use Net::Z3950;
$conn = new Net::Z3950::Connection('indexdata.dk', 210,
				   databaseName => 'gils')
    or die "can't connect: $!";
$rs = $conn->search('mineral')
    or die $conn->errmsg();
print "found ", $rs->size(), " records:\n";
exit if $rs->size() == 0;
my $rec = $rs->record(1)
    or die $rs->errmsg();
print $rec->render();
