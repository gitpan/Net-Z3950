# $Header: /home/cvsroot/NetZ3950/Z3950/Connection.pm,v 1.6 2002/02/08 17:41:20 mike Exp $

package Net::Z3950::Connection;
use IO::Handle;
use Event;
use Errno qw(ECONNREFUSED);
use strict;


=head1 NAME

Net::Z3950::Connection - Connection to a Z39.50 server, with request queue

=head1 SYNOPSIS

	$conn = new Net::Z3950::Connection($hostname, $port);
	$rs = $conn->search('au=kernighan and su=unix');
	# or
	$mgr = $conn->manager();
	$conn = $mgr->wait();
	if ($mgr->failed()) {
		die "error " . $conn->errcode() .
			"( " . $conn->addinfo() . ")" .
			" in " . Net::Z3950::opstr($conn->errop());
	}

=head1 DESCRIPTION

A connection object represents an established connection to a
particular server on a particular port, together with options such as
the default database in which to search.  It maintains a queue of
outstanding requests (searches executed against it, fetches executed
against result sets instantiated against it) I<etc.>

=head1 METHODS

=cut


=head2 new()

	$conn = new Net::Z3950::Connection($mgr, $host, $port);

Creates and returns a new connection, under the control of the manager
I<$mgr>, to the server on the specified I<$host> and I<$port>.  If the
I<$port> argument is omitted, the C<z3950> service is used; if this is
not defined, port 210 is used.

The manager argument may be omitted, in which
case, the connection is created under the control of a
``default manager'', a reference to which may be subsequently
retrieved with the C<manager()> method.  Multiple connections made
with no explicitly-specified manager in this way will all share the
same implicit manager.  The default manager is initially in
synchronous mode.

If the connection is created in synchronous mode, (or, if the
constructor call doesn't specify a mode, if the manager controlling
the new connection is synchronous), then the constructor does not
return until either the connection is forged or an error occurs in
trying to do so.  (In the latter case, error information is stored in
the manager structure.)  If the connection is asynchronous, then the
new object is created and returned before the connection is forged;
this will happen in parallel with subsequent actions.

I<This is a lie: connecting is always done synchronously.>

Any of the standard options (including synchronous or asynchronous
mode) may be specified as additional arguments.  Specifically:

	$conn = new Net::Z3950::Connection($mgr, $host, $port, mode => 'async');

Works as expected.

=cut

# PRIVATE to the new() method
use vars qw($_default_manager);

sub new {
    my $class = shift();
    my $mgr = shift();
    my($host, $port);

    # Explicit manager-reference is optional: was it supplied?
    if (ref $mgr) {
	$host = shift();
	$port = shift();
    } else {
	$host = $mgr;
	$port = shift();
	$mgr = undef;
    }
    $port ||= getservbyname('z3950', 'tcp') || 210;
    my $addr = "$host:$port";

    if (!defined $mgr) {
	# Manager either explicitly undefined or not supplied: use the
	# default global manager -- if it doesn't exist yet, make it.
	if (!defined $_default_manager) {
	    $_default_manager = new Net::Z3950::Manager()
		or die "can't create default manager";
	}

	$mgr = $_default_manager;
    }

    my $cb;
    $cb = shift() if ref $_[0] eq 'CODE';

    my $this = bless {
	mgr => $mgr,
	host => $host,
	port => $port,
	resultSets => [],
	options => { @_ },
	refId2cb => {},		# maps reference IDs to callback functions
    }, $class;

    ###	It would be nice if we could find a way to do the DNS lookups
    #	asynchronously, but even the major web browsers don't do it,
    #	so either (A) it's hard, or (B) they're lazy.  Oh, or (C) of
    #	course.
    #
    my $cs = Net::Z3950::yaz_connect($addr)
	or return undef;	# caller should consult $!

    $this->{cs} = $cs;
    my $fd = Net::Z3950::yaz_socket($cs);
    my $sock = new_from_fd IO::Handle($fd, "r+")
	or die "can't make IO::Handle out of file descriptor";
    $this->{sock} = $sock;

    Event->io(fd => $sock, poll => 'r', data => $this, cb => \&_ready_to_read,
	      debug => 5)
	or die "can't make read-watcher on socket to $addr";
    $this->{writeWatcher} = Event->io(fd => $sock, poll => 'w', data => $this,
				      parked => 1, cb => \&_ready_to_write,
				      debug => 5)
	or die "can't make write-watcher on socket to $addr";

    # Arrange to have result-sets on this connection ask for extra records
    $this->{idleWatcher} = Event->idle(data => $this, repeat => 1, parked => 1,
				       cb => \&Net::Z3950::ResultSet::_idle,
				       debug => 5)
	or die "can't make idle-watcher on socket to $addr";

    # Generate the INIT request and queue it up for subsequent dispatch
    my $errmsg = '';
    my $ir = Net::Z3950::makeInitRequest('init',
				    $this->option('preferredMessageSize'),
				    $this->option('maximumRecordSize'),
				    $this->option('user'),
				    $this->option('password'),
				    $this->option('groupid'),
				    $this->option('implementationId'),
				    $this->option('implementationName'),
				    $this->option('implementationVersion'),
				    $errmsg);
    die "can't make init request: $errmsg" if !defined $ir;

    $this->_enqueue($ir);
    $this->{refId2cb}->{'init'} = $cb if defined $cb;
    $mgr->_register($this);

    if ($this->option('mode') ne 'async') {
	$this->expect(Net::Z3950::Op::Init, "init")
	    or return undef;	# e.g. ECONNREFUSED
    }

    return $this;
}


