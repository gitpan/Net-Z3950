# $Header: /home/cvsroot/perlZ3950/Z3950/ResultSet.pm,v 1.3 2000/10/06 10:01:03 mike Exp $

package Net::Z3950::ResultSet;
use strict;


=head1 NAME

Net::Z3950::ResultSet - result set received in response to a Z39.50 search

=head1 SYNOPSIS

	if ($conn->op() == Net::Z3950::Op::Search) {
		$rs = $conn->resultSet();
		$size = $rs->size();

=head1 DESCRIPTION

A ResultSet object represents the set of records found by a Z39.50
server in response to a search.  At any given time, none, some or all
of the records may have been physcially transferred to the client; a
cache is maintained.

Note that there is no constructor for this class (or at least, none
that I'm going to tell you about :-)  ResultSet objects are always
created by the Net::Z3950 module itself, and are returned to the caller
via the C<Net::Z3950::Connection> class's C<resultSet()> method.

=head1 METHODS

=cut


# Private enumeration for non-reference values of slots in the
# $this->{records} array.  The slot contains a record reference if we
# have the record (either because it was piggy-backed in the initial
# search response, or because we've subsequently got it in a present
# response); and it's undefined or not there at all (off the end of the
# array) if we don't have it, and it's not been requested yet):
sub CALLER_REQUESTED { 1 }	# caller asked for it
sub RS_REQUESTED { 2 }		# ... and we've issued a Present request
# We use the slots in $this->{records} corresponding to 1-based record
# numbers; that is, slot zero is not used at all.
#
#   ###	Bugger!  This cache doesn't make a distinction between fetches
#	with different element-sets, so that if you ask for a "b"
#	record, then ask for the full version, this code will just
#	give you its cached brief record again.

# PRIVATE to the Net::Z3950::Connection class's _dispatch() method
sub _new {
    my $class = shift();
    my($conn, $rsName, $searchResponse) = @_;

    if (!$searchResponse->searchStatus()) {
	# Search failed: set $conn's error indicators and return undef
	my $records = $searchResponse->records()
	    or die "no diagnostics";
	ref $records eq 'Net::Z3950::APDU::DefaultDiagFormat'
	    or die "non-default diagnostic format";
	### $rec->diagnosticSetId() is not used
	$conn->{errcode} = $records->condition();
	$conn->{addinfo} = $records->addinfo();
	return undef;
    }

    my $this = bless {
	conn => $conn,
	rsName => $rsName,
	searchResponse => $searchResponse,
	records => [],
    }, $class;

    ### Should check presentStatus
    my $rawrecs = $searchResponse->records();
    $this->_insert_records($searchResponse, 1, 1)
	if defined $rawrecs;

    return $this;
}


=head2 size()

	$nrecords = $rs->size();

Returns the number of records in the result set I<$rs>

=cut

sub size {
    my $this = shift();

    return $this->{searchResponse}->resultCount();
}


=head2 record()

	$rec = $rs->record($n);

Returns a reference to I<$n>th record in the result set I<$rs>, if the
content of that record is known.  Valid values of I<$n> range from 1
to the return value of the C<size()> method.

If the record is not available, an undefined value is returned, and
diagnostic information made available via I<$rs>'s C<errcode()> and
C<addinfo()> methods.

As a special case, when the connection is anychronous, the
C<errcode()> may be zero, indicating simply that the record has not
yet been fetched from the server.  In this case, the calling code
should try again later.  (How much later?  As a rule of thumb, after
it's done ``something else'', such as request another record or issue
another search.)  This can never happen in synchronous mode.

=cut

sub record {
    my $this = shift();
    my($which) = @_;

    my $records = $this->{records};
    my $rec = $records->[$which];

    if (ref $rec && $rec->isa('Net::Z3950::APDU::DefaultDiagFormat')) {
	# Set error information from record into the result set
	### $rec->diagnosticSetId() is not used
	$this->{errcode} = $rec->condition();
	$this->{addinfo} = $rec->addinfo();
	return undef;
    } elsif (ref $rec) {
	# We have it, and it's presumably a legitmate record
	return $rec;
    }

    # Record is not yet in place
    if (!defined $rec) {
	# It hasn't even been requested: mark for Present-request
	$records->[$which] = CALLER_REQUESTED;
	$this->{conn}->{idleWatcher}->start();
    }

    if ($this->option('mode') ne 'sync') {
	$this->{errcode} = 0;
	return undef;
    }

    # Synchronous-mode request for a record that we don't yet have: we
    # need to wait for it to arrive, then return it.  The remainder of
    # this code is lifted and modified from Net::Connection::search()
    # which suggests there should be an underlying abstraction?  All
    # of this would work better with callbacks.
    #
    my $xconn = $this->{conn};
    my $conn = $xconn->manager()->wait();
    if ($conn != $xconn) {
	#   ###	We would prefer just to ignore any events on
	#	connections other than this one, but there doesn't
	#	seem to be a way to do this (unless we invent one);
	#	so, for now, you shouldn't mix synchronous and
	#	asynchronous calls unless the async ones nominate a
	#	callback (which they can't yet do)
	die "single-plexing wait() returned wrong connection!";
    }

    if ($conn->op == Net::Z3950::Op::Error) {
	# Error code and addinfo are in $conn: copy them across
	$this->{errcode} = $conn->{errcode};
	$this->{addinfo} = $conn->{addinfo};
	return undef;
    }

    if ($conn->op() != Net::Z3950::Op::Get) {
	#   ###	Again, we'd like to ignore this event, but there's no
	#	way to do it, so this has to be a fatal error.
	die "single-plexing wait() fired wrong op (expected get)";
    }

    ### We should check that the presentResponse was to this
    #	particular present response, but then we only get here if
    #	we're in synchronous mode, so I think it's a "can't happen".

    # OK, the callback invoked by the event loop should now have
    # inserted the requested record into out array, so we should just
    # be able to return it.  Sanity-check first, though.
    die "impossible: didn;t get record" if !defined$records->[$which];
    return $this->record(@_);
}


# PRIVATE to the Net::Z3950::Connection module's new() method, invoked as
# an Event->idle callback
sub _idle {
    my($event) = @_;
    my $watcher = $event->w();
    my $conn = $watcher->data();

    foreach my $rs ($conn->resultSets()) {
	next if !$rs;		# a pending slot, awaiting search response
	$rs->_checkRequired();
    }

    # Don't fire again until more records are requested
    $watcher->stop();
}


# PRIVATE to the _request_records() method
sub _checkRequired {
    my $this = shift();

    my $records = $this->{records};
    my $n = @$records;

    ###	If our interface to the C function makePresentRequest allowed
    #	us to generate multiple ranges (using the Present Request
    #	APDU's additionalRange parameter), we could consider using
    #	that and making a single big present request instead of
    #	(potentially) several little ones; but it's slightly tricky to
    #	do, and it's not clear that it would be more efficient, so
    #	let's not lose any sleep over it for now.

    my($first, $howmany);
    for (my $i = 1; $i <= $n; $i++) {
	my $rec = $records->[$i];
	if (!defined $first) {
	    # We've not yet seen a record we want to fetch
	    if (defined $rec && $rec == CALLER_REQUESTED) {
		# ... but now we have!  Start a new range
		$first = $i;
		$records->[$i] = RS_REQUESTED;
	    }
	} else {
	    # We're already gathering a range
	    if (defined $rec && $rec == CALLER_REQUESTED) {
		# Range continues: mark that we're requesting this record
		$records->[$i] = RS_REQUESTED;
	    } else {
		# This record is one past the end of the range we want
		$howmany = $i-$first;
		$this->_send_presentRequest($first, $i-$first);
		$first = undef;	# prepare for next range
	    }
	}
    }
}


# PRIVATE to the _checkRequired() method
#
#   ###	Instead of sending these out immediately, we should put them
#	on a queue to be sent out when the connection is quiet (which
#	may be immediately): in this way we work with broken (but
#	compliant!) servers which may throw away anything after the
#	first APDU in their connection's input queue.  In Real Life,
#	the current version will Nearly Always(tm) work, but this is a
#	good place to look if we get bug reports in this area.
#
sub _send_presentRequest {
    my $this = shift();
    my($first, $howmany) = @_;

    my $refId = _bind_refId($this->{rsName}, $first, $howmany);
    my $pr = Net::Z3950::makePresentRequest($refId,
				       $this->{rsName},
				       $first, $howmany,
				       $this->option('elementSetName'),
				       $this->option('preferredRecordSyntax'));
    die "can't make present request" if !defined $pr;
    $this->{conn}->_enqueue($pr);
}


# PRIVATE to the Net::Z3950::Connection class's _dispatch() method
sub _add_records {
    my $this = shift();
    my($presentResponse) = @_;

    my($rsName, $first, $howmany) =
	_unbind_refId($presentResponse->referenceId());
    ### Should check presentStatus
    my $n = $presentResponse->numberOfRecordsReturned();

    # Sanity checks
    if ($rsName ne $this->{rsName}) {
	die "rs '" . $this->{rsName} . "' was sent records for '$rsName'";
    }
    if ($n > $howmany) {
	die "rs '$rsName' got $n records but only asked for $howmany";
    }

    if ($this->_insert_records($presentResponse, $first, $howmany)) {
	my $records = $this->{records};
	for (my $i = $n; $i < $howmany; $i++) {
	    # We asked for this record but didn't get it, for whatever
	    # reason.  Mark the record down to "requested by the user
	    # but no present request outstanding" so that it gets
	    # requested again.
	    ###	This might not always be The Right Thing -- if the
	    #	error is a permanent one, we'll end up looping, asking
	    #	for it again and again.  We could further overload the
	    #	meaning of numbers in the $this->{records} array to
	    #	count how many times we've tried, and bomb out after
	    #	"too many" tries.
	    $this->_check_slot($records->[$first+$i], $first+$i);
	    $records->[$first+$i] = CALLER_REQUESTED;
	}
    }

    if ($n < $howmany) {
	# We're missing at least one record, which we've marked
	# CALLER_REQUESTED; restart the idle watcher so it issues a
	# new present request at an appropriate point.
	$this->{conn}->{idleWatcher}->start();
    }
}


# PRIVATE to the _new() and _add_record() methods
sub _insert_records {
    my $this = shift();
    my($apdu, $first, $howmany) = @_;
    # $first is 1-based; $howmany is used only when storing NSDs.

    my $records = $this->{records};
    my $rawrecs = $apdu->records();
    if ($rawrecs->isa('Net::Z3950::APDU::DefaultDiagFormat')) {
	# Now what?  We want to report the error back to the caller,
	# but we got here from a callback from the event loop, and
	# we're now miles away from any notional "flow of control"
	# where we could pop up with an error.  Instead, we lodge a
	# copy of this error in the slots for each record requested,
	# so that when the caller invokes records(), we can arrange
	# that we set appropriate error information.
	for (my $i = 0; $i < $howmany; $i++) {
	    $records->[$first+$i] = $rawrecs;
	}
	return 0;
    }

    {
	#   ###	Should deal more gracefully with multiple
	#	non-surrogate diagnostics (Z_Records_multipleNSD)
	my $type = 'Net::Z3950::APDU::NamePlusRecordList';
	if (!$rawrecs->isa($type)) {
	    die "expected $type, got " . ref($rawrecs);
	}
    }

    my $n = @$rawrecs;
    for (my $i = 0; $i < $n; $i++) {
	$this->_check_slot($records->[$first+$i], $first+$i)
	    if $first > 1;		# > 1 => it's a present response

	my $record = $rawrecs->[$i];
	{
	    # Merely a redundant sanity check
	    my $type = 'Net::Z3950::APDU::NamePlusRecord';
	    if (!$record->isa($type)) {
		die "expected $type, got " . ref($record);
	    }
	}

	### We're ignoring databaseName -- do we have any use for it?
	my $which = $record->which();
	{
	    ### Should deal more gracefully with surrogate
	    #	diagnostics, not to mention segmentation fragments
	    my $type = Net::Z3950::NamePlusRecord::DatabaseRecord;
	    if ($which != $type) {
		die "expected $type, got $which";
	    }
	}

	$records->[$first+$i] = $record->databaseRecord();
    }

    return 1;
}


# PRIVATE to the _add_records() and _insert_records() methods
sub _check_slot {
    my $this = shift();
    my($rec, $which) = @_;

    die "re-fetching a record that's already had an error"
	if ref $rec && $rec->isa('Net::Z3950::APDU::DefaultDiagFormat');
    die "presented record $rec already loaded"
	if ref $rec;
    die "server was never asked for presented record"
	if $rec == CALLER_REQUESTED;
    die "user never asked for presented record"
	if !defined $rec;
    die "record is defined but false, which is impossible"
	if !$rec;
    die "weird slot-value $rec"
	if $rec != RS_REQUESTED;
}


# PRIVATE to the _send_presentRequest() and _add_records() methods
#
# These functions encapsulate the scheme used for binding a result-set
# name, the first record requested and the number of records requested
# into a single opaque string, which we then use as a reference Id so
# that it gets passed back to us when the present response arrives
# (otherwise there's no way to know from the response what we asked
# for, and therefore where in the result set to insert the records.)
#
sub _bind_refId {
    my($rsName, $first, $howmany) = @_;
    return $rsName . '-' . $first . '-' . $howmany;
}

sub _unbind_refId {
    my($refId) = @_;
    $refId =~ /(.*)-(.*)-(.*)/;
    return ($1, $2, $3);
}


#   ###	The following records() method is a simplifying interface for
#	synchronous applications; there should be a similarly
#	synchronous interface for fetching single records; or perhaps
#	that's what record() should do if the connection is
#	synchronous.


=head2 records()

	@records = $rs->records();
	foreach $rec (@records) {
	    print $rec->render();
	}

This utility method returns a list of all the records in the result
set I$<rs>.  Because Perl arrays are indexed from zero, the first
record is C<$records[0]>, the second is C<$records[1]>, I<etc.>

If not all the records associated with I<$rs> have yet been
transferred from the server, then they need to be transferred at this
point.  This means that the C<records()> method may block, and so is
not recommended for use in applications that interact with multiple
servers simultaneously.  It does also have the side-effect that
subsequent invocations of the C<record()> method will always
immediately return either a legitimate record or a ``real error''
rather than a ``not yet'' indicator.

If an error occurs, an empty list is returned.  Since this is also
what's returned when the search had zero hits, well-behaved
applications will consult C<$rs->size()> in these circumstances to
determine which of these two conditions pertains.  After an error has
occurred, details may be obtained via the result set's C<errcode()>
and C<addinfo()> methods.

If a non-empty list is returned, then individual elements of that list
may still be undefined, indicating that corresponding record could not
be fetched.  In order to get more information, it's necessary to
attempt to fetch the record using the C<record()> method, then consult
the C<errcode()> and C<addinfo()> methods.

B<Unwarranted personal opinion>: all in all, this method is a pleasant
short-cut for trivial programs to use, but probably carries too many
caveats to be used extensively in serious applications.

=cut

#   ###	We'd like to do this by just returning $rs->{records} of
#	course, but we can't do that because (A) it's 1-based, and (B)
#	we need undefined slots where errors occur rather than
#	error-information APDUs.  So we make a copy.
#
#   ###	It would be nice to come up with some cuter logic for when we
#	can fall out of our calling-wait()-to-get-more-records loop,
#	but for now, the trivial keep-going-till-we-have-them-all
#	approach is adequate.
#
sub records {
    my $this = shift();

    my $size = $this->size();
    my $records = $this->{records};

    # Issue requests for any records not already available or requested.
    for (my $i = 0; $i < $size; $i++) {
	if (!defined $records->[$i+1]) {
	    $this->record($i+1); # discard result
	}
    }

    # Wait until all the records are in (or at least errors)
    while (1) {
	my $done = 1;
	for (my $i = 0; $i < $size; $i++) {
	    if (!ref $records->[$i+1]) {
		$done = 0;
		last;
	    }
	}
	last if $done;

	# OK, we have at least one slot in $records which is not a
	# reference either to a legitimate record or to an error
	# APDU, so we need to wait for another server response.
	my $conn = $this->{conn};
	my $c2 = $conn->manager()->wait();
	die "wait() yielded wrong connection"
	    if $c2 ne $conn;
    }

    my @res;
    for (my $i = 0; $i < $size; $i++) {
	my $tmp = $this->record($i+1);
	$res[$i] = $tmp;
    }

    return @res;
}


=head2 errcode(), addinfo()

	if (!defined $rs->record($n)) {
		print "error number: ", $rs->errcode(), "\n";
		print "additional info: ", $rs->errcode(), "\n";
	}

When a result set's C<record()> method returns an undefined value,
indicating an error, it also sets into the result set the BIB-1 error
code and additional information returned by the server.  They can be
retrieved via the C<errcode()> and C<addinfo()> methods.

=cut

sub errcode {
    my $this = shift();
    return $this->{errcode};
}

sub addinfo {
    my $this = shift();
    return $this->{addinfo};
}


=head2 option()

	$value = $rs->option($type);
	$value = $rs->option($type, $newval);

Returns I<$rs>'s value of the standard option I<$type>, as registered
in I<$rs> itself, in the connection across which it was created, in
the manager which controls that connection, or in the global defaults.

If I<$newval> is specified, then it is set as the new value of that
option in I<$rs>, and the option's old value is returned.

=cut

sub option {
    my $this = shift();
    my($type, $newval) = @_;

    my $value = $this->{options}->{$type};
    if (!defined $value) {
	$value = $this->{conn}->option($type);
    }
    if (defined $newval) {
	$this->{options}->{$type} = $newval;
    }
    return $value
}


=head1 AUTHOR

Mike Taylor E<lt>mike@tecc.co.ukE<gt>

First version Sunday 28th May 2000.

=cut

1;
