/*
 * ion/ioncore/frame-draw.c
 *
 * Copyright (c) Tuomo Valkonen 1999-2009.
 *
 * See the included file LICENSE for details.
 */

#include <string.h>

#include <libtu/objp.h>
#include <libtu/minmax.h>
#include <libtu/map.h>

#include "common.h"
#include "frame.h"
#include "framep.h"
#include "frame-draw.h"
#include "strings.h"
#include "activity.h"
#include "names.h"
#include "gr.h"
#include "gr-util.h"


#define BAR_INSIDE_BORDER(FRAME) \
    ((FRAME)->barmode==FRAME_BAR_INSIDE || (FRAME)->barmode==FRAME_BAR_NONE)
#define BAR_EXISTS(FRAME) ((FRAME)->barmode!=FRAME_BAR_NONE)
#define BAR_H(FRAME) (FRAME)->bar_h


/*{{{ Attributes */


GR_DEFATTR(active);
GR_DEFATTR(inactive);
GR_DEFATTR(selected);
GR_DEFATTR(unselected);
GR_DEFATTR(tagged);
GR_DEFATTR(not_tagged);
GR_DEFATTR(dragged);
GR_DEFATTR(not_dragged);
GR_DEFATTR(activity);
GR_DEFATTR(no_activity);


static void ensure_create_attrs()
{
    GR_ALLOCATTR_BEGIN;
    GR_ALLOCATTR(active);
    GR_ALLOCATTR(inactive);
    GR_ALLOCATTR(selected);
    GR_ALLOCATTR(unselected);
    GR_ALLOCATTR(tagged);
    GR_ALLOCATTR(not_tagged);
    GR_ALLOCATTR(dragged);
    GR_ALLOCATTR(not_dragged);
    GR_ALLOCATTR(no_activity);
    GR_ALLOCATTR(activity);
    GR_ALLOCATTR_END;
}


void frame_update_attr(WFrame *frame, int i, WRegion *reg)
{
    GrStyleSpec *spec;
    bool selected, tagged, dragged, activity;

    if(i>=frame->titles_n){
        /* Might happen when deinitialising */
        return;
    }

    ensure_create_attrs();

    spec=&frame->titles[i].attr;

    cairo_surface_t *tab_icon=frame->titles[i].icon;
    if(tab_icon){
        cairo_surface_destroy(tab_icon);
        tab_icon=NULL;
    }

    frame->titles[i].icon = reg ? region_icon(reg) : NULL;

    selected=(reg==FRAME_CURRENT(frame));
    tagged=(reg!=NULL && reg->flags&REGION_TAGGED);
    dragged=(i==frame->tab_dragged_idx);
    activity=(reg!=NULL && region_is_activity_r(reg));

    gr_stylespec_unalloc(spec);
    gr_stylespec_set(spec, selected ? GR_ATTR(selected) : GR_ATTR(unselected));
    gr_stylespec_set(spec, tagged ? GR_ATTR(tagged) : GR_ATTR(not_tagged));
    gr_stylespec_set(spec, dragged ? GR_ATTR(dragged) : GR_ATTR(not_dragged));
    gr_stylespec_set(spec, activity ? GR_ATTR(activity) : GR_ATTR(no_activity));
}


/*}}}*/


/*{{{ (WFrame) dynfun default implementations */


static uint get_spacing(const WFrame *frame)
{
    GrBorderWidths bdw;

    if(frame->brush==NULL)
        return 0;

    grbrush_get_border_widths(frame->brush, &bdw);

    return bdw.spacing;
}


void frame_border_geom(const WFrame *frame, WRectangle *geom)
{
    geom->x=0;
    geom->y=0;
    geom->w=REGION_GEOM(frame).w;
    geom->h=REGION_GEOM(frame).h;

    if(!BAR_INSIDE_BORDER(frame) && frame->brush!=NULL){
        geom->y+=frame->bar_h;
        geom->h=MAXOF(0, geom->h-frame->bar_h);
    }
}


