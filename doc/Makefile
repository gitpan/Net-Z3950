# $Header: /home/cvsroot/perlZ3950/doc/Makefile,v 1.3 2000/10/06 10:01:03 mike Exp $

MODULES = Z3950 Z3950/Tutorial Z3950/Manager Z3950/Connection Z3950/APDU \
	Z3950/ResultSet Z3950/Record
PERL = $(MODULES:%=../%.pm)
HTML = $(MODULES:%=%.html)
JUNK = pod2html-dircache pod2html-itemcache

all: Z3950 $(HTML)

Z3950:
	mkdir Z3950

%.html: ../%.pm
	pod2html < $? > $@

### Why do we need this rule?  Isn't is a special case of the last one?
Z3950/%.html: ../Z3950/%.pm
	pod2html < $? > $@

clean:
	rm -f $(HTML) $(JUNK)