# PRIVATE to the new() method, invoked as an Event->io callback
#
# So far as I can tell from the Event.pm documentation, and a cursory
# reading of the rather opaque source code, it appears that the return
# value of callbacks such as this one is ignored.
#
sub _ready_to_read {
    my($event) = @_;
    my $watcher = $event->w();
    my $conn = $watcher->data();
    my $addr = $conn->{host} . ":" . $conn->{port};

    my $reason = 0;		# We need to give $reason a value to
				# avoid a spurious "uninitialized"
				# warning on the next line, even
				# though $result is a pure-result
				# parameter to decodeAPDU()
    my $apdu = Net::Z3950::decodeAPDU($conn->{cs}, $reason);
    if (defined $apdu) {
	my $refId = $conn->_dispatch($apdu);
	if (!defined $refId) {
	    # Unrecognised APDU -- nothing useful to do here, unless
	    # we think die()ing might be helpful?
	    return;
	}

	my $cb = $conn->{refId2cb}->{$refId};
	#warn ref($apdu). ": refId='$refId', cb='$cb'";
	if (defined $cb) {
	    # Application-level callback provided by caller
	    &$cb($conn, $apdu);
	} else {
	    Event::unloop($conn);
	}
	return;
    }

    if ($reason == Net::Z3950::Reason::EOF) {
	print "[$addr] EOF from server (server closed connection?)\n";
	$watcher->cancel();

    } elsif ($reason == Net::Z3950::Reason::Incomplete) {
	# Some bytes have been read into the COMSTACK (which maintains
	# its own state), but not enough yet to make a whole APDU.  We
	# have nothing to do here -- just return to the event loop and
	# wait until we get called again with the next chunk.

    } elsif ($reason == Net::Z3950::Reason::Malformed) {
	print "[$addr] malformed APDU (server doesn't speak Z39.50?)\n";
	$watcher->cancel();	

    } elsif ($reason == Net::Z3950::Reason::BadAPDU) {
	print "[$addr] unrecognised APDU: never mind\n";
	# No need to shut down the connection: it's probably our fault.

    } elsif ($reason == Net::Z3950::Reason::Error) {
	print "[$addr] system error ($!)\n";
	$watcher->cancel();

    } else {
	# Should be impossible
	print "decodeAPDU() failed for unknown reason: $reason\n";
    }
}


# PRIVATE to the _ready_to_read() function
#
# Return referenceId of returned APDU or undef if unsupported.
#
sub _dispatch {
    my $this = shift();
    my($apdu) = @_;

    if ($apdu->isa('Net::Z3950::APDU::InitResponse')) {
	$this->{op} = Net::Z3950::Op::Init;
	$this->{initResponse} = $apdu;
	return $apdu->referenceId();

    } elsif ($apdu->isa('Net::Z3950::APDU::SearchResponse')) {
	$this->{op} = Net::Z3950::Op::Search;
	$this->{searchResponse} = $apdu;
	my $which = $apdu->referenceId();
	defined $which or die "no reference Id in search response";
	my $rs = $this->{resultSets}->[$which]
	    and die "reference to exisiting result set";
	$rs = _new Net::Z3950::ResultSet($this, $which, $apdu);
	$this->{resultSets}->[$which] = $rs;
	$this->{resultSet} = $rs;
	return $which;

    } elsif ($apdu->isa('Net::Z3950::APDU::PresentResponse')) {
	$this->{op} = Net::Z3950::Op::Get;
	$this->{presentResponse} = $apdu;
	# refId is of the form <rsindexex-junk>
	my $which = $apdu->referenceId();
	defined $which or die "no reference Id in present response";
	# Extract initial portion, local result-set index, from refId
	$which =~ s/-.*//;
	my $rs = $this->{resultSets}->[$which]
	    or die "reference to non-existent result set";
	$rs->_add_records($apdu);
	$this->{resultSet} = $rs;
	return $apdu->referenceId();

    } else {
	print "unsupported APDU [$apdu] ignored\n";
	return undef;
    }
}


