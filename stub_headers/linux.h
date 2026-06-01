// Minimal stub of the GdkPixbuf / GLib surface used by the Linux backend.
//
// ffigen parses ONLY this header, so `lib/src/linux/bindings.g.dart` contains
// exactly the declarations below — none of GLib/GObject's huge transitive type
// graph. The signatures and the struct/enum layouts mirror the real headers
//   gdk-pixbuf-2.0/gdk-pixbuf/gdk-pixbuf.h  and  glib-2.0/glib/*.h
// and are kept honest by the headless conversion test, which drives the live
// library on Linux CI (test/linux_conversion_test.dart): an ABI mismatch
// between this stub and the installed library would crash or misbehave there.
//
// To change the surface: edit this header, then regenerate with
//   dart run ffigen --config ffigen.yaml

// --- GLib primitive typedefs (stable across the GLib 2.x ABI) ---
typedef int gint;
typedef gint gboolean;
typedef char gchar;
typedef unsigned char guchar;
typedef unsigned long gsize;
typedef unsigned int guint32;
typedef guint32 GQuark;
typedef void *gpointer;

// --- Opaque types: only ever held by pointer ---
// Underscore-free tags so ffigen emits public `GdkPixbuf`/… opaque classes
// (a `struct _Gdk*` tag would be generated as a private `_Gdk*` class).
typedef struct GdkPixbuf GdkPixbuf;
typedef struct GdkPixbufLoader GdkPixbufLoader;
typedef struct GdkPixbufFormat GdkPixbufFormat;

// --- GError: only `message` is read by the backend ---
// Anonymous tag so ffigen names the Dart class `GError` (a leading-underscore
// C tag like the real `struct _GError` would be emitted as a private class).
typedef struct {
  GQuark domain;
  gint code;
  gchar *message;
} GError;

// --- GSList: singly linked list node; `data` holds a GdkPixbufFormat* ---
// Needs a tag for the self-reference; keep it underscore-free for the same
// reason as GError above.
typedef struct GSList {
  gpointer data;
  struct GSList *next;
} GSList;

// --- GdkInterpType: the backend uses GDK_INTERP_HYPER (== 3) ---
typedef enum {
  GDK_INTERP_NEAREST = 0,
  GDK_INTERP_TILES = 1,
  GDK_INTERP_BILINEAR = 2,
  GDK_INTERP_HYPER = 3,
} GdkInterpType;

// --- GdkPixbuf (libgdk_pixbuf-2.0) ---
GdkPixbufLoader *gdk_pixbuf_loader_new(void);
gboolean gdk_pixbuf_loader_write(GdkPixbufLoader *loader, const guchar *buf,
                                 gsize count, GError **error);
gboolean gdk_pixbuf_loader_close(GdkPixbufLoader *loader, GError **error);
GdkPixbuf *gdk_pixbuf_loader_get_pixbuf(GdkPixbufLoader *loader);
int gdk_pixbuf_get_width(const GdkPixbuf *pixbuf);
int gdk_pixbuf_get_height(const GdkPixbuf *pixbuf);
GdkPixbuf *gdk_pixbuf_scale_simple(const GdkPixbuf *src, int dest_width,
                                   int dest_height, GdkInterpType interp_type);
GdkPixbuf *gdk_pixbuf_apply_embedded_orientation(GdkPixbuf *src);
gboolean gdk_pixbuf_save_to_bufferv(GdkPixbuf *pixbuf, gchar **buffer,
                                    gsize *buffer_size, const char *type,
                                    char **option_keys, char **option_values,
                                    GError **error);
GSList *gdk_pixbuf_get_formats(void);
gchar *gdk_pixbuf_format_get_name(GdkPixbufFormat *format);
gboolean gdk_pixbuf_format_is_writable(GdkPixbufFormat *format);

// --- GLib / GObject memory management ---
void g_free(gpointer mem);
void g_slist_free(GSList *list);
void g_error_free(GError *error);
void g_object_unref(gpointer object);
