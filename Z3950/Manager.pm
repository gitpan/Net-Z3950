# $Header: /home/cvsroot/NetZ3950/Z3950/Manager.pm,v 1.2 2002/01/22 14:51:01 mike Exp $

package Net::Z3950::Manager;
use Event;
use strict;


=head1 NAME

Net::Z3950::Manager - State manager for multiple Z39.50 connections.

=head1 SYNOPSIS

	$mgr = new Net::Z3950::Manager(mode => 'async');
	$conn = $mgr->connect($hostname, $port);
	# Set up some more connections, then:
	while ($conn = $mgr->wait()) {
		# Handle message on $conn
	}

=head1 DESCRIPTION

A manager object encapsulates the Net::Z3950 module's global state -
preferences for search parsing, preferred record syntaxes, compiled
configuration files, I<etc.> - as well as a list of references to all
the open connections.  It main role is to handle multiplexing between
the connections that are opened on it.

We would normally expect there to be just one manager object in a
program, but I suppose there's no reason why you shouldn't make more
if you want.

Simple programs - those which therefore have no requirement for
multiplexing, perhaps because they connect only to a single server -
do not need explicitly to create a manager at all: an anonymous
manager is implicitly created along with the connection.

=head1 METHODS

=cut


=head2 new()

	$mgr = new Net::Z3950::Manager();

Creates and returns a new manager.  Any of the standard options may be
specified as arguments; in addition, the following manager-specific
options are recognised:

=over 4

=item mode

Must be either C<sync> or C<async>; if omitted, defaults to C<sync>.
The mode affects various details of subsequent behaviour - for
example, see the description of the C<Net::Z3950::Connection> class's
C<new()> method.

=back

=cut

sub new {
    my $class = shift();
    # No additional arguments except options

    return bless {
	connections => [],
	options => { @_ },
    }, $class;
}


=head2 option()

	$value = $mgr->option($type);
	$value = $mgr->option($type, $newval);

Returns I<$mgr>'s value of the standard option I<$type>, as registered
in I<$mgr> or in the global defaults.

If I<$newval> is specified, then it is set as the new value of that
option in I<$mgr>, and the option's old value is returned.

=cut

sub option {
    my $this = shift();
    my($type, $newval) = @_;

    my $value = $this->{options}->{$type};
    if (!defined $value) {
	$value = _default($type);
    }
    if (defined $newval) {
	$this->{options}->{$type} = $newval;
    }
    return $value;
}

# PRIVATE to the option() method
#
# This function specifies the hard-wired global defaults used when
# constructors and the option() method do not override them.
#
#	### Should have POD documentation for these options.
#
sub _default {
    my($type) = @_;

    # Used in Net::Z3950::ResultSet::record() to determine whether to wait
    return 'sync' if $type eq 'mode';

    # Used in Net::Z3950::Connection::new() (for INIT request)
    # (Values are mostly derived from what yaz-client does.)
    return 1024*1024 if $type eq 'preferredMessageSize';
    return 1024*1024 if $type eq 'maximumRecordSize';
    return undef if $type eq 'user';
    return undef if $type eq 'password';
    return undef if $type eq 'groupid';
    # (Compare the next three values with those in "yaz/zutil/zget.c".
    # The standard doesn't give much help, just saying:
    #	3.2.1.1.6 Implementation-id, Implementation-name, and
    #	Implementation-version -- The request or response may
    #	optionally include any of these three parameters. They are,
    #	respectively, an identifier (unique within the client or
    #	server system), descriptive name, and descriptive version, for
    #	the origin or target implementation. These three
    #	implementation parameters are provided solely for the
    #	convenience of implementors, for the purpose of distinguishing
    #	implementations.
    # )
    return 'Mike Taylor (id=169)' if $type eq 'implementationId';
    return 'Net::Z3950.pm (Perl)' if $type eq 'implementationName';
    return $Net::Z3950::VERSION if $type eq 'implementationVersion';

    # Used in Net::Z3950::Connection::startSearch()
    return 'prefix' if $type eq 'querytype';
    return 'Default' if $type eq 'databaseName';
    return 0 if $type eq 'smallSetUpperBound';
    return 1 if $type eq 'largeSetLowerBound';
    return 0 if $type eq 'mediumSetPresentNumber';
    return 'f' if $type eq 'smallSetElementSetName';
    return 'b' if $type eq 'mediumSetElementSetName';
    return Net::Z3950::RecordSyntax::GRS1 if $type eq 'preferredRecordSyntax';

    # Used in Net::Z3950::ResultSet::makePresentRequest()
    return 'b' if $type eq 'elementSetName';

    # etc.

    # Otherwise it's an unknown option.
    return undef;
}


