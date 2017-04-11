#ifndef MINIMAP_STANDALONE
extern GMainContext *g_main_context;
#endif

/*
 * Base event for clutter -> notion event types.
 */
typedef struct {
  Window win;
} ModClutterEvent;

extern void minimap_add_window(Window w);
extern void minimap_clear();
extern void minimap_run();
extern void clutter_eval_js(const char *js);
