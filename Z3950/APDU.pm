# $Header: /home/cvsroot/NetZ3950/Z3950/APDU.pm,v 1.5 2001/10/19 15:40:25 mike Exp $

package Net::Z3950::APDU;
use strict;
use vars qw($AUTOLOAD @FIELDS);


=head1 NAME

Net::Z3950::APDU - Read-only objects representing decoded Z39.50 APDUs

=head1 SYNOPSIS

I<You probably shouldn't be reading this!>

	package Net::Z3950::APDU::SomeSpecificSortOfAPDU;
	use Net::Z3950::APDU;
	@ISA = qw(Net::Z3950::APDU);
	@FIELDS = qw(names of APDU fields);

=head1 DESCRIPTION

This class provides a trivial base for the various read-only APDUs
implemented as a part of the Net::Z3950 module.  Its role is simply to
supply named methods providing read-only access to the same-named
fields.  The set of fields is specified by the derived class's
package-global C<@FIELDS> array.

I<You don't need to understand or use this class in order to use the
Net::Z3950 module.  It's purely an implementation detail.  In fact, I
probably should never even have written this documentation.  Forget I
said anything.  Go and read the next section.>

=cut

sub AUTOLOAD {
    my $this = shift();

    my $class = ref $this;
    my $fieldname;
    ($fieldname = $AUTOLOAD) =~ s/.*:://;
    die "class $class -- field `$fieldname' not defined"
	if !grep { $_ eq $fieldname } $class->_fields();

    return $this->{$fieldname};
}

sub DESTROY {
    # Do nothing.  This is only here because on some installations --
    # I don't really have a handle on what the condition is --
    # APDU-derived objects try to call DESTROY when they're thrown
    # away, and that was getting translated into a call to AUTOLOAD,
    # which was complaining "field `DESTROY' not defined".  Now that
    # we have an explicit no-opping DESTROY, that shouldn't happen.
    #
    # The only discussion I have found anywhere of DESTROY/AUTOLOAD
    # interaction is this thread on comp.lang.perl.moderated:
    #	http://groups.google.com/groups?hl=en&frame=right&th=1bc05ce0aff89451&seekm=86r9qpmvbv.fsf%40lion.plab.ku.dk#link1
}


=head1 SUBCLASSES

The following classes are all trivial derivations of C<Net::Z3950::APDU>,
and represent specific types of APDU.  Each such class is
characterised by the set of data-access methods it supplies: these are
listed below.

Each method takes no arguments, and returns the information implied by
its name.  See the relevant sections of the Z39.50 Standard for
information on the interpretation of this information - for example,
section 3.2.1 (Initialization Facility) describes the elements of the
C<Net::Z3950::APDU::InitResponse> class.

I<Actually, you don't need to understand or use any of these classes
either: they're used internally in the implementation, so this
documentation is provided as a service to those who will further
develop this module in the future.>

=cut


=head2 Net::Z3950::APDU::InitResponse

	referenceId()
	preferredMessageSize()
	maximumRecordSize()
	result()
	implementationId()
	implementationName()
	implementationVersion()

=cut

package Net::Z3950::APDU::InitResponse;
use vars qw(@ISA @FIELDS);
@ISA = qw(Net::Z3950::APDU);
@FIELDS = qw(referenceId preferredMessageSize maximumRecordSize result
	     implementationId implementationName
	     implementationVersion);
sub _fields { @FIELDS };


=head2 Net::Z3950::APDU::SearchResponse

	referenceId()
	resultCount()
	numberOfRecordsReturned()
	nextResultSetPosition()
	searchStatus()
	resultSetStatus()
	presentStatus()
	records()

=cut

package Net::Z3950::APDU::SearchResponse;
use vars qw(@ISA @FIELDS);
@ISA = qw(Net::Z3950::APDU);
@FIELDS = qw(referenceId resultCount numberOfRecordsReturned
	     nextResultSetPosition searchStatus resultSetStatus
	     presentStatus records);
sub _fields { @FIELDS };


=head2 Net::Z3950::APDU::PresentResponse

	referenceId()
	numberOfRecordsReturned()
	nextResultSetPosition()
	presentStatus()
	records()

=cut

package Net::Z3950::APDU::PresentResponse;
use vars qw(@ISA @FIELDS);
@ISA = qw(Net::Z3950::APDU);
@FIELDS = qw(referenceId numberOfRecordsReturned nextResultSetPosition
	     presentStatus records);
sub _fields { @FIELDS };


=head2 Net::Z3950::APDU::NamePlusRecordList

No methods - just treat as a reference to an array of
C<Net::Z3950::APDU::NamePlusRecord>

=cut

package Net::Z3950::APDU::NamePlusRecordList;


=head2 Net::Z3950::APDU::NamePlusRecord

	databaseName()
	which()
	databaseRecord()
	surrogateDiagnostic()
	startingFragment()
	intermediateFragment()
	finalFragment()

Only one of the last five methods will return anything - you can find
out which one by inspecting the return value of the C<which()> method,
which always takes one of the following values:

=over 4

=item *

Net::Z3950::NamePlusRecord::DatabaseRecord

=item *

Net::Z3950::NamePlusRecord::SurrogateDiagnostic

=item *

Net::Z3950::NamePlusRecord::StartingFragment

=item *

