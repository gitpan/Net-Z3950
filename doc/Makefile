# $Header: /home/cvsroot/NetZ3950/doc/Makefile,v 1.2 2001/10/12 15:16:13 mike Exp $

MODULES = Z3950 Z3950/Tutorial Z3950/Manager Z3950/Connection Z3950/APDU \
	Z3950/ResultSet Z3950/Record
PERL = $(MODULES:%=../%.pm)
HTML = $(MODULES:%=%.html)
JUNK = pod2html-dircache pod2html-itemcache

all: Z3950 Z3950/style.css $(HTML)

Z3950:
	mkdir Z3950

Z3950/style.css: style.css
	rm -f $@; cp $? $@

%.html: ../%.pm
	./htmlify < $? > $@

### Why do we need this rule?  Isn't is a special case of the last one?
Z3950/%.html: ../Z3950/%.pm
	./htmlify < $? > $@

clean:
	rm -f $(HTML) Z3950/style.css $(JUNK)
