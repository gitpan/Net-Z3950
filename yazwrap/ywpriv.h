/* $Header: /home/cvsroot/NetZ3950/yazwrap/ywpriv.h,v 1.1.1.1 2001/02/12 10:53:55 mike Exp $ */

#include "EXTERN.h"		/* Prerequisite for "perl.h" */
#define yaz_log __some_stupid_function_in_the_linux_math_library
#include "perl.h"		/* Is this enough for SV*? */
#undef yaz_log
#undef simple
/*
 * Explanations for the above bits of brain damage.
 *
 * 1. on some systems (e.g. Red Hat Linux 6.0), the <math.h> header
 * file (which is included by "perl.h") deploys a terrifying swathe of
 * cpp trickery to declare a function called yaz_log() -- totally
 * unrelated to Index Data's Yaz toolkit -- which means that when we
 * subsequently #include <yaz/log.h> (as "send.c" does), the true
 * declaration is flagged as an error.  Ouch.  Hence the
 * define-it-out-of-the-way nonsense above.
 *
 * I find it truly hard to believe this, but "embed.h" (included by
 * "perl.h") #defines the token "simple" to "Perl_simple", which means
 * we can't access the `simple' element of Yaz's Z_RecordComposition
 * structure.  So this has to be explicitly undefined.  Bleaurrgh.
 */

#include "yazwrap.h"

void fatal(char *fmt, ...);
int cs_look(COMSTACK cs);