Net::Z3950::NamePlusRecord::IntermediateFragment

=item *

Net::Z3950::NamePlusRecord::FinalFragment

=back

When C<which()> is C<Net::Z3950::NamePlusRecord::DatabaseRecord>, the
object returned from the C<databaseRecord()> method will be a decoded
Z39.50 EXTERNAL.  Its type may be any of the following (and may be
tested using C<$rec-E<gt>isa('Net::Z3950::Record::Whatever')> if necessary.)

=over 4

=item *

Net::Z3950::Record::SUTRS

=item *

Net::Z3950::Record::GRS1

=item *

Net::Z3950::Record::USMARC and
similarly, Net::Z3950::Record::UKMARC, Net::Z3950::Record::NORMARC, I<etc>.

=item *

Net::Z3950::Record::XML

I<### others, not yet supported>

=back

=cut

package Net::Z3950::APDU::NamePlusRecord;
use vars qw(@ISA @FIELDS);
@ISA = qw(Net::Z3950::APDU);

@FIELDS = qw(databaseName which databaseRecord surrogateDiagnostic
	     startingFragment intermediateFragment finalFragment);
sub _fields { @FIELDS };

# Define the NamePlusRecord class's "which" enumeration, which
# indicates which of the possible branches contains data (i.e. it's
# the discriminator for a union.)  This must be kept synchronised with
# the values defined in the header file <yaz/z-core.h>
package Net::Z3950::NamePlusRecord;
sub DatabaseRecord       { 1 }
sub SurrogateDiagnostic  { 2 }
sub StartingFragment     { 3 }
sub IntermediateFragment { 4 }
sub FinalFragment        { 5 }
package Net::Z3950;


=head2 Net::Z3950::APDU::SUTRS, Net::Z3950::APDU::USMARC, Net::Z3950::APDU::UKMARC, Net::Z3950::APDU::NORMARC, Net::Z3950::APDU::LIBRISMARC, Net::Z3950::APDU::DANMARC, Net::Z3950::APDU::UNIMARC, Net::Z3950::APDU::OPAC

No methods - just treat as an opaque chunk of data.

=cut

package Net::Z3950::APDU::SUTRS;
package Net::Z3950::APDU::USMARC;
package Net::Z3950::APDU::UKMARC;
package Net::Z3950::APDU::NORMARC;
package Net::Z3950::APDU::LIBRISMARC;
package Net::Z3950::APDU::DANMARC;
package Net::Z3950::APDU::UNIMARC;
package Net::Z3950::APDU::OPAC;


=head2 Net::Z3950::APDU::GRS1

No methods - just treat as a reference to an array of
C<Net::Z3950::APDU::TaggedElement>

=cut

package Net::Z3950::APDU::GRS1;


=head2 Net::Z3950::APDU::TaggedElement;

	tagType()
	tagValue()
	tagOccurrence()
	content()

=cut

package Net::Z3950::APDU::TaggedElement;
use vars qw(@ISA @FIELDS);
@ISA = qw(Net::Z3950::APDU);
@FIELDS = qw(tagType tagValue tagOccurrence content);
sub _fields { @FIELDS };


=head2 Net::Z3950::APDU::ElementData

	which()
	numeric()
	string()
	subtree()

Only one of the last three methods will return anything - you can find
out which one by inspecting the return value of the C<which()> method,
which always takes one of the following values:

=over 4

=item *

Net::Z3950::ElementData::Numeric

=item *

Net::Z3950::ElementData::String

=item *

Net::Z3950::ElementData::subtree

=item *

I<### others, not yet supported>

=back

=cut

package Net::Z3950::APDU::ElementData;
use vars qw(@ISA @FIELDS);
@ISA = qw(Net::Z3950::APDU);

@FIELDS = qw(which numeric string oid subtree);
sub _fields { @FIELDS };

# Define the ElementData class's "which" enumeration, which indicates
# which of the possible branches contains data (i.e. it's the
# discriminator for a union.)  This must be kept synchronised with the
# values defined in the header file <yaz/z-grs.h> -- NOT <yaz/prt-grs.h>
package Net::Z3950::ElementData;
sub Numeric { 1 }
sub String  { 5 }
sub OID { 7 }
sub Subtree { 13 }
package Net::Z3950;


=head2 Net::Z3950::APDU::DiagRecs

No methods - just treat as a reference to an array of object
references.  The objects will typically be of class
C<Net::Z3950::APDU::DefaultDiagFormat>, but careful callers will check
this, since any kind of EXTERNAL may be provided instead.

=cut

package Net::Z3950::APDU::DiagRecs;


=head2 Net::Z3950::APDU::DefaultDiagFormat;

	diagnosticSetId()
	condition()
	addinfo()

=cut

package Net::Z3950::APDU::DefaultDiagFormat;
use vars qw(@ISA @FIELDS);
@ISA = qw(Net::Z3950::APDU);
@FIELDS = qw(diagnosticSetId condition addinfo);
sub _fields { @FIELDS };


=head2 Net::Z3950::APDU::OID

No methods - just treat as a reference to an array of integers.

=cut

package Net::Z3950::APDU::OID;



=head1 AUTHOR

Mike Taylor E<lt>mike@tecc.co.ukE<gt>

First version Saturday 27th May 2000.

=cut

1;
