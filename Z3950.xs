/* $Header: /home/cvsroot/NetZ3950/Z3950.xs,v 1.1.1.1 2001/02/12 10:53:54 mike Exp $ */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "yazwrap/yazwrap.h"

/* Used for converting databuf-type arguments */
static databuf SVstar2databuf(SV* svp)
{
    databuf buf;

    if (SvOK(svp)) {
	buf.data = (char*) SvPV(svp, buf.len);
    } else {
	buf.data = 0;
    }

    return buf;
}

static char *SVstar2MNPV(SV* svp)
{
    STRLEN dummy;

    if (!SvOK(svp))
	return 0;

    return SvPV(svp, dummy);
}


/*
 * The manifest-constant stuff, generated by h2xs, turns out not to be
 * necessary or sufficient, so we don't use it.  But it's non-trivial
 * to surgically remove this code, so we leave it in for now -- the
 * overhead can't be great.
 */
static int
not_here(char *s)
{
    croak("%s not implemented on this architecture", s);
    return -1;
}

static double
constant(char *name, int arg)
{
    errno = 0;
    switch (*name) {
    case 'A':
	break;
    case 'B':
	break;
    case 'C':
	break;
    case 'D':
	break;
    case 'E':
	break;
    case 'F':
	break;
    case 'G':
	break;
    case 'H':
	break;
    case 'I':
	break;
    case 'J':
	break;
    case 'K':
	break;
    case 'L':
	break;
    case 'M':
	break;
    case 'N':
	break;
    case 'O':
	break;
    case 'P':
	break;
    case 'Q':
	break;
    case 'R':
	break;
    case 'S':
	break;
    case 'T':
	break;
    case 'U':
	break;
    case 'V':
	break;
    case 'W':
	break;
    case 'X':
	break;
    case 'Y':
	break;
    case 'Z':
	break;
    }
    errno = EINVAL;
    return 0;

not_there:
    errno = ENOENT;
    return 0;
}


MODULE = Net::Z3950		PACKAGE = Net::Z3950		

PROTOTYPES: DISABLE


double
constant(name,arg)
	char *		name
	int		arg

COMSTACK
yaz_connect(addr)
	char *addr

int
yaz_socket(cs)
	COMSTACK cs

const char *
diagbib1_str(errcode)
	int errcode

databuf
makeInitRequest(referenceId, preferredMessageSize, maximumRecordSize, user, password, groupid, implementationId, implementationName, implementationVersion)
	databuf referenceId
	int preferredMessageSize
	int maximumRecordSize
	mnchar *user
	mnchar *password
	mnchar *groupid
	mnchar *implementationId
	mnchar *implementationName
	mnchar *implementationVersion

databuf
makeSearchRequest(referenceId, smallSetUpperBound, largeSetLowerBound, mediumSetPresentNumber, resultSetName, databaseName, smallSetElementSetName, mediumSetElementSetName, preferredRecordSyntax, queryType, query)
	databuf referenceId
	int smallSetUpperBound
	int largeSetLowerBound
	int mediumSetPresentNumber
	char *resultSetName
	char *databaseName
	char *smallSetElementSetName
	char *mediumSetElementSetName
	int preferredRecordSyntax
	int queryType
	char *query

databuf
makePresentRequest(referenceId, resultSetId, resultSetStartPoint, numberOfRecordsRequested, elementSetName, preferredRecordSyntax)
	databuf referenceId
	char *resultSetId
	int resultSetStartPoint
	int numberOfRecordsRequested
	char *elementSetName
	int preferredRecordSyntax

SV *
decodeAPDU(cs, reason)
	COMSTACK cs
	int &reason
	OUTPUT:
	reason

int
yaz_write(cs, buf)
	COMSTACK cs
	databuf buf