/* $Header: /home/cvsroot/NetZ3950/yazwrap/send.c,v 1.2 2001/02/16 16:51:06 mike Exp $ */

/*
 * yazwrap/send.c -- wrapper functions for Yaz's client API.
 *
 * This file provides functions which (we hope) will be easier to
 * invoke via XS than the raw Yaz API.  We do this by providing fewer
 * functions at a higher level; and, where appropriate, using more
 * primitive C data types.
 */

#include <unistd.h>
#include <yaz/proto.h>
#include <yaz/log.h>
#include <yaz/pquery.h>		/* prefix query compiler */
#include <yaz/ccl.h>		/* CCL query compiler */
#include <yaz/yaz-ccl.h>	/* CCL-to-RPN query converter */
#include "ywpriv.h"


Z_ReferenceId *make_ref_id(Z_ReferenceId *buf, databuf refId);
static Odr_oid *record_syntax(ODR odr, int preferredRecordSyntax);
static databuf encode_apdu(ODR odr, Z_APDU *apdu);
static void prepare_odr(ODR *odrp);
static databuf nodata(char *debug);


/*
 * The YAZ memory allocation function go fatal on memory exhaustion,
 * so in interface terms, that's a "can't happen".  What else can go
 * wrong?  The actual encoding of the APDU into an ODR buffer is the
 * only other possibility, so we diagnose that by returning a databuf
 * with a null data member.
 */
databuf makeInitRequest(databuf referenceId,
			int preferredMessageSize,
			int maximumRecordSize,
			mnchar *user,
			mnchar *password,
			mnchar *groupid,
			mnchar *implementationId,
			mnchar *implementationName,
			mnchar *implementationVersion)
{
    static ODR odr = 0;
    Z_APDU *apdu;
    Z_InitRequest *req;
    Z_ReferenceId zr;
    Z_IdAuthentication auth;
    Z_IdPass id;

    prepare_odr(&odr);
    apdu = zget_APDU(odr, Z_APDU_initRequest);
    req = apdu->u.initRequest;

    req->referenceId = make_ref_id(&zr, referenceId);
    /*
     * ### We should consider allowing the caller to influence which
     * of the following options are set.  The ones marked with the
     * Mystic Rune Of The Triple Hash are actually not supported in
     * Net::Z3950.pm as I write.
     */
    ODR_MASK_SET(req->options, Z_Options_search);
    ODR_MASK_SET(req->options, Z_Options_present);
    ODR_MASK_SET(req->options, Z_Options_namedResultSets);
    ODR_MASK_SET(req->options, Z_Options_triggerResourceCtrl); /* ### */
    ODR_MASK_SET(req->options, Z_Options_scan);	/* ### */
    ODR_MASK_SET(req->options, Z_Options_sort);	/* ### */
    ODR_MASK_SET(req->options, Z_Options_extendedServices); /* ### */
    ODR_MASK_SET(req->options, Z_Options_delSet); /* ### */

    ODR_MASK_SET(req->protocolVersion, Z_ProtocolVersion_1);
    ODR_MASK_SET(req->protocolVersion, Z_ProtocolVersion_2);
    ODR_MASK_SET(req->protocolVersion, Z_ProtocolVersion_3);

    *req->preferredMessageSize = preferredMessageSize;
    *req->maximumRecordSize = maximumRecordSize;

    /*
     * We interpret the `user', `password' and `group' arguments as
     * follows: if `user' is not specified, then authentication is
     * omitted (which is more or less the same as "anonymous"
     * authentication); if `user' is specified but not `password',
     * then it's treated as an "open" authentication token; if both
     * `user' and `password' are specified, then they are used in
     * "idPass" authentication, together with `group' if specified.
     */
    if (user != 0) {
	req->idAuthentication = &auth;
	if (password == 0) {
	    auth.which = Z_IdAuthentication_open;
	    auth.u.open = user;
	} else {
	    auth.which = Z_IdAuthentication_idPass;
	    auth.u.idPass = &id;
	    id.userId = user;
	    id.groupId = groupid;
	    id.password = password;
	}
    }

    if (implementationId != 0)
	req->implementationId = implementationId;
    if (implementationName != 0)
	req->implementationName = implementationName;
    if (implementationVersion != 0)
	req->implementationVersion = implementationVersion;

    return encode_apdu(odr, apdu);
}


