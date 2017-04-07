##
## Notion clutter module Makefile
##
##

# System specific configuration is in system.mk
TOPDIR=..
include $(TOPDIR)/build/system-inc.mk

######################################

INCLUDES += $(X11_INCLUDES) $(LIBTU_INCLUDES) $(LIBEXTL_INCLUDES) -I..
CFLAGS += $(XOPEN_SOURCE) $(C99_SOURCE) `pkg-config --cflags clutter-glx-1.0` \
	-Wno-unused-parameter
LIBS += `pkg-config --libs clutter-glx-1.0` -lpthread

SOURCES=main.c minimap.c
DOCS=LICENSE

MAKE_EXPORTS=mod_clutter

MODULE=mod_clutter

######################################

include $(TOPDIR)/build/rules.mk

######################################

_install: module_install

######################################

main.o: exports.h

.PHONY: tags
tags:
	exuberant-ctags -R . $(TOPDIR)