=head2 connect()

	$conn = $mgr->connect($hostname, $port);

Creates a new connection under the control of the manager I<$mgr>.
The connection will be forged to the server on the specified I<$port>
of <$hostname>.

Additional standard options may be specified after the I<$port>
argument.

(This is simply a sugar function to C<Net::Z3950::Connection->new()>)

=cut

sub connect {
    my $this = shift();
    my($hostname, $port, @other_args) = @_;

    # The "indirect object" notation "new Net::Z3950::Connection" fails if
    # we use it here, because we've not yet seen the Connection
    # module (Net::Z3950.pm use's Manager first, then Connection).  It gets
    # mis-parsed as an application of the new() function to the result
    # of the Connection() function in the Net::Z3950 package (I think) but
    # that error message is immediately further obfuscated by the
    # autoloader (thanks for that), which complains "Can't locate
    # auto/Net::Z3950/Connection.al in @INC".  It took me a _long_ time to
    # grok this ...
    return Net::Z3950::Connection->new($this, $hostname, $port, @other_args);
}


=head2 wait()

	$conn = $mgr->wait();

Waits for an event to occur on one of the connections under the
control of I<$mgr>, yielding control to any other event handlers that
may have been registered with the underlying event loop.

When a suitable event occurs - typically, a response is received to an
earlier INIT, SEARCH or PRESENT - the handle of the connection on
which it occurred is returned: the handle can be further interrogated
with its C<op()> and related methods.

=cut

sub wait {
    my $this = shift();

    # The next line prevents the Event module from catching our die()
    # calls and turning them into warnings sans bathtub.  By
    # installing this handler, we can get proper death back.
    #
    ###	This is not really the right place to do this, but then where
    #	is?  There's no single main()-like entry-point to this
    #	library, so we may as well set Event's die()-handler just
    #	before we hand over control.
    $Event::DIED = \&Event::verbose_exception_handler;

    my $conn = Event::loop();
    return $conn;
}


# PRIVATE to the Net::Z3950::Connection module's new() method
sub _register {
    my $this = shift();
    my($conn) = @_;

    push @{$this->{connections}}, $conn;
}


=head2 connections()

	@conn = $mgr->connections();

Returns a list of all the connections that have been opened under the
control of the manager I<$mgr> and have not subsequently been closed.

=cut

sub connections {
    my $this = shift();

    return @{$this->{connections}};
}

=head2 resultSets()

	@rs = $mgr->resultSets();

Returns a list of all the result sets that have been created across
the connections associated with the manager I<$mgr> and have not
subsequently been deleted.

=cut

sub resultSets {
    my $this = shift();

    my @rs;

    foreach my $conn ($this->connections()) {
	push @rs, @{$conn->{resultSets}};
    }

    return @rs;
}


### PRIVATE to the Net::Z3950::Connection::close() method.
sub forget {
    my $this = shift();
    my($conn) = @_;

    my $n = $this->connections();
    for (my $i = 0; $i < $n; $i++) {
	next if $this->{connections}->[$i] ne $conn;
	warn "forgetting connection $i of $n";
	splice @{ $this->{connections} }, $i, 1;
	return;
    }

    die "$this can't forget $conn";
}


sub DESTROY {
    my $this = shift();

    #warn "destroying Net::Z3950 Connection $this";
}


=head1 AUTHOR

Mike Taylor E<lt>mike@tecc.co.ukE<gt>

First version Tuesday 23rd May 2000.

=head1 SEE ALSO

List of standard options.

Discussion of the Net::Z3950 module's use of the Event module.

=cut

1;
