/* $Header: /home/cvsroot/NetZ3950/yazwrap/yazwrap.h,v 1.1.1.1 2001/02/12 10:53:55 mike Exp $ */

/*
 * yazwrap/yazwrap.h -- wrapper functions for Yaz's client API.
 *
 * This file provides the public interface to this thin library.
 */

#include <yaz/diagbib1.h>	/* Provide declaration of diagbib1_str() */
#include <yaz/comstack.h>	/* Need COMSTACK typedef to parse this file */

/* Simple counted-length data buffer (so it can contain NULs) */
typedef struct databuf {
    char *data;
    size_t len;
} databuf;

/* Maybe-null char* (don't ask -- see ../typemap if you really care */
typedef char mnchar;

/* Home-brew simplified front end functions */
COMSTACK yaz_connect(char *addr);
int yaz_socket(COMSTACK cs);

/*
 * Functions representing Z39.50 requests.  Where parameters specified
 * by the standard are not currently supported by this interface,
 * their names are commented.
 */
databuf makeInitRequest(databuf referenceId,
			/* protocolVersion */
			/* options */
			int preferredMessageSize,
			int maximumRecordSize,
			mnchar *user,
			mnchar *password,
			mnchar *groupid,
			mnchar *implementationId,
			mnchar *implementationName,
			mnchar *implementationVersion
			/* userInformationField */
			/* otherInfo */
			);

databuf makeSearchRequest(databuf referenceId,
			  int smallSetUpperBound,
			  int largeSetLowerBound,
			  int mediumSetPresentNumber,
			  /* replaceIndicator */
			  char *resultSetName,
			  /* num_databaseNames */
			  char *databaseName,
			  char *smallSetElementSetName,
			  char *mediumSetElementSetName,
			  int preferredRecordSyntax,
			  int queryType,
			  char *query
			  /* additionalSearchInfo */
			  /* otherInfo */
			  );
/* Constants for use as `querytype' argument to makeSearchRequest() */
#define QUERYTYPE_PREFIX  39501	/* Yaz's "@attr"-ish forward-Polish notation */
#define QUERYTYPE_CCL     39502	/* Send CCL string to server ``as is'' */
#define QUERYTYPE_CCL2RPN 39503 /* Convert CCL to RPN (type-1) locally */

databuf makePresentRequest(databuf referenceId,
			   char *resultSetId,
			   int resultSetStartPoint,
			   int numberOfRecordsRequested,
			   /* num_ranges */
			   /* additionalRanges */
			   char *elementSetName,
			   int preferredRecordSyntax
			   /* maxSegmentCount */
			   /* maxRecordSize */
			   /* maxSegmentSize */
			   /* otherInfo */
			   );

SV *decodeAPDU(COMSTACK cs, int *reasonp);
/*
 * decodeAPDU() error codes -- will be set into `*reasonp' if a null
 * pointer is returned.  In addition to these, `*reasonp' may be set
 * to a value of cs_errno()
 */ 
#define REASON_EOF 23951	/* read EOF from connection (server gone) */
#define REASON_INCOMPLETE 23952	/* read bytes, but not yet a whole APDU */
#define REASON_MALFORMED 23953	/* couldn't decode APDU (malformed) */
#define REASON_BADAPDU 23954	/* APDU was well-formed but unrecognised */
#define REASON_ERROR 23955	/* some other error (consult errno) */

int yaz_write(COMSTACK cs, databuf buf);