
prefix ?= /usr/local
bindir = $(prefix)/bin
datadir = $(prefix)/share/canfar

INSTALL = install -c
INSTALL_SCRIPT = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644
MKDIR_P = mkdir -p
RM = rm -f

SCRIPTS = canfar_submit canfar_job_validate cansub
DATA = canfar_batch_setup.bash canfarcs_id_rsa.pub

install: 
	@$(MKDIR_P) $(DESTDIR)$(bindir) ; \
	for script in $(SCRIPTS); do \
		echo " $(INSTALL_SCRIPT) $$script $(DESTDIR)$(bindir)/$$script" ; \
		$(INSTALL_SCRIPT) $$script $(DESTDIR)$(bindir)/$$script ; \
	done
	@$(MKDIR_P) $(DESTDIR)$(datadir) ; \
	for data in $(DATA); do \
		echo " $(INSTALL_DATA) $$data $(DESTDIR)$(datadir)/$$data" ; \
		$(INSTALL_DATA) $$data $(DESTDIR)$(datadir)/$$data ; \
	done

uninstall:
	@for script in $(SCRIPTS); do \
		echo " $(RM) $(DESTDIR)$(bindir)/$$script" ; \
		$(RM) $(DESTDIR)$(bindir)/$$script ; \
	done
	@for data in $(DATA); do \
		echo " $(RM) $(DESTDIR)$(datadir)/$$data" ; \
		$(RM) $(DESTDIR)$(datadir)/$$data ; \
	done