/*
 * I feel really uncomfortable about that fact that if this function
 * fails, the caller has no way to know why -- it could be an illegal
 * record syntax, an unsupported query type, a bad search command or
 * failure to encode the APDU.  Oh well.
 */
databuf makeSearchRequest(databuf referenceId,
			  int smallSetUpperBound,
			  int largeSetLowerBound,
			  int mediumSetPresentNumber,
			  char *resultSetName,
			  char *databaseName,
			  char *smallSetElementSetName,
			  char *mediumSetElementSetName,
			  int preferredRecordSyntax,
			  int queryType,
			  char *query)
{
    static ODR odr = 0;
    Z_APDU *apdu;
    Z_SearchRequest *req;
    Z_ReferenceId zr;
    Z_ElementSetNames smallES, mediumES;
    oident attrset;
    int oidbuf[20];		/* more than enough */
    Z_Query zquery;
    Odr_oct ccl_query;
    struct ccl_rpn_node *rpn;
    int error, pos;

    prepare_odr(&odr);
    apdu = zget_APDU(odr, Z_APDU_searchRequest);
    req = apdu->u.searchRequest;

    req->referenceId = make_ref_id(&zr, referenceId);
    *req->smallSetUpperBound = smallSetUpperBound;
    *req->largeSetLowerBound = largeSetLowerBound;
    *req->mediumSetPresentNumber = mediumSetPresentNumber;
    *req->replaceIndicator = 1;
    req->resultSetName = resultSetName;
    req->num_databaseNames = 1;
    req->databaseNames = &databaseName;

    /* Translate a single element-set names into a Z_ElementSetNames */
    req->smallSetElementSetNames = &smallES;
    smallES.which = Z_ElementSetNames_generic;
    smallES.u.generic = smallSetElementSetName;

    req->mediumSetElementSetNames = &mediumES;
    mediumES.which = Z_ElementSetNames_generic;
    mediumES.u.generic = mediumSetElementSetName;

    /* Convert from our enumeration to the corresponding OID */
    if ((req->preferredRecordSyntax =
	 record_syntax(odr, preferredRecordSyntax)) == 0)
	return nodata("can't convert record syntax");

    /* Convert from our querytype/query pair to a Z_Query */
    req->query = &zquery;

    switch (queryType) {
    case QUERYTYPE_PREFIX:
	/* ### Is type-1 always right?  What about type-101 when under v2? */
        zquery.which = Z_Query_type_1;
        if ((zquery.u.type_1 = p_query_rpn (odr, PROTO_Z3950, query)) == 0)
	    return nodata("can't compile PQN query");
        break;

    case QUERYTYPE_CCL:
        zquery.which = Z_Query_type_2;
        zquery.u.type_2 = &ccl_query;
        ccl_query.buf = (unsigned char*) query;
        ccl_query.len = strlen(query);
        break;

    case QUERYTYPE_CCL2RPN:
        zquery.which = Z_Query_type_1;
        if ((rpn = ccl_find_str((CCL_bibset) 0, query, &error, &pos)) == 0)
	    return nodata("can't compile CCL query");
        if ((zquery.u.type_1 = ccl_rpn_query(odr, rpn)) == 0)
	    return nodata("can't encode Type-1 query");
        attrset.proto = PROTO_Z3950;
        attrset.oclass = CLASS_ATTSET;
        attrset.value = VAL_BIB1; /* ### should be configurable! */
        zquery.u.type_1->attributeSetId = oid_ent_to_oid(&attrset, oidbuf);
        ccl_rpn_delete (rpn);
        break;

    default:
	return nodata("unknown queryType");
    }

    return encode_apdu(odr, apdu);
}


