# $Header: /home/cvsroot/NetZ3950/Makefile.PL,v 1.2 2002/02/08 17:41:20 mike Exp $

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Net::Z3950',
    'VERSION_FROM' => 'Z3950.pm', # finds $VERSION
#   'LIBS'	=> ['-L/usr/local/src/yaz/lib/.libs -lyaz'],   # e.g., '-lm' 
    'LIBS'	=> ['-lyaz'],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
#   'INC'	=> '-I/usr/local/src/yaz/include',
    'PREREQ_PM' => { Event => 0.77 },
    'MYEXTLIB'	=> 'yazwrap/libyazwrap$(LIB_EXT)',
    'AUTHOR'    => 'Mike Taylor <mike@perl.z3950.org>',
    'ABSTRACT'  => 'Build clients for the Z39.50 info. retrieval protocol',
);


#   ###	I put this bit here basically because the "perlxstut" (XS
#	Tutorial) manual told me to, but frankly I don't understand
#	the MakeMaker.  It seems that this is superfluous, because the
#	generated Makefile in any case recurses to yazwrap at the drop
#	of a hat -- including, for example, when doing a "make test",
#	which is _not_ what I want.  Never mind, it's not the end of
#	the world.
#
sub MY::postamble {
'
$(MYEXTLIB): yazwrap/Makefile
	cd yazwrap && $(MAKE) $(PASTHRU)
';
}
