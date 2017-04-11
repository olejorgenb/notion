/*
 * ion/mod_clutter/main.c
 *
 * Copyright (c) Tuomo Valkonen 1999-2009.
 *
 * See the included file LICENSE for details.
 */

#include <libextl/readconfig.h>
#include <libextl/extl.h>
#include <libtu/minmax.h>
#include <ioncore/binding.h>
#include <ioncore/conf-bindings.h>
#include <ioncore/frame.h>
#include <ioncore/saveload.h>
#include <ioncore/bindmaps.h>
#include <ioncore/ioncore.h>

#include <libmainloop/defer.h>
#include <libmainloop/signal.h>

/* #include "query.h" */
/* #include "edln.h" */
/* #include "wedln.h" */
/* #include "input.h" */
/* #include "complete.h" */
/* #include "history.h" */
#include "exports.h"
/* #include "main.h" */

#include <glib.h>

#include <gjs/gjs.h>
#include <gio/gio.h>
#include <girepository.h>

#include "minimap.h"

GMainContext *g_main_context;

/* The clutter thread adds event to this queue, to be picked up by notion's mainloop */
static GAsyncQueue  *clutter_to_notion_queue;
static WTimer* clutter_event_timer   = NULL;
static unsigned int clutter_poll_interval = 50;

/*{{{ Module information */

#include "../version.h"

char mod_clutter_ion_api_version[]=NOTION_API_VERSION;


/*}}}*/

void mod_clutter_deinit()
{
    mod_clutter_unregister_exports();
}

void process_clutter_events()
{
    while(TRUE){
        gpointer event = g_async_queue_try_pop(clutter_to_notion_queue);
        if(event==NULL){
            break;
        }

        printf("event received %d\n", ((int)event));
    }
}

void poll_clutter_events(WTimer* timer, Obj* UNUSED(dummy2))
{
    process_clutter_events();

    timer_set(clutter_event_timer, clutter_poll_interval,
              (WTimerHandler*)poll_clutter_events, NULL);
}

static
void *
start_thread(void *arg)
{
    minimap_run(clutter_to_notion_queue);
    return NULL;
}

EXTL_EXPORT
void mod_clutter_eval_js(const char *js)
{
    g_idle_add(clutter_eval_js, (gpointer)js);
}


EXTL_EXPORT
void mod_clutter_minimap_run()
{
    gchar *name = "minimap";
    GThread *thread = g_thread_new(name, &start_thread, NULL);

    poll_clutter_events(NULL, NULL);
}

EXTL_EXPORT
void mod_clutter_minimap_add_window(WRegion *wwin_reg)
{
    WWindow *wwin = OBJ_CAST(wwin_reg, WWindow);
    if(wwin==NULL)
        return;

    /* HACK: pass the int directly through the pointer */
    g_idle_add(&minimap_add_window, (gpointer)wwin->win);
}

EXTL_EXPORT
void mod_clutter_minimap_clear() {
    g_idle_add(&minimap_clear, NULL);
}


bool mod_clutter_init()
{
    if(!mod_clutter_register_exports())
        goto err;

    clutter_to_notion_queue = g_async_queue_new();
    clutter_event_timer = create_timer();


    return TRUE;

err:
    mod_clutter_deinit();
    return FALSE;
}