void frame_border_inner_geom(const WFrame *frame, WRectangle *geom)
{
    GrBorderWidths bdw;

    frame_border_geom(frame, geom);

    if(frame->brush!=NULL){
        grbrush_get_border_widths(frame->brush, &bdw);

        geom->x+=bdw.left;
        geom->y+=bdw.top;
        geom->w=MAXOF(0, geom->w-(bdw.left+bdw.right));
        geom->h=MAXOF(0, geom->h-(bdw.top+bdw.bottom));
    }
}


void frame_bar_geom(const WFrame *frame, WRectangle *geom)
{
    uint off;

    if(BAR_INSIDE_BORDER(frame)){
        off=0; /*get_spacing(frame);*/
        frame_border_inner_geom(frame, geom);
    }else{
        off=0;
        geom->x=0;
        geom->y=0;
        geom->w=(frame->barmode==FRAME_BAR_SHAPED
                 ? frame->bar_w
                 : REGION_GEOM(frame).w);
    }
    geom->x+=off;
    geom->y+=off;
    geom->w=MAXOF(0, geom->w-2*off);
    geom->h=BAR_H(frame);
}


void frame_managed_geom(const WFrame *frame, WRectangle *geom)
{
    uint spacing=get_spacing(frame);

    frame_border_inner_geom(frame, geom);

    /*
    geom->x+=spacing;
    geom->y+=spacing;
    geom->w-=2*spacing;
    geom->h-=2*spacing;
    */

    if(BAR_INSIDE_BORDER(frame) && BAR_EXISTS(frame)){
        geom->y+=frame->bar_h+spacing;
        geom->h-=frame->bar_h+spacing;
    }

    geom->w=MAXOF(geom->w, 0);
    geom->h=MAXOF(geom->h, 0);
}


int frame_shaded_height(const WFrame *frame)
{
    if(frame->barmode==FRAME_BAR_NONE){
        return 0;
    }else if(!BAR_INSIDE_BORDER(frame)){
        return frame->bar_h;
    }else {
        GrBorderWidths bdw;

        grbrush_get_border_widths(frame->brush, &bdw);

        return frame->bar_h+bdw.top+bdw.bottom;
    }
}


void frame_set_shape(WFrame *frame)
{
    WRectangle gs[2];
    int n=0;

    if(frame->brush!=NULL){
        if(BAR_EXISTS(frame)){
            frame_bar_geom(frame, gs+n);
            n++;
        }
        frame_border_geom(frame, gs+n);
        n++;

        grbrush_set_window_shape(frame->brush, TRUE, n, gs);
    }
}


void frame_clear_shape(WFrame *frame)
{
    if(frame->brush!=NULL)
        grbrush_set_window_shape(frame->brush, TRUE, 0, NULL);
}


static void free_title(WFrame *frame, int i)
{
    if(frame->titles[i].text!=NULL){
        free(frame->titles[i].text);
        frame->titles[i].text=NULL;
    }
}


void frame_recalc_bar(WFrame *frame, bool complete)
{
    int textw, i;
    WLListIterTmp tmp;
    WRegion *sub;
    char *title;
    bool set_shape;

    if(frame->bar_brush==NULL || frame->titles==NULL)
        return;

    set_shape=frame->tabs_params.alg(frame,complete);

    if(set_shape) {
        if(frame->barmode==FRAME_BAR_SHAPED)
            frame_set_shape(frame);
        else
            frame_clear_shape(frame);
    }

    i=0;

    if(FRAME_MCOUNT(frame)==0){
        free_title(frame, i);
        textw=frame->titles[i].iw;
        if(textw>0){
            title=grbrush_make_label(frame->bar_brush, TR("<empty frame>"),
                                     textw);
            frame->titles[i].text=title;
        }
        return;
    }

    FRAME_MX_FOR_ALL(sub, frame, tmp){
        free_title(frame, i);
        textw=frame->titles[i].iw;
        if(textw>0){
            int icon_w=0;
            if(frame->show_icon){
                const cairo_surface_t *icon=region_icon(sub);
                if(icon) {
                    icon_w=cairo_image_surface_get_width(icon)+3;
                }
            }

            title=region_make_label(sub, textw-icon_w, frame->bar_brush);
            frame->titles[i].text=title;
        }
        i++;
    }
}