# PRIVATE to the new() method, invoked as an Event->io callback
sub _ready_to_write {
    my($event) = @_;
    my $watcher = $event->w();
    my $conn = $watcher->data();
    my $addr = $conn->{host} . ":" . $conn->{port};

    if (!$conn->{queued}) {
	print STDERR "Huh?  _ready_to_write() called with nothing queued\n";
	return;
    }

    # We bung as much of the data down the socket as we can, and keep
    # hold of whatever's left.
    my $nwritten = Net::Z3950::yaz_write($conn->{cs}, $conn->{queued});
    if ($nwritten < 0 && $! == ECONNREFUSED) {
	print "[$addr] connection refused\n";
	$conn->_destroy();
	Event::unloop(undef);
    } elsif ($nwritten < 0) {
	print "[$addr] yaz_write() failed ($!): closing connection\n";
	$watcher->cancel();
	return;
    }

    if ($nwritten == 0) {
	# Should be impossible: we only get called when ready to write
	print "[$addr] write zero bytes (shouldn't happen): never mind\n";
	return;
    }

    $conn->{queued} = substr($conn->{queued}, $nwritten);
    if (!$conn->{queued}) {
	# Don't bother me with select() hits when we have nothing to write
	$watcher->stop();
    }
}


# PRIVATE to the _ready_to_write() function.
#
# Destroys a connection object when it turns out that the connection
# didn't get forged after all (yaz_write() fails with ECONNREFUSED,
# indicating a failed asynchronous connection.)
#
sub _destroy {
    my $this = shift();

    # Do nothing for now: I'm not sure that this is the right thing.
}

=head2 option()

	$value = $conn->option($type);
	$value = $conn->option($type, $newval);

Returns I<$conn>'s value of the standard option I<$type>, as
registered in I<$conn> itself, in the manager which controls it, or in
the global defaults.

If I<$newval> is specified, then it is set as the new value of that
option in I<$conn>, and the option's old value is returned.

=cut

sub option {
    my $this = shift();
    my($type, $newval) = @_;

    my $value = $this->{options}->{$type};
    if (!defined $value) {
	$value = $this->{mgr}->option($type);
    }
    if (defined $newval) {
	$this->{options}->{$type} = $newval;
    }
    return $value
}


=head2 manager()

	$mgr = $conn->manager();

Returns a reference to the manager controlling I<$conn>.  If I<$conn>
was created with an explicit manager, then this method will always
return that function; otherwise, it returns a reference to the single
global ``default manager'' shared by all other connections.

=cut

sub manager {
    my $this = shift();

    return $this->{mgr};
}


=head2 startSearch()

	$conn->startSearch($srch);
	$conn->startSearch(-ccl => 'au=kernighan and su=unix');
	$conn->startSearch(-prefix => '@and @attr 1=1 kernighan @attr 1=21 unix');
	$conn->startSearch('@and @attr 1=1 kernighan @attr 1=21 unix');

Inititiates a new search against the Z39.50 server to which I<$conn>
is connected.  Since this can never fail (:-), it C<die()s> if
anything goes wrong.  But that will never happen.  (``Surely the odds
of that happening are million to one, doctor?'')

The query itself can be specified in a variety of ways:

=over 4

=item *

A C<Net::Z3950::Query> object may be passed in.

=item *

