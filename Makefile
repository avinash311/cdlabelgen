# Makefile for cdlabelgen

SHELL = /bin/bash

VERSION = 4.3.0
ZIPVERSION = 430
# for 2.0.0, use 200, etc - note - lines above should have no spaces at end

# Where you want cdlabelgen and related files to be
# Change these to locations you need, also
# remember to edit cdlabelgen and its @where_is_the_template as needed.

BASE_DIR   = /usr
# BASE_DIR   = /usr/local
# BASE_DIR   = /opt
BIN_DIR   = $(BASE_DIR)/bin
LIB_DIR   = $(BASE_DIR)/share/cdlabelgen
MAN_DIR   = $(BASE_DIR)/share/man
WEBSOURCES= ../cdinsert.pl ../cdinsert-ps.pl ../cdlabelgen-form.html
SOURCES    = cdlabelgen ChangeLog INSTALL README Makefile INSTALL.WEB cdlabelgen.pod cdlabelgen.1 cdlabelgen.html spec.template $(WEBSOURCES)
POSTSCRIPT = template.ps *.eps
DISTFILES = $(SOURCES) $(POSTSCRIPT)

# just use 'cp -a' if you don't have install...
INSTALL		:= install -m 0755
INSTALL_DIR	:= install -d -m 0755
INSTALL_FILE	:= install -m 0644

# Makefile macros....
#1.  $@ is the name of the file to be made.
#2.  $? is the names of the changed dependents. 
#3.  $< the name of the related file that caused the action.
#4.  $* the prefix shared by target and dependent files. 
# ---------------
# rpmbuild creates packages here, should be writeable by CGI user/group
# RPM_TOPDIR	:= /usr/src/redhat
RPM_TOPDIR	:= $(HOME)/rpmbuild
# ---------------

all: cdlabelgen.html cdlabelgen.1

cdlabelgen.html: cdlabelgen.pod
	pod2html --outfile=$@ --infile=$?
	rm -f pod2html-dircache pod2html-itemcache pod2htm?.???

cdlabelgen.1: cdlabelgen.pod
	pod2man $? $@

###
install: all
	@echo "Installing cdlabelgen in $(BIN_DIR) and $(LIB_DIR)"
	@echo ""
	$(INSTALL_DIR) $(BIN_DIR)
	$(INSTALL) cdlabelgen $(BIN_DIR)
	$(INSTALL_FILE) cdlabelgen.1 $(MAN_DIR)/man1
	$(INSTALL_DIR) $(LIB_DIR)
	set -e; \
	for file in $(POSTSCRIPT); do \
		$(INSTALL_FILE) postscript/$$file $(LIB_DIR)/; \
	done
	@echo "** Done. Check $(BIN_DIR)/cdlabelgen and fix @where_is_the_template - if needed!"

cdlabelgen-$(VERSION).spec: spec.template
	sed -e "s/TAG_VERSION/$(VERSION)/" < $? > $@
	
dist: all cdlabelgen-$(VERSION).spec
	rm -rf cdlabelgen-$(VERSION)
	mkdir cdlabelgen-$(VERSION)
	mkdir cdlabelgen-$(VERSION)/postscript
	cp $(SOURCES) cdlabelgen-$(VERSION)/
	mv cdlabelgen-$(VERSION).spec cdlabelgen-$(VERSION)/
	cd postscript; cp $(POSTSCRIPT) ../cdlabelgen-$(VERSION)/postscript
	rm -f cdlbl$(ZIPVERSION).zip cdlabelgen-$(VERSION).tgz
	zip -r cdlbl$(ZIPVERSION) cdlabelgen-$(VERSION)
	tar cvzf cdlabelgen-$(VERSION).tgz cdlabelgen-$(VERSION)
	rm -rf cdlabelgen-$(VERSION)
	# On Ubuntu, the following command fails to create .rpm file,
	# and then errors on check files stage. Fixed: allow unpackaged files in spec.template
	# rpmbuild -ta cdlabelgen-$(VERSION).tgz  # fails, src can't be built. Ok, build bin only.
	# mv $(RPM_TOPDIR)/RPMS/noarch/cdlabelgen-$(VERSION)*noarch.rpm .
	mkdir -p $(RPM_TOPDIR)/{BUILD,RPMS,SPECS}
	rpmbuild --target=noarch -tb cdlabelgen-$(VERSION).tgz
	mv $(RPM_TOPDIR)/RPMS/noarch/cdlabelgen-$(VERSION)*noarch.rpm .
	# .rpm not worth the trouble - can't install it, reports "Error: failed dependencies" even
	# though system has it... and other such problems.

clean:
	rm -f *.tgz *~
