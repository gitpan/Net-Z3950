/* $Header: /home/cvsroot/perlZ3950/yazwrap/receive.c,v 1.3 2000/10/06 10:01:03 mike Exp $ */

/*
 * yazwrap/receive.c -- wrapper functions for Yaz's client API.
 *
 * This file provides a single function, decodeAPDU(), which pulls an
 * APDU off the network, decodes it (using YAZ) and converts it from
 * Yaz's C structures into broadly equivalent Perl functions.
 */

#include <assert.h>
#include <yaz/proto.h>
#include <yaz/oid.h>
#include "ywpriv.h"


static SV *translateAPDU(Z_APDU *apdu, int *reasonp);
static SV *translateInitResponse(Z_InitResponse *res, int *reasonp);
static SV *translateSearchResponse(Z_SearchResponse *res, int *reasonp);
static SV *translatePresentResponse(Z_PresentResponse *res, int *reasonp);
static SV *translateRecords(Z_Records *x);
static SV *translateNamePlusRecordList(Z_NamePlusRecordList *x);
static SV *translateNamePlusRecord(Z_NamePlusRecord *x);
static SV *translateExternal(Z_External *x);
static SV *translateSUTRS(Z_SUTRS *x);
static SV *translateGenericRecord(Z_GenericRecord *x);
static SV *translateTaggedElement(Z_TaggedElement *x);
static SV *translateStringOrNumeric(Z_StringOrNumeric *x);
static SV *translateElementData(Z_ElementData *x);
static SV *translateOctetAligned(Odr_oct *x, Odr_oid *direct_reference);
static SV *translateFragmentSyntax(Z_FragmentSyntax *x);
static SV *translateDiagRecs(Z_DiagRecs *x);
static SV *translateDiagRec(Z_DiagRec *x);
static SV *translateDefaultDiagFormat(Z_DefaultDiagFormat *x);
static SV *translateOID(Odr_oid *x);
static SV *newObject(char *class, SV *referent);
static void setNumber(HV *hv, char *name, IV val);
static void setString(HV *hv, char *name, char *val);
static void setBuffer(HV *hv, char *name, char *valdata, int vallen);
static void setMember(HV *hv, char *name, SV *val);


/*
 * This interface hides from the caller the possibility that the
 * socket has become ready not because there's data to be read, but
 * because the connect() has finished.  In this case, we just return a
 * null pointer with *reasonp==REASON_INCOMPLETE, which the caller
 * will treat in the right way (try again later.)
 *
 *  ###	The "perlguts" manual strongly implies that returning a null
 *	pointer here and elsewhere is not good enough, and I need
 *	instead to return PL_sv_undef.  In fact, null seems to work
 *	just fine.
 */
SV *decodeAPDU(COMSTACK cs, int *reasonp)
{
    static char *buf = 0;	/* apparently, static is OK */
    static int size = 0;	/* apparently, static is OK */
    int nbytes;
    ODR odr;
    Z_APDU *apdu;

    switch (cs_look(cs)) {
    case CS_CONNECT:
	if (cs_rcvconnect(cs) < 0) {
	    *reasonp = REASON_ERROR;
	} else {
	    *reasonp = REASON_INCOMPLETE;
	}
	return 0;
    case CS_DATA:
	break;
    default:
	fatal("surprising cs_look() result");
    }

    nbytes = cs_get(cs, &buf, &size);
    switch (nbytes) {
    case -1:
	*reasonp = cs_errno(cs);
	return 0;
    case 0:
	*reasonp = REASON_EOF;
	return 0;
    case 1:
	*reasonp = REASON_INCOMPLETE;
	return 0;
    default:
	/* We got enough bytes for a whole PDU */
	break;
    }

    if ((odr = odr_createmem(ODR_DECODE)) == 0) {
	/* Perusal of the Yaz source shows that this is impossible:
	 * odr_createmem() only fails if the initial xmalloc() fails,
	 * but xmalloc() is #defined to xmalloc_f(), which goes fatal
	 * if the underlying xmalloc_d() call fails.
	 */
	fatal("impossible odr_createmem() failure");
    }

    odr_reset(odr);		/* do we need to do this on a new ODR? */
    odr_setbuf(odr, buf, nbytes, 0);
    if (!z_APDU(odr, &apdu, 0, 0)) {
	/* Oops.  Malformed APDU (can't be short, otherwise, we'd not
	 * have got a >1 response from cs_get()).  There's nothing we
	 * can do about it.
	 */
	*reasonp = REASON_BADAPDU;
	return 0;
    }

    /* ### we should find a way to request another call if cs_more() */
    return translateAPDU(apdu, reasonp);
}