void frame_draw_bar(const WFrame *frame, bool complete)
{
    WRectangle geom;

    if(frame->bar_brush==NULL
       || !BAR_EXISTS(frame)
       || frame->titles==NULL){
        return;
    }

    frame_bar_geom(frame, &geom);

    grbrush_begin(frame->bar_brush, &geom, GRBRUSH_AMEND);

    grbrush_init_attr(frame->bar_brush, &frame->baseattr);

    grbrush_draw_textboxes(frame->bar_brush, &geom, frame->titles_n,
                           frame->titles, complete);

    grbrush_end(frame->bar_brush);
}

void frame_draw(const WFrame *frame, bool complete)
{
    WRectangle geom;

    if(frame->brush==NULL)
        return;

    frame_border_geom(frame, &geom);

    grbrush_begin(frame->brush, &geom, (complete ? 0 : GRBRUSH_NO_CLEAR_OK));

    grbrush_init_attr(frame->brush, &frame->baseattr);

    grbrush_draw_border(frame->brush, &geom);

    frame_draw_bar(frame, TRUE);

    grbrush_end(frame->brush);
}


void frame_brushes_updated(WFrame *frame)
{
    WFrameBarMode barmode;
    char *s;

    if(frame->brush==NULL)
        return;

    if(frame->mode==FRAME_MODE_FLOATING){
        barmode=FRAME_BAR_SHAPED;
    }else if(frame->mode==FRAME_MODE_TILED || frame->mode==FRAME_MODE_UNKNOWN ||
            frame->mode==FRAME_MODE_TRANSIENT_ALT){
        barmode=FRAME_BAR_INSIDE;
    }else{
        barmode=FRAME_BAR_NONE;
    }

    if(grbrush_get_extra(frame->brush, "bar", 's', &s)){
        if(strcmp(s, "inside")==0)
            barmode=FRAME_BAR_INSIDE;
        else if(strcmp(s, "outside")==0)
            barmode=FRAME_BAR_OUTSIDE;
        else if(strcmp(s, "shaped")==0)
            barmode=FRAME_BAR_SHAPED;
        else if(strcmp(s, "none")==0)
            barmode=FRAME_BAR_NONE;
        free(s);
    }

    grbrush_get_extra(frame->bar_brush, "show_icon", 'b', &frame->show_icon);

    frame->barmode=barmode;

    if(barmode==FRAME_BAR_NONE || frame->bar_brush==NULL){
        frame->bar_h=0;
    }else{
        GrBorderWidths bdw;
        GrFontExtents fnte;

        grbrush_get_border_widths(frame->bar_brush, &bdw);
        grbrush_get_font_extents(frame->bar_brush, &fnte);

        int inner_h=frame->show_icon ? MAXOF(fnte.max_height,16) : fnte.max_height;

        frame->bar_h=bdw.top+bdw.bottom+inner_h;
    }

    /* tabs and bar width calculation stuff */
    frame_tabs_calc_brushes_updated(frame);
}


/*}}}*/


/*{{{ Misc. */


void frame_updategr(WFrame *frame)
{
    frame_release_brushes(frame);

    frame_initialise_gr(frame);

    /* Update children */
    region_updategr_default((WRegion*)frame);

    mplex_fit_managed(&frame->mplex);
    frame_recalc_bar(frame, TRUE);
    frame_set_background(frame, TRUE);
}


