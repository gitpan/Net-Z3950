/* $Header: /home/cvsroot/NetZ3950/yazwrap/util.c,v 1.2 2001/06/22 08:32:38 mike Exp $ */

/*
 * yazwrap/util.c -- wrapper functions for Yaz's client API.
 *
 * This file provides utility functions for the wrapper library.
 */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include "ywpriv.h"


void fatal(char *fmt, ...)
{
    va_list ap;

    fprintf(stderr, "FATAL (yazwrap): ");
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    abort();
}


/*
 * cs_look(), which we need to use in yaz_write() and decodeAPDU(), is
 * simply not defined in Yaz of the current release (1.6), despite
 * documentation to the contrary.  Correspondingly, we just go ahead and
 * write it ourselves.  We have to mess with the underlying socket, so this
 * is definitely The Wrong Thing.
 *
 * This is _very_ monobuttockular.
 */
int cs_look(COMSTACK cs)
{
    int s = cs_fileno(cs);
    int err = 0;		/* initialise to avoid -Wall warning */
    size_t errlen = sizeof err;

    if (getsockopt(s, SOL_SOCKET, SO_ERROR, (void*) &err, &errlen) < 0)
	fatal("getsockopt() failed: error %d (%s)", errno, strerror(errno));
    assert(errlen == sizeof err);

    if (err == ECONNREFUSED) {
	/* Assume this is because an async connect() has been unsuccessful */
	return CS_CONNECT;
    }

    return CS_DATA;
}