/*
 * This has to return a Perl data-structure representing the decoded
 * APDU.  What's the best way to do this?  We have several options:
 *
 *  1.	We can hack a new backend onto Yaz's existing ASN.1 compiler
 *	(written in Tcl!) so that it mechanically generates the
 *	functions necessary to convert Yaz's C data structures into
 *	Perl.
 *
 *  2.	We can do it by hand, which will be more work but will yield a
 *	better final product.  This also has the benefit of a lower
 *	startup cost (I don't have to grok the Tcl code) and a simpler
 *	distribution.
 *
 *  3.	We can do (or have the ASN.1 compiler do) a mechanical job,
 *	translating into low-level Perl data structures like arrays
 *	and hashes, and have the Perl layer above this translate the
 *	"raw" structures into something more palatable.
 *
 * For now, I guess we'll go with option 2, just so we can demonstrate
 * a successful Init negotiation.  In the longer term, we'll probably
 * need to run with 1 or 3, because there's a LOT of dull code to
 * write!
 *
 *  ###	Do I need to check for the Perl "guts" functions returning
 *	null values?  The manual doesn't seem to be clear on this.
 */
static SV *translateAPDU(Z_APDU *apdu, int *reasonp)
{
    switch (apdu->which) {
    case Z_APDU_initResponse:
	return translateInitResponse(apdu->u.initResponse, reasonp);
    case Z_APDU_searchResponse:
	return translateSearchResponse(apdu->u.searchResponse, reasonp);
    case Z_APDU_presentResponse:
	return translatePresentResponse(apdu->u.presentResponse, reasonp);
    default:
	break;
    }

    *reasonp = REASON_BADAPDU;
    return 0;
}


static SV *translateInitResponse(Z_InitResponse *res, int *reasonp)
{
    SV *sv;
    HV *hv;

    sv = newObject("Net::Z3950::APDU::InitResponse", (SV*) (hv = newHV()));

    if (res->referenceId) {
	setBuffer(hv, "referenceId",
		  res->referenceId->buf, res->referenceId->len);
    }
    /* protocolVersion not translated (complex data type) */
    /* options not translated (complex data type) */
    setNumber(hv, "preferredMessageSize", (IV) *res->preferredMessageSize);
    setNumber(hv, "maximumRecordSize", (IV) *res->maximumRecordSize);
    setNumber(hv, "result", (IV) *res->result);
    if (res->implementationId)
	setString(hv, "implementationId", res->implementationId);
    if (res->implementationName)
	setString(hv, "implementationName", res->implementationName);
    if (res->implementationVersion)
	setString(hv, "implementationVersion", res->implementationVersion);
    /* userInformationField (OPT) not translated (complex data type) */
    /* otherInfo (OPT) not translated (complex data type) */

    return sv;
}


static SV *translateSearchResponse(Z_SearchResponse *res, int *reasonp)
{
    SV *sv;
    HV *hv;

    sv = newObject("Net::Z3950::APDU::SearchResponse", (SV*) (hv = newHV()));
    if (res->referenceId)
	setBuffer(hv, "referenceId",
		  res->referenceId->buf, res->referenceId->len);

    setNumber(hv, "resultCount", (IV) *res->resultCount);
    setNumber(hv, "numberOfRecordsReturned",
	      (IV) *res->numberOfRecordsReturned);
    setNumber(hv, "nextResultSetPosition", (IV) *res->nextResultSetPosition);
    setNumber(hv, "searchStatus", (IV) *res->searchStatus);
    if (res->resultSetStatus)
	setNumber(hv, "resultSetStatus", (IV) *res->resultSetStatus);
    if (res->presentStatus)
	setNumber(hv, "presentStatus", (IV) *res->presentStatus);
    if (res->records)
	setMember(hv, "records", translateRecords(res->records));

    /* additionalSearchInfo (OPT) not translated (complex data type) */
    /* otherInfo (OPT) not translated (complex data type) */

    return sv;
}


