use ExtUtils::MakeMaker;
$Verbose = 1;

#   ###	I shouldn't have to tell the MakeMaker this (I found it out by
#	looking at a Makefile generated without a CCFLAGS
#	specification) but I can't find a way to _add_ bits to an
#	option.
#
my $defaultCCFLAGS = q[-Dbool=char -DHAS_BOOL -I/usr/local/include];

WriteMakefile(
    'NAME'	=> 'Net::Z3950::yazwrap',
#   'INC'	=> '-I/usr/local/src/yaz/include',
    'CCFLAGS'	=> $defaultCCFLAGS . ' -Wall',
### The next line (as directed by the "perlxstut" manual) generates an
#	irritating warning which I've managed to eliminate by hacking
#	the line in the form that appears below it: but why do I need
#	it at all?  What's it for?  Omitting it does in fact prevent
#	the build from working!
#   'SKIP'	=> [qw(all static static_lib dynamic dynamic_lib)],
    'SKIP'	=> [qw(all static dynamic test)],
    'clean'	=> {'FILES' => 'libyazwrap$(LIB_EXT)'},
	      'OPTIMIZE' => '-g',	### temporary
);


sub MY::top_targets {
	'
all :: static

static :: libyazwrap$(LIB_EXT)

libyazwrap$(LIB_EXT): $(O_FILES)
	$(AR) cr libyazwrap$(LIB_EXT) $(O_FILES)
	$(RANLIB) libyazwrap$(LIB_EXT)

# nothing to test

test:

';
}
