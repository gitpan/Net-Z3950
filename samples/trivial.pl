use Net::Z3950;
$conn = new Net::Z3950::Connection('indexdata.dk', 210,
				   databaseName => 'gils');
$rs = $conn->search('mineral');
print "found ", $rs->size(), " records:\n";
my $rec = $rs->record(1);
print $rec->render();
