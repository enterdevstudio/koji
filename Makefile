NAME=koji
SPECFILE = $(firstword $(wildcard *.spec))
SUBDIRS = hub builder koji cli docs util www

ifdef DIST
DIST_DEFINES := --define "dist $(DIST)"
endif

ifndef VERSION
VERSION := $(shell rpm $(RPM_DEFINES) $(DIST_DEFINES) -q --qf "%{VERSION}\n" --specfile $(SPECFILE)| head -1)
endif
# the release of the package
ifndef RELEASE
RELEASE := $(shell rpm $(RPM_DEFINES) $(DIST_DEFINES) -q --qf "%{RELEASE}\n" --specfile $(SPECFILE)| head -1)
endif

ifndef WORKDIR
WORKDIR := $(shell pwd)
endif
## Override RPM_WITH_DIRS to avoid the usage of these variables.
ifndef SRCRPMDIR
SRCRPMDIR = $(WORKDIR)
endif
ifndef BUILDDIR
BUILDDIR = $(WORKDIR)
endif
ifndef RPMDIR
RPMDIR = $(WORKDIR)
endif
## SOURCEDIR is special; it has to match the CVS checkout directory,-
## because the CVS checkout directory contains the patch files. So it basically-
## can't be overridden without breaking things. But we leave it a variable
## for consistency, and in hopes of convincing it to work sometime.
ifndef SOURCEDIR
SOURCEDIR := $(shell pwd)
endif


# RPM with all the overrides in place;
ifndef RPM
RPM := $(shell if test -f /usr/bin/rpmbuild ; then echo rpmbuild ; else echo rpm ; fi)
endif
ifndef RPM_WITH_DIRS
RPM_WITH_DIRS = $(RPM) --define "_sourcedir $(SOURCEDIR)" \
		    --define "_builddir $(BUILDDIR)" \
		    --define "_srcrpmdir $(SRCRPMDIR)" \
		    --define "_rpmdir $(RPMDIR)"
endif

# CVS-safe version/release -- a package name like 4Suite screws things
# up, so we have to remove the leaving digits from the name
TAG_NAME    := $(shell echo $(NAME)    | sed -e s/\\\./_/g -e s/^[0-9]\\\+//g)
TAG_VERSION := $(shell echo $(VERSION) | sed s/\\\./_/g)
TAG_RELEASE := $(shell echo $(RELEASE) | sed s/\\\./_/g)

# tag to export, defaulting to current tag in the spec file
ifndef TAG
TAG=$(TAG_NAME)-$(TAG_VERSION)-$(TAG_RELEASE)
endif

_default:
	@echo "read the makefile"

clean:
	rm -f *.o *.so *.pyc *~ koji*.bz2 koji*.src.rpm
	rm -rf koji-$(VERSION)
	for d in $(SUBDIRS); do make -s -C $$d clean; done

subdirs:
	for d in $(SUBDIRS); do make -C $$d; [ $$? = 0 ] || exit 1; done

tarball: clean
	@rm -rf .koji-$(VERSION)
	@mkdir .koji-$(VERSION)
	@cp -rl $(SUBDIRS) Makefile *.spec .koji-$(VERSION)
	@mv .koji-$(VERSION) koji-$(VERSION)
	tar --bzip2 --exclude '*.tar.bz2' --exclude '*.rpm' --exclude '.#*' --exclude '.cvsignore' --exclude CVS \
	     -cpf koji-$(VERSION).tar.bz2 koji-$(VERSION)
	@rm -rf koji-$(VERSION)

srpm: tarball
	$(RPM_WITH_DIRS) $(DIST_DEFINES) -ts koji-$(VERSION).tar.bz2

rpm: tarball
	$(RPM_WITH_DIRS) $(DIST_DEFINES) -tb koji-$(VERSION).tar.bz2

tag::    $(SPECFILE)
	cvs tag $(TAG_OPTS) -c $(TAG)
	@echo "Tagged with: $(TAG)"
	@echo

# If and only if "make build" fails, use "make force-tag" to 
# re-tag the version.
force-tag: $(SPECFILE)
	@$(MAKE) tag TAG_OPTS="-F $(TAG_OPTS)"

DESTDIR ?= /
install:
	@if [ "$(DESTDIR)" = "" ]; then \
		echo " "; \
		echo "ERROR: A destdir is required"; \
		exit 1; \
	fi

	mkdir -p $(DESTDIR)

	for d in $(SUBDIRS); do make DESTDIR=`cd $(DESTDIR); pwd` \
		-C $$d install; [ $$? = 0 ] || exit 1; done