/*
 * ion/ioncore/pseudowin.h
 *
 * Copyright (c) Tuomo Valkonen 1999-2009.
 *
 * See the included file LICENSE for details.
 */

#include <string.h>

#include <libtu/objp.h>
#include "common.h"
#include "global.h"
#include "window.h"
#include "pseudowin.h"
#include "resize.h"
#include "gr.h"
#include "event.h"
#include "strings.h"


/*{{{ Init/deinit */


bool pseudowin_init(WPseudoWin *p, WWindow *parent, const WFitParams *fp,
                  const char *style)
{
    XSetWindowAttributes attr;

    if(!window_init(&(p->wwin), parent, fp, "WPseudoWin"))
        return FALSE;

    p->buffer=ALLOC_N(char, PSEUDOWIN_BUFFER_LEN);
    if(p->buffer==NULL)
        goto fail;
    p->buffer[0]='\0';

    if(style==NULL)
        p->style=scopy("*");
    else
        p->style=scopy(style);
    if(p->style==NULL)
        goto fail2;

    p->brush=NULL;

    gr_stylespec_init(&p->attr);

    pseudowin_updategr(p);

    if(p->brush==NULL)
        goto fail3;

    /* Enable save unders */
    attr.save_under=True;
    XChangeWindowAttributes(ioncore_g.dpy, p->wwin.win, CWSaveUnder, &attr);

    window_select_input(&(p->wwin), IONCORE_EVENTMASK_NORMAL);

    return TRUE;

fail3:
    gr_stylespec_unalloc(&p->attr);
    free(p->style);
fail2:
    free(p->buffer);
fail:
    window_deinit(&(p->wwin));
    return FALSE;
}


WPseudoWin *create_pseudowin(WWindow *parent, const WFitParams *fp,
                         const char *style)
{
    CREATEOBJ_IMPL(WPseudoWin, pseudowin, (p, parent, fp, style));
}


void pseudowin_deinit(WPseudoWin *p)
{
    if(p->buffer!=NULL){
        free(p->buffer);
        p->buffer=NULL;
    }

    if(p->style!=NULL){
        free(p->style);
        p->style=NULL;
    }

    if(p->brush!=NULL){
        grbrush_release(p->brush);
        p->brush=NULL;
    }

    gr_stylespec_unalloc(&p->attr);

    window_deinit(&(p->wwin));
}


/*}}}*/


/*{{{ Drawing and geometry */


void pseudowin_draw(WPseudoWin *p, bool UNUSED(complete))
{
    WRectangle g;

    if(p->brush==NULL)
        return;

    g.x=0;
    g.y=0;
    g.w=REGION_GEOM(p).w;
    g.h=REGION_GEOM(p).h;

    grbrush_begin(p->brush, &g, GRBRUSH_NO_CLEAR_OK);
    grbrush_init_attr(p->brush, &p->attr);
    grbrush_draw_textbox(p->brush, &g, p->buffer, TRUE);
    grbrush_end(p->brush);
}


void pseudowin_updategr(WPseudoWin *p)
{
    GrBrush *nbrush;

    assert(p->style!=NULL);

    nbrush=gr_get_brush(p->wwin.win,
                        region_rootwin_of((WRegion*)p),
                        p->style);
    if(nbrush==NULL)
        return;

    if(p->brush!=NULL)
        grbrush_release(p->brush);

    p->brush=nbrush;

    window_draw(&(p->wwin), TRUE);
}



/*}}}*/


/*{{{ Content-setting */


GrStyleSpec *pseudowin_stylespec(WPseudoWin *p)
{
    return &p->attr;
}


static void pseudowin_do_set_text(WPseudoWin *p, const char *str)
{
    strncpy(PSEUDOWIN_BUFFER(p), str, PSEUDOWIN_BUFFER_LEN);
    PSEUDOWIN_BUFFER(p)[PSEUDOWIN_BUFFER_LEN-1]='\0';
}


static void pseudowin_resize(WPseudoWin *p)
{
    WRQGeomParams rq=RQGEOMPARAMS_INIT;
    const char *str=PSEUDOWIN_BUFFER(p);
    GrBorderWidths bdw;
    GrFontExtents fnte;

    rq.flags=REGION_RQGEOM_WEAK_X|REGION_RQGEOM_WEAK_Y;

    rq.geom.x=REGION_GEOM(p).x;
    rq.geom.y=REGION_GEOM(p).y;

    grbrush_get_border_widths(p->brush, &bdw);
    grbrush_get_font_extents(p->brush, &fnte);

    rq.geom.w=bdw.left+bdw.right;
    rq.geom.w+=grbrush_get_text_width(p->brush, str, strlen(str));
    rq.geom.h=fnte.max_height+bdw.top+bdw.bottom;

    if(rectangle_compare(&rq.geom, &REGION_GEOM(p))!=RECTANGLE_SAME)
        region_rqgeom((WRegion*)p, &rq, NULL);
}


/*EXTL_DOC
 * Set contents of the info window.
 */
EXTL_EXPORT_MEMBER
void pseudowin_set_text(WPseudoWin *p, const char *str, int maxw)
{
    bool set=FALSE;

    if(str==NULL){
        PSEUDOWIN_BUFFER(p)[0]='\0';
    }else{
        if(maxw>0 && p->brush!=NULL){
            char *tmp=grbrush_make_label(p->brush, str, maxw);
            if(tmp!=NULL){
                pseudowin_do_set_text(p, tmp);
                free(tmp);
                set=TRUE;
            }
        }

        if(!set)
            pseudowin_do_set_text(p, str);
    }

    pseudowin_resize(p);

    /* sometimes unnecessary */
    window_draw((WWindow*)p, TRUE);
}


/*}}}*/


/*{{{ Load */


WRegion *pseudowin_load(WWindow *par, const WFitParams *fp, ExtlTab tab) // Mark
{
    char *style=NULL, *text=NULL;
    WPseudoWin *p;

    extl_table_gets_s(tab, "style", &style);

    p=create_pseudowin(par, fp, style);

    free(style);

    if(p==NULL)
        return NULL;

    if(extl_table_gets_s(tab, "text", &text)){
        pseudowin_do_set_text(p, text);
        free(text);
    }

    return (WRegion*)p;
}


/*}}}*/


/*{{{ Dynamic function table and class implementation */


static DynFunTab pseudowin_dynfuntab[]={
    {window_draw, pseudowin_draw},
    {region_updategr, pseudowin_updategr},
    /* {(DynFun*)region_icon, */
    /*  (DynFun*)pseudowin_icon}, */
    
    END_DYNFUNTAB
};


EXTL_EXPORT
IMPLCLASS(WPseudoWin, WWindow, pseudowin_deinit, pseudowin_dynfuntab);


/*}}}*/