static SV *translatePresentResponse(Z_PresentResponse *res, int *reasonp)
{
    SV *sv;
    HV *hv;

    sv = newObject("Net::Z3950::APDU::PresentResponse", (SV*) (hv = newHV()));

    if (res->referenceId)
	setBuffer(hv, "referenceId",
		  res->referenceId->buf, res->referenceId->len);
    setNumber(hv, "numberOfRecordsReturned",
	      (IV) *res->numberOfRecordsReturned);
    setNumber(hv, "nextResultSetPosition", (IV) *res->nextResultSetPosition);
    setNumber(hv, "presentStatus", (IV) *res->presentStatus);
    if (res->records)
	setMember(hv, "records", translateRecords(res->records));

    /* otherInfo (OPT) not translated (complex data type) */

    return sv;
}


static SV *translateRecords(Z_Records *x)
{
    switch (x->which) {
    case Z_Records_DBOSD:
	return translateNamePlusRecordList(x->u.databaseOrSurDiagnostics);
    case Z_Records_NSD:
	return translateDefaultDiagFormat(x->u.nonSurrogateDiagnostic);
    case Z_Records_multipleNSD:
	return translateDiagRecs(x->u.multipleNonSurDiagnostics);
    default:
	break;
    }
    fatal("illegal `which' in Z_Records");
    return 0;			/* NOTREACHED; inhibit gcc -Wall warning */
}


static SV *translateNamePlusRecordList(Z_NamePlusRecordList *x)
{
    /* Represented as a reference to a blessed array of elements */
    SV *sv;
    AV *av;
    int i;

    sv = newObject("Net::Z3950::APDU::NamePlusRecordList", (SV*) (av = newAV()));
    for (i = 0; i < x->num_records; i++)
	av_push(av, translateNamePlusRecord(x->records[i]));

    return sv;
}


static SV *translateNamePlusRecord(Z_NamePlusRecord *x)
{
    SV *sv;
    HV *hv;

    sv = newObject("Net::Z3950::APDU::NamePlusRecord", (SV*) (hv = newHV()));
    if (x->databaseName)
	setString(hv, "databaseName", x->databaseName);
    setNumber(hv, "which", x->which);

    switch (x->which) {
    case Z_NamePlusRecord_databaseRecord:
	setMember(hv, "databaseRecord",
		  translateExternal(x->u.databaseRecord));
	break;
    case Z_NamePlusRecord_surrogateDiagnostic:
	setMember(hv, "surrogateDiagnostic",
		  translateDiagRec(x->u.surrogateDiagnostic));
	break;
    case Z_NamePlusRecord_startingFragment:
	setMember(hv, "startingFragment",
		  translateFragmentSyntax(x->u.startingFragment));
	break;
    case Z_NamePlusRecord_intermediateFragment:
	setMember(hv, "intermediateFragment",
		  translateFragmentSyntax(x->u.intermediateFragment));
	break;
    case Z_NamePlusRecord_finalFragment:
	setMember(hv, "finalFragment",
		  translateFragmentSyntax(x->u.finalFragment));
	break;
    default:
	fatal("illegal `which' in Z_NamePlusRecord");
    }

    return sv;
}


/*
 * Section 3.4 (EXTERNAL Data) of chapter 3 (The ASN Module) of the
 * Yaz Manual has this to say:
 *	For ASN.1 structured data, you need only consult the which
 *	field to determine the type of data.  You can the access the
 *	data directly through the union.
 * In other words, the Z_External structure's direct_reference,
 * indirect_reference and descriptor fields are only there to help the
 * data get across the network; and once it's done that (and arrived
 * here), we can simply use the `which' discriminator to choose a
 * branch of the union to encode.
 *
 *  ###	Exception: if I understand this correctly, then we need to
 *	have translateOctetAligned() consult x->direct_reference so it
 *	knows which specific *MARC class to bless the data into.
 */
static SV *translateExternal(Z_External *x)
{
    switch (x->which) {
    case Z_External_sutrs:
	return translateSUTRS(x->u.sutrs);
    case Z_External_grs1:
	return translateGenericRecord(x->u.grs1);
    case Z_External_octet:
	/* This is used for any opaque data-block (i.e. just a hunk of
	 * octets) -- in particular, for records in any of the *MARC
	 * syntaxes.
	 */
	return translateOctetAligned(x->u.octet_aligned, x->direct_reference);
    default:
	break;
    }
    fatal("illegal/unsupported `which' (%d) in Z_External", x->which);
    return 0;			/* NOTREACHED; inhibit gcc -Wall warning */
}