A query-type option may be passed in, together with the query string
itself as its argument.  Currently recognised query types are C<-ccl>
(using the standard CCL query syntax, interpreted by the server),
C<-ccl2rpn> (CCL query compiled by the client into a type-1 query) and
C<-prefix> (using Index Data's prefix query notation).

=item *

A query string alone may be passed in.  In this case, it is
interpreted according to the query type previously established as a
default for I<$conn> or its manager.

=back

The various query types are described in more detail in the
documentation of the C<Net::Z3950::Query> class.

=cut

# PRIVATE to the startSearch() method
my %_queryTypes = (
    prefix => Net::Z3950::QueryType::Prefix,
    ccl => Net::Z3950::QueryType::CCL,
    ccl2rpn => Net::Z3950::QueryType::CCL2RPN,
);

sub startSearch {
    my $this = shift();
    my $query = shift();
    my($type, $value);

    if (ref $query) {
	### Huh?  We don't actually have a *::Query type!
	$type = $query->type();
	$value = $query->value();
    } else {
	# Must be either (-querytype querystring) or just querystring
	if ($query =~ /^-/) {
	    ($type = $query) =~ s/^-//;
	    $value = shift();
	} else {
	    $type = $this->option('querytype');
	    $value = $query;
	}
	$query = undef;
    }

    my $queryType = $_queryTypes{$type};
    die "undefined query type '$type'" if !defined $queryType;

    # Generate the SEARCH request and queue it up for subsequent dispatch
    my $rss = $this->{resultSets};
    my $nrss = @$rss;
    my $errmsg = '';
    my $sr = Net::Z3950::makeSearchRequest($nrss,
				      $this->option('smallSetUpperBound'),
				      $this->option('largeSetLowerBound'),
				      $this->option('mediumSetPresentNumber'),
				      $nrss, # result-set name
				      $this->option('databaseName'),
				      $this->option('smallSetElementSetName'),
				      $this->option('mediumSetElementSetName'),
				      $this->option('preferredRecordSyntax'),
				      $queryType, $value, $errmsg);
    die "can't make search request: $errmsg" if !defined $sr;
    $rss->[$nrss] = 0;		# placeholder

    $this->_enqueue($sr);

    # Callback for asynchronous notification
    my $cb = shift();
    #warn "startSearch: cb='$cb'";
    $this->{refId2cb}->{$nrss} = $cb if defined $cb;
}


# PRIVATE to the new() and startSearch() methods
sub _enqueue {
    my $this = shift();
    my($msg) = @_;

    $this->{queued} .= $msg;
    $this->{writeWatcher}->start();
}


=head2 search()

	$rs = $conn->search($srch);

This utility method performs a blocking search, returning a reference
to the result set generated by the server.  It takes the same
arguments as C<startSearch()>

=cut

#   ###	Is there a mistake in the interface here?  At fetch-time we
#	have a single ResultSet method, record(), which either starts
#	an operations or starts and finishes it, depending on whether
#	we're in async or synchronous mode.  Maybe in the same way, we
#	should have a single search() method here, which behaves like
#	startSearch() when used on an asynchronous connection.  More
#	likely, it's the fetch interface that's broken, and should
#	have separate sync and async methods, so that we can discard
#	the notion of a mode completely.
#
sub search {
    my $this = shift();

    $this->startSearch(@_);
    if (!$this->expect(Net::Z3950::Op::Search, "search")) {
	return undef;
    }

    # We've established that the event was a search response on $this, so:
    return $this->resultSet();
}


# Private method, shared with ResultSet.pm but not available to client
# code.  Used to implement synchronous operations on top of async
# ones: waits for something to happen on $conn's manager, checks that
# the event is on the right connection, and is the expected kind of
# operation.  Return 1 or undef for success or failure.
#
sub expect {
    my $this = shift();
    my($op, $opname) = @_;

    my $conn = $this->manager()->wait();
    # Error not associated with a connection, e.g. ECONNREFUSED
    return undef
	if !defined $conn;

    ###	We would prefer just to ignore any events on connections other
    #	than this one, but there isn't a way to do this (unless we
    #	invent one, storing other-connection events until they're
    #	requested); so, for now, you shouldn't mix synchronous and
    #	asynchronous calls unless the async ones nominate a callback.
    die "expect() returned wrong connection!"
	if $conn != $this;

    # Error code and addinfo are already available from $this
    return undef
	if $this->op == Net::Z3950::Op::Error;

    ###	Again, we'd like to ignore this event, leaving it lying around
    #	for later; but there's no way to do it, so this has to be a
    #	fatal error.
    die "expect() got wrong op (expected $opname)"
	if $this->op() != $op;

    return 1;
}



=head2 op()

	op = $conn->op();
	if (op == Net::Z3950::Op::Search) { # ...

When a connection has been returned from the C<Net::Z3950::Manager> class's
C<wait()> method, it's known that I<something> has happened to it.
This method may then be called to find out what.  It returns one of
the following values:

=over 4

=item C<Net::Z3950::Op::Error>

An error occurred.  The details may be obtained via the C<errcode()>,
C<addinfo()> and C<errop()> methods described below.

=item C<Net::Z3950::Op::Init>

An init response was received.  The response object may be obtained
via the C<initResponse()> method described below.

=item C<Net::Z3950::Op::Search>

A search response was received.  The result set may be obtained via
the C<resultSet()> method described below.

=item C<Net::Z3950::Op::Get>

One or more result-set records have become available.  They may be
obtained via the C<records()> method described below.

=back

=cut

sub op {
    my $this = shift();

    my $op = $this->{op};
    die "Net::Z3950::Connection::op() called when no op is stored"
	if !defined $op;

    return $op;
}


=head2 errcode(), addinfo(), errop(), errmsg()

	if ($conn->op() == Net::Z3950::Op::Error) {
		print "error number: ", $conn->errcode(), "\n";
		print "error message: ", $conn->errmsg(), "\n";
		print "additional info: ", $conn->errcode(), "\n";
		print "in function: ", Net::Z3950::opstr($conn->errop()), "\n";
	}

When an error is known to have occurred on a connection, the error
code (from the BIB-1 diagnosic set) can be retrieved via the
C<errcode()> method, any additional information via the C<addinfo()>
method, and the operation that was being attempted when the error
occurred via the C<errop()> method.  (The error operation returned
takes one of the values that may be returned from the C<op()> method.)

As a convenience, C<$conn->errmsg()> is equivalent to
C<Net::Z3950::errstr($conn->errcode())>.

=cut

sub errcode {
    my $this = shift();
    return $this->{errcode};
}

sub addinfo {
    my $this = shift();
    return $this->{addinfo};
}

sub errop {
    my $this = shift();
    return $this->{errop};
}

sub errmsg {
    my $this = shift();
    return Net::Z3950::errstr($this->errcode());
}


=head2 initResponse()

	if ($op == Net::Z3950::Op::Init) {
		$rs = $conn->initResponse();

When a connection is known to have received an init response, the
response may be accessed via the connection's C<initResponse()>
method.

=cut

sub initResponse {
    my $this = shift();
    die "not init response" if $this->op() != Net::Z3950::Op::Init;
    return $this->{initResponse};
}


=head2 searchResponse(), resultSet()

	if ($op == Net::Z3950::Op::Search) {
		$sr = $conn->searchResponse();
		$rs = $conn->resultSet();

When a connection is known to have received a search response, the
response may be accessed via the connection's C<searchResponse()>, and
the search result may be accessed via the connection's C<resultSet()>
method.

=cut

sub searchResponse {
    my $this = shift();
    die "not search response" if $this->op() != Net::Z3950::Op::Search;
    return $this->{searchResponse};
}

sub resultSet {
    my $this = shift();
    die "not search response" if $this->op() != Net::Z3950::Op::Search;
    return $this->{resultSet};
}


=head2 resultSets()

	@rs = $conn->resultSets();

Returns a list of all the result sets that have been created across
the connection I<$conn> and have not subsequently been deleted.

=cut

sub resultSets {
    my $this = shift();

    return @{$this->{resultSets}};
}


=head2 name()

	print $conn->name();

Returns a short string which can be used as the connection's "name" in
text output.

=cut

sub name {
    my $this = shift();

    return $this->{host} . ':' . $this->{port};
}


=head2 close()

	$conn->close();

This lets the C<Net::Z3950> module know that you no longer want to use
C<$conn> so it can be closed.  It would be nice if this could be done
implicitly when C<$conn> goes out of scope, as in:

	{
	    $conn = new Net::Z3950::Connection($host, $port);
	    $rs = $conn->search($query);
	    print "found ", $rs->size(), " records\n";
	}

But in general this won't work, because C<$conn> is not the only
reference to the connection object: when it goes out of scope, the
connection is not destroyed because its manager still holds a
reference to it.  So use C<$conn->close()> (just before the close
brace in the example above) to let the connection know it's done with.

=cut

sub close {
    my $this = shift();

    my $mgr = delete $this->{mgr};
    $mgr->forget($this);
    ### How can we check if our refcount is zero now?
}


sub DESTROY {
    my $this = shift();

    #warn "destroying Net::Z3950 Connection $this";
}


=head1 AUTHOR

Mike Taylor E<lt>mike@tecc.co.ukE<gt>

First version Tuesday 23rd May 2000.

=head1 SEE ALSO

C<Net::Z3950::Query>

=cut

1;
