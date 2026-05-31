// Field/parameter names deliberately mirror the GLib / GdkPixbuf C names.
// ignore_for_file: non_constant_identifier_names
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Hand-written FFI bindings for GdkPixbuf — the imaging library in the
/// GLib/GTK stack that every Flutter Linux app already links (the GTK embedder
/// depends on it). Binding it adds no native build step and no extra packaging:
/// the shared objects are resolved at runtime with [DynamicLibrary.open].
///
/// GdkPixbuf decodes through dynamically-loaded *loader modules* and encodes
/// through those same modules' optional save support. JPEG and PNG are built in
/// and effectively always present; WebP and HEIF are separate loader packages
/// whose availability — and whether they can *write*, not just read — varies by
/// distribution. The backend surfaces that runtime variance as an
/// `UnsupportedFormatException` with reason `codecUnavailable` rather than a
/// hard failure (see `gdkPixbufFormatIsWritable`).
///
/// Written by hand rather than generated: ffigen would require the GdkPixbuf and
/// GLib development headers at generation time, while the surface used here is
/// tiny and has been ABI-stable across the entire GLib/GdkPixbuf 2.x series.
/// Every symbol resolves lazily, so the `DynamicLibrary.open` calls only run
/// when the converter is instantiated — i.e. only on Linux.

/// Opens the first of [sonames] that loads, trying the versioned runtime name
/// before the unversioned `-dev` symlink. Throws if none are present.
DynamicLibrary _open(List<String> sonames) {
  Object? lastError;
  for (final soname in sonames) {
    try {
      return DynamicLibrary.open(soname);
    } catch (error) {
      lastError = error;
    }
  }
  throw ArgumentError('Failed to load any of $sonames: $lastError');
}

final DynamicLibrary _glib = _open(['libglib-2.0.so.0', 'libglib-2.0.so']);
final DynamicLibrary _gobject = _open([
  'libgobject-2.0.so.0',
  'libgobject-2.0.so',
]);
final DynamicLibrary _gdkPixbuf = _open([
  'libgdk_pixbuf-2.0.so.0',
  'libgdk_pixbuf-2.0.so',
]);

/// `GError` — `{ GQuark domain; gint code; gchar *message; }`. Only [message]
/// is read; it is surfaced in the thrown exception.
final class GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Utf8> message;
}

/// `GSList` — a singly linked list node; [data] holds a `GdkPixbufFormat *`.
final class GSList extends Struct {
  external Pointer<Void> data;

  external Pointer<GSList> next;
}

/// `GDK_INTERP_HYPER` — the highest-quality (bicubic-like) resampling filter,
/// matching the high-quality intent of the other backends' downscaling.
const int gdkInterpHyper = 3;

// ---------------------------------------------------------------------------
// GLib (libglib-2.0)
// ---------------------------------------------------------------------------

/// `void g_free (gpointer mem)`.
final void Function(Pointer<Void>) gFree = _glib
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'g_free',
    );

/// `void g_slist_free (GSList *list)`.
final void Function(Pointer<GSList>) gSListFree = _glib
    .lookupFunction<
      Void Function(Pointer<GSList>),
      void Function(Pointer<GSList>)
    >('g_slist_free');

/// `void g_error_free (GError *error)`.
final void Function(Pointer<GError>) gErrorFree = _glib
    .lookupFunction<
      Void Function(Pointer<GError>),
      void Function(Pointer<GError>)
    >('g_error_free');

// ---------------------------------------------------------------------------
// GObject (libgobject-2.0)
// ---------------------------------------------------------------------------

/// `void g_object_unref (gpointer object)`.
final void Function(Pointer<Void>) gObjectUnref = _gobject
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'g_object_unref',
    );

// ---------------------------------------------------------------------------
// GdkPixbuf (libgdk_pixbuf-2.0)
// ---------------------------------------------------------------------------

/// `GdkPixbufLoader *gdk_pixbuf_loader_new (void)`.
final Pointer<Void> Function() gdkPixbufLoaderNew = _gdkPixbuf
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'gdk_pixbuf_loader_new',
    );