databuf makePresentRequest(databuf referenceId,
			   char *resultSetId,
			   int resultSetStartPoint,
			   int numberOfRecordsRequested,
			   char *elementSetName,
			   int preferredRecordSyntax)
{
    static ODR odr = 0;
    Z_APDU *apdu;
    Z_PresentRequest *req;
    Z_ReferenceId zr;
    Z_RecordComposition rcomp;
    Z_ElementSetNames esname;

    prepare_odr(&odr);
    apdu = zget_APDU(odr, Z_APDU_presentRequest);
    req = apdu->u.presentRequest;

    req->referenceId = make_ref_id(&zr, referenceId);
    req->resultSetId = resultSetId;
    *req->resultSetStartPoint = resultSetStartPoint;
    *req->numberOfRecordsRequested = numberOfRecordsRequested;
    req->num_ranges = 0;	/* ### would be nice to support this */
    req->recordComposition = &rcomp;
    rcomp.which = Z_RecordComp_simple;	/* ### espec suppport would be nice */
    rcomp.u.simple = &esname;
    esname.which = Z_ElementSetNames_generic;
    esname.u.generic = elementSetName;
    if ((req->preferredRecordSyntax =
	 record_syntax(odr, preferredRecordSyntax)) == 0)
	return nodata("can't convert record syntax");

    return encode_apdu(odr, apdu);
}


/*
 * If refId is non-null, copy it into the provided buffer, and return
 * a pointer to it; otherwise, return a null pointer.  Either way, the
 * result is suitable to by plugged into an APDU structure.
 */
Z_ReferenceId *make_ref_id(Z_ReferenceId *buf, databuf refId)
{
    if (refId.data == 0)
	return 0;

    buf->buf = refId.data;
    buf->len = (int) refId.len;
    return buf;
}


static Odr_oid *record_syntax(ODR odr, int preferredRecordSyntax)
{
    oident prefsyn;
    int oidbuf[20];		/* more than enough */
    int *oid;

    prefsyn.proto = PROTO_Z3950;
    prefsyn.oclass = CLASS_RECSYN;
    prefsyn.value = (oid_value) preferredRecordSyntax;
    if ((oid = oid_ent_to_oid(&prefsyn, oidbuf)) == 0)
	return 0;

    return odr_oiddup(odr, oid);
}



/*
 * Memory management strategy: every APDU we're asked to allocate
 * obliterates the previous one by overwriting our static ODR buffer,
 * so the caller _must_ ensure that it copies or otherwise consumes
 * the return value before the next call is made.  (This strategy
 * would normally stink, but it's actually not error-prone in this
 * context, since we know that the Perl XS code is about to copy the
 * data onto its stack.)
 */
static databuf encode_apdu(ODR odr, Z_APDU *apdu)
{
    databuf res;
    res.data = 0;

    if (!z_APDU(odr, &apdu, 0, (char*) 0)) {
	/* ### it's a bit naughty to generate output here */
        odr_perror(odr, "Encoding APDU");
	return res;
    }

    res.data = odr_getbuf(odr, &res.len, (int*) 0);
    return res;
}


static void prepare_odr(ODR *odrp)
{
    if (*odrp != 0) {
	odr_reset(*odrp);
    } else if ((*odrp = odr_createmem(ODR_ENCODE)) == 0) {
	yaz_log(LOG_FATAL, "Can't create ODR stream");
	exit(1);
    }
}


/*
 * Return a databuf with a null pointer (used as an error indicator)
 * (In passing, we also report to stderr what the problem was.)
 */
static databuf nodata(char *debug)
{
    databuf buf;

#ifndef NDEBUG
    fprintf(stderr, "nodata(): %s\n", debug);
#endif
    buf.data = 0;
    return buf;
}


/*
 * Simple wrapper for cs_write() when that comes along.  Also calls
 * cs_look() to detect the completion of a connection when that comes
 * along.  In the mean time, we fake both bits.
 */
int yaz_write(COMSTACK cs, databuf buf)
{
    if (cs_look(cs) == CS_CONNECT) {
	/*
	 * This is nonsense, but it works.  Fix it when Index Data provide
	 * real cs_look(), which should be Real Soon Now.
	 */
	errno = ECONNREFUSED;
	return -1;		
    }

    return write(cs_fileno(cs), buf.data, buf.len);
}