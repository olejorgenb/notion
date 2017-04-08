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

/* #include "query.h" */
/* #include "edln.h" */
/* #include "wedln.h" */
/* #include "input.h" */
/* #include "complete.h" */
/* #include "history.h" */
#include "exports.h"
/* #include "main.h" */
#include <pthread.h>

#include <glib.h>

#include "minimap.h"

GMainContext *g_main_context;

/*{{{ Module information */

#include "../version.h"

char mod_clutter_ion_api_version[]=NOTION_API_VERSION;


/*}}}*/

void mod_clutter_deinit()
{
    mod_clutter_unregister_exports();
}

static
void *
start_thread(void *arg)
{
    minimap_run();
    return NULL;
}


EXTL_EXPORT
void mod_clutter_minimap_run()
{
    gchar *name = "minimap";
    GThread *thread = g_thread_new(name, &start_thread, NULL);
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


    return TRUE;

err:
    mod_clutter_deinit();
    return FALSE;
}