static StringIntMap frame_tab_styles[]={
    {"tab-frame-unknown", FRAME_MODE_UNKNOWN},
    {"tab-frame-unknown-alt", FRAME_MODE_UNKNOWN_ALT},
    {"tab-frame-tiled", FRAME_MODE_TILED},
    {"tab-frame-tiled-alt", FRAME_MODE_TILED_ALT},
    {"tab-frame-floating", FRAME_MODE_FLOATING},
    {"tab-frame-floating-alt", FRAME_MODE_FLOATING_ALT},
    {"tab-frame-transient", FRAME_MODE_TRANSIENT},
    {"tab-frame-transient-alt", FRAME_MODE_TRANSIENT_ALT},
    END_STRINGINTMAP
};


const char *framemode_get_tab_style(WFrameMode mode)
{
    return stringintmap_key(frame_tab_styles, mode, "tab-frame");
}


const char *framemode_get_style(WFrameMode mode)
{
    const char *p=framemode_get_tab_style(mode);
    assert(p!=NULL);
    return (p+4);
}


void frame_initialise_gr(WFrame *frame)
{
    Window win=frame->mplex.win.win;
    WRootWin *rw=region_rootwin_of((WRegion*)frame);
    const char *style=framemode_get_style(frame->mode);
    const char *tab_style=framemode_get_tab_style(frame->mode);

    frame->brush=gr_get_brush(win, rw, style);

    if(frame->brush==NULL)
        return;

    frame->bar_brush=grbrush_get_slave(frame->brush, rw, tab_style);

    if(frame->bar_brush==NULL)
        return;

    frame_brushes_updated(frame);
}


void frame_release_brushes(WFrame *frame)
{
    if(frame->bar_brush!=NULL){
        grbrush_release(frame->bar_brush);
        frame->bar_brush=NULL;
    }

    if(frame->brush!=NULL){
        grbrush_release(frame->brush);
        frame->brush=NULL;
    }
}


bool frame_set_background(WFrame *frame, bool set_always)
{
    GrTransparency mode=GR_TRANSPARENCY_DEFAULT;

    if(FRAME_CURRENT(frame)!=NULL){
        if(OBJ_IS(FRAME_CURRENT(frame), WClientWin)){
            WClientWin *cwin=(WClientWin*)FRAME_CURRENT(frame);
            mode=(cwin->flags&CLIENTWIN_PROP_TRANSPARENT
                  ? GR_TRANSPARENCY_YES : GR_TRANSPARENCY_NO);
        }else if(!OBJ_IS(FRAME_CURRENT(frame), WGroup)){
            mode=GR_TRANSPARENCY_NO;
        }
    }

    if(mode!=frame->tr_mode || set_always){
        frame->tr_mode=mode;
        if(frame->brush!=NULL){
            grbrush_enable_transparency(frame->brush, mode);
            window_draw((WWindow*)frame, TRUE);
        }
        return TRUE;
    }

    return FALSE;
}


void frame_setup_dragwin_style(WFrame *frame, GrStyleSpec *spec, int tab)
{
    gr_stylespec_append(spec, &frame->baseattr);
    gr_stylespec_append(spec, &frame->titles[tab].attr);
}


/*}}}*/


/*{{{ Activated/inactivated */


void frame_inactivated(WFrame *frame)
{
    ensure_create_attrs();

    gr_stylespec_set(&frame->baseattr, GR_ATTR(inactive));
    gr_stylespec_unset(&frame->baseattr, GR_ATTR(active));

    window_draw((WWindow*)frame, FALSE);
}


void frame_activated(WFrame *frame)
{
    ensure_create_attrs();

    gr_stylespec_set(&frame->baseattr, GR_ATTR(active));
    gr_stylespec_unset(&frame->baseattr, GR_ATTR(inactive));

    window_draw((WWindow*)frame, FALSE);
}


/*}}}*/

