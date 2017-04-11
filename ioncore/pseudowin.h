/*
 * ion/ioncore/pseudowin.h
 *
 * Copyright (c) Tuomo Valkonen 1999-2009.
 *
 * See the included file LICENSE for details.
 */

#ifndef ION_IONCORE_PSEUDOWIN_H
#define ION_IONCORE_PSEUDOWIN_H

#include "common.h"
#include "window.h"
#include "gr.h"
#include "rectangle.h"

#define PSEUDOWIN_BUFFER_LEN 256

DECLCLASS(WPseudoWin){
    WWindow wwin;
    Watch real_watch;
    GrBrush *brush;
    char *buffer;
    char *style;
    GrStyleSpec attr;
};

#define PSEUDOWIN_REAL(PSEUDOWIN) ((WRegion*)(PSEUDOWIN)->real_watch.obj)

#define PSEUDOWIN_BRUSH(PSEUDOWIN) ((PSEUDOWIN)->brush)
#define PSEUDOWIN_BUFFER(PSEUDOWIN) ((PSEUDOWIN)->buffer)

extern bool pseudowin_init(WPseudoWin *p, WWindow *parent, const WFitParams *fp,
                           const char *style, WRegion *real);
extern WPseudoWin *create_pseudowin(WWindow *parent, const WFitParams *fp,
                                    const char *style, WRegion *real);

extern void pseudowin_deinit(WPseudoWin *p);

extern void pseudowin_set_text(WPseudoWin *p, const char *s, int maxw);
extern GrStyleSpec *pseudowin_stylespec(WPseudoWin *p);

extern WRegion *pseudowin_load(WWindow *par, const WFitParams *fp, ExtlTab tab);

extern void pseudowin_updategr(WPseudoWin *p);

extern WRegion *pseudowin_real(WPseudoWin *p);

#endif /* ION_IONCORE_PSEUDOWIN_H */