static SV *translateSUTRS(Z_SUTRS *x)
{
    /* Represent as a blessed scalar -- unusual but clearly appropriate.
     * The usual scheme of things in this source file is to make objects of
     * class Net::Z3950::APDU::*, but in this case and some other below, we go
     * straight to the higher-level representation of a Net::Z3950::Record::*
     * object, knowing that this is a subclass of its Net::Z3950::APDU::*
     * analogue, but with additional, record-syntax-specific,
     * functionality.
     */
    return newObject("Net::Z3950::Record::SUTRS", newSVpvn(x->buf, x->len));
}


static SV *translateGenericRecord(Z_GenericRecord *x)
{
    /* Represented as a reference to a blessed array of elements */
    SV *sv;
    AV *av;
    int i;

    /* See comment on class-name in translateSUTRS() above.  We use
     * ...::GRS1 rather than ...::GenericRecord because that's what the
     * application-level calling code will expect.
     */
    sv = newObject("Net::Z3950::Record::GRS1", (SV*) (av = newAV()));
    for (i = 0; i < x->num_elements; i++)
	av_push(av, translateTaggedElement(x->elements[i]));

    return sv;
}


static SV *translateTaggedElement(Z_TaggedElement *x)
{
    SV *sv;
    HV *hv;

    sv = newObject("Net::Z3950::APDU::TaggedElement", (SV*) (hv = newHV()));
    if (x->tagType)
	setNumber(hv, "tagType", *x->tagType);
    setMember(hv, "tagValue", translateStringOrNumeric(x->tagValue));
    if (x->tagOccurrence)
	setNumber(hv, "tagOccurrence", *x->tagOccurrence);
    setMember(hv, "content", translateElementData(x->content));
    /* Z_ElementMetaData *metaData; // OPT */
    /* Z_Variant *appliedVariant; // OPT */

    return sv;
}


static SV *translateStringOrNumeric(Z_StringOrNumeric *x)
{
    switch (x->which) {
    case Z_StringOrNumeric_string:
	return newSVpv(x->u.string, 0);
    case Z_StringOrNumeric_numeric:
	return newSViv(*x->u.numeric);
    default:
	break;
    }
    fatal("illegal `which' in Z_ElementData");
    return 0;			/* NOTREACHED; inhibit gcc -Wall warning */
}


/*
 * It's tempting to treat this data by simply returning an appropriate
 * Perl data structure, no bothering with an explicit discriminator --
 * as translateStringOrNumeric() does for its data -- but that would
 * mean (for example) that we couldn't tell the difference between
 * elementNotThere, elementNotEmpty and noDataRequested.  This would
 * be A Bad Thing, since it's not this code's job to fix bugs in the
 * standard :-)  Instead, we return an object with an explicit `which'
 * element, as translateNamePlusRecord() does.
 */
static SV *translateElementData(Z_ElementData *x)
{
    SV *sv;
    HV *hv;

    sv = newObject("Net::Z3950::APDU::ElementData", (SV*) (hv = newHV()));
    setNumber(hv, "which", x->which);

    switch (x->which) {
    case Z_ElementData_numeric:
	setMember(hv, "numeric", newSViv(*x->u.numeric));
	break;
    case Z_ElementData_string:
	setMember(hv, "string", newSVpv(x->u.string, 0));
	break;
    case Z_ElementData_oid:
	setMember(hv, "oid", translateOID(x->u.oid));
	break;
    case Z_ElementData_subtree:
	setMember(hv, "subtree", translateGenericRecord(x->u.subtree));
	break;
    default:
	fatal("illegal/unsupported `which' (%d) in Z_ElementData", x->which);
    }

    return sv;
}


/*
 * We use a blessed scalar string to represent the (non-ASN.1-encoded)
 * record; the only difficult part is knowing what class to bless it into.
 * We do that by looking up its record syntax in a hardwired table that
 * maps it to a class-name string.
 *
 * We assume that the record, not processed here, will subsequently be
 * picked apart by some pre-existing module, most likely MARC.pm
 */
