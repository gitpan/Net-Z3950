/* $Header: /home/cvsroot/NetZ3950/yazwrap/connect.c,v 1.3 2002/07/19 15:44:16 mike Exp $ */

/*
 * yazwrap/connect.c -- wrapper functions for Yaz's client API.
 *
 * Provide a simple Perl-level interface to Yaz's COMSTACK API.  We
 * need to use this because of its mystical ability to read only whole
 * APDUs off the network stream.
 */

#include <yaz/tcpip.h>
#include "ywpriv.h"


/*
 *  ###	We're setting up the connection in non-blocking mode, which is
 *	what we want.  However, the YAZ docs imply that this means
 *	that the connect() (as well as subsequent read()s) will be
 *	non-blocking, so that we'll need to catch and service the
 *	"connection complete" callback.  We're not doing that, but the
 *	code more or less works anyway -- what gives?!
 */
COMSTACK yaz_connect(char *addr)
{
    COMSTACK conn;
    void *inaddr;

    if ((conn = cs_create(tcpip_type, 0, PROTO_Z3950)) == 0) {
	/* mostly likely `errno' will be ENOMEM or something useful */
        return 0;
    }

    if ((inaddr = cs_straddr(conn, addr)) == 0) {
	/* ### How can we get more information to the caller? */
	return 0;
    }

    switch (cs_connect(conn, inaddr)) {
    case -1:			/* can't connect */
/*printf("cs_connect() failed\n");*/
	/* mostly likely `errno' will be ECONNREFUSED or something useful */
        cs_close(conn);
        return 0;
    case 0:			/* success */
/*printf("cs_connect() succeeded\n");*/
        break;
    case 1:			/* non-blocking -- "not yet" */
/*printf("cs_connect() not yet\n");*/
	break;
    }

    return conn;
}


/* Need a Real Function for Perl to call, as cs_fileno() is a macro */
int yaz_socket(COMSTACK cs)
{
    return cs_fileno(cs);
}

/* just a wrapper for now, but who knows - perhaps it may do more later */

int yaz_close(COMSTACK cs)
{
    return cs_close(cs);
}