/// `gboolean gdk_pixbuf_loader_write (GdkPixbufLoader *, const guchar *buf,
/// gsize count, GError **error)`. The loader copies `buf`, so it need not
/// outlive the call.
final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Pointer<GError>>)
gdkPixbufLoaderWrite = _gdkPixbuf
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Uint8>,
        Size,
        Pointer<Pointer<GError>>,
      ),
      int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Pointer<GError>>)
    >('gdk_pixbuf_loader_write');

/// `gboolean gdk_pixbuf_loader_close (GdkPixbufLoader *, GError **error)`.
final int Function(Pointer<Void>, Pointer<Pointer<GError>>)
gdkPixbufLoaderClose = _gdkPixbuf
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<GError>>),
      int Function(Pointer<Void>, Pointer<Pointer<GError>>)
    >('gdk_pixbuf_loader_close');

/// `GdkPixbuf *gdk_pixbuf_loader_get_pixbuf (GdkPixbufLoader *)` — returns a
/// borrowed reference owned by the loader; do not unref it.
final Pointer<Void> Function(Pointer<Void>) gdkPixbufLoaderGetPixbuf =
    _gdkPixbuf.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('gdk_pixbuf_loader_get_pixbuf');

/// `int gdk_pixbuf_get_width (const GdkPixbuf *)`.
final int Function(Pointer<Void>) gdkPixbufGetWidth = _gdkPixbuf
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'gdk_pixbuf_get_width',
    );

/// `int gdk_pixbuf_get_height (const GdkPixbuf *)`.
final int Function(Pointer<Void>) gdkPixbufGetHeight = _gdkPixbuf
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'gdk_pixbuf_get_height',
    );

/// `GdkPixbuf *gdk_pixbuf_scale_simple (const GdkPixbuf *src, int dest_width,
/// int dest_height, GdkInterpType interp_type)` — returns a new reference the
/// caller owns and must unref.
final Pointer<Void> Function(Pointer<Void>, int, int, int)
gdkPixbufScaleSimple = _gdkPixbuf
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Int32, Int32, Int32),
      Pointer<Void> Function(Pointer<Void>, int, int, int)
    >('gdk_pixbuf_scale_simple');

/// `gboolean gdk_pixbuf_save_to_bufferv (GdkPixbuf *, gchar **buffer,
/// gsize *buffer_size, const char *type, char **option_keys,
/// char **option_values, GError **error)`. On success `*buffer` is a freshly
/// allocated block the caller must release with [gFree].
final int Function(
  Pointer<Void>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<GError>>,
)
gdkPixbufSaveToBufferv = _gdkPixbuf
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Pointer<Uint8>>,
        Pointer<Size>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<GError>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Pointer<Uint8>>,
        Pointer<Size>,
        Pointer<Utf8>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<GError>>,
      )
    >('gdk_pixbuf_save_to_bufferv');

/// `GSList *gdk_pixbuf_get_formats (void)` — list of `GdkPixbufFormat *`. The
/// list (but not the formats, which are owned by GdkPixbuf) must be freed with
/// [gSListFree].
final Pointer<GSList> Function() gdkPixbufGetFormats = _gdkPixbuf
    .lookupFunction<Pointer<GSList> Function(), Pointer<GSList> Function()>(
      'gdk_pixbuf_get_formats',
    );

/// `gchar *gdk_pixbuf_format_get_name (GdkPixbufFormat *)` — a freshly allocated
/// string the caller must release with [gFree].
final Pointer<Utf8> Function(Pointer<Void>) gdkPixbufFormatGetName = _gdkPixbuf
    .lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)
    >('gdk_pixbuf_format_get_name');

/// `gboolean gdk_pixbuf_format_is_writable (GdkPixbufFormat *)`.
final int Function(Pointer<Void>) gdkPixbufFormatIsWritable = _gdkPixbuf
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'gdk_pixbuf_format_is_writable',
    );