static SV *translateOctetAligned(Odr_oct *x, Odr_oid *direct_reference)
{
    struct {
	oid_value val;
	char *name;
    } rs[] = {
	{ VAL_USMARC,		"Net::Z3950::Record::USMARC" },
	{ VAL_UKMARC,		"Net::Z3950::Record::UKMARC" },
	{ VAL_NORMARC,		"Net::Z3950::Record::NORMARC" },
	{ VAL_LIBRISMARC,	"Net::Z3950::Record::LIBRISMARC" },
	{ VAL_DANMARC,		"Net::Z3950::Record::DANMARC" },
	{ VAL_NOP }		/* end marker */
	/* ### etc. */
    };

    int i;
    for (i = 0; rs[i].val != VAL_NOP; i++) {
	static struct oident ent = { PROTO_Z3950, CLASS_RECSYN };
	int *oid;
	ent.value = rs[i].val;
	oid = oid_getoidbyent(&ent);
	if (!oid_oidcmp(oid, direct_reference))
	    break;
    }

    if (rs[i].val == VAL_NOP)
	fatal("can't translate record of unknown RS");

    return newObject(rs[i].name, newSVpvn(x->buf, x->len));
}


static SV *translateFragmentSyntax(Z_FragmentSyntax *x)
{
    return 0;			/* ### not yet implemented */
}


static SV *translateDiagRecs(Z_DiagRecs *x)
{
    /* Represented as a reference to a blessed array of elements */
    SV *sv;
    AV *av;
    int i;

    sv = newObject("Net::Z3950::APDU::DiagRecs", (SV*) (av = newAV()));
    for (i = 0; i < x->num_diagRecs; i++)
	av_push(av, translateDiagRec(x->diagRecs[i]));

    return sv;
}


static SV *translateDiagRec(Z_DiagRec *x)
{
    switch (x->which) {
    case Z_DiagRec_defaultFormat:
	return translateDefaultDiagFormat(x->u.defaultFormat);
    case Z_DiagRec_externallyDefined:
	return translateExternal(x->u.externallyDefined);
    default:
	break;
    }
    fatal("illegal `which' in Z_DiagRec");
    return 0;			/* NOTREACHED; inhibit gcc -Wall warning */
}


static SV *translateDefaultDiagFormat(Z_DefaultDiagFormat *x)
{
    SV *sv;
    HV *hv;

    sv = newObject("Net::Z3950::APDU::DefaultDiagFormat", (SV*) (hv = newHV()));
    setMember(hv, "diagnosticSetId", translateOID(x->diagnosticSetId));
    setNumber(hv, "condition", *x->condition);
    /* ### we don't care what value of `which' pertains -- in either
     * case, what we have is frankly a char*, so we let type punning
     * take care of it.
     */
    setString(hv, "addinfo", x->u.v2Addinfo);
    return sv;
}


static SV *translateOID(Odr_oid *x)
{
    /* Yaz represents an OID by an int arrays terminated by a negative
     * value, typically -1; we represent it as a reference to a
     * blessed array of scalar elements.
     */
    SV *sv;
    AV *av;
    int i;

    sv = newObject("Net::Z3950::APDU::OID", (SV*) (av = newAV()));
    for (i = 0; x[i] >= 0; i++)
	av_push(av, newSViv(x[i]));

    return sv;
}


/*
 * Creates a new Perl object of type `class'; the newly-created scalar
 * that is a reference to the blessed thingy `referent' is returned.
 */
static SV *newObject(char *class, SV *referent)
{
    HV *stash;
    SV *sv;

    sv = newRV_noinc((SV*) referent);
    stash = gv_stashpv(class, 0);
    if (stash == 0)
	fatal("attempt to create object of undefined class '%s'", class);
    /*assert(stash != 0);*/
    sv_bless(sv, stash);
    return sv;
}


static void setNumber(HV *hv, char *name, IV val)
{
    SV *sv = newSViv(val);
    setMember(hv, name, sv);
}


static void setString(HV *hv, char *name, char *val)
{
    return setBuffer(hv, name, val, 0);
}


static void setBuffer(HV *hv, char *name, char *valdata, int vallen)
{
    SV *sv = newSVpv(valdata, vallen);
    setMember(hv, name, sv);
}


static void setMember(HV *hv, char *name, SV *val)
{
    /* We don't increment `val's reference count -- I think this is
     * right because it's created with a refcount of 1, and in fact
     * the reference via this hash is the only reference to it in
     * general.
     */
    if (!hv_store(hv, name, (U32) strlen(name), val, (U32) 0))
	fatal("couldn't store member in hash");
}
