// Regenerate bindings with `dart run ffigen_linux.dart`.
//
// Linux/GdkPixbuf counterpart of ffigen.dart (the Darwin config), using the
// same default @Native style. Every Flutter Linux app links the GTK embedder,
// which loads libgdk_pixbuf, so the gdk_pixbuf_*/g_* symbols live in the process
// and resolve through @Native — no explicit dlopen needed. (Verified: all 14
// symbols resolve via DynamicLibrary.process() in a real `-d linux` app.)
import 'package:ffigen/ffigen.dart';

final config = FfiGenerator(
  headers: Headers(entryPoints: [Uri.file('stub_headers/linux.h')]),
  output: Output(
    dartFile: Uri.file('lib/src/linux/bindings.g.dart'),
    // Default style is @Native external functions (like the Darwin config).
    // `any` comment style (not the default doxygen) so the stub's plain `//`
    // comments carry through as binding docs.
    commentType: const CommentType(CommentStyle.any, CommentLength.full),
  ),
  // The entry point is a hand-written stub (stub_headers/linux.h) that declares
  // ONLY the surface the backend uses, so includeAll on each category emits
  // exactly that surface — no system gdk-pixbuf.h, no transitive GLib/GObject
  // type graph (which would balloon the output ~50x).
  functions: const Functions(include: Declarations.includeAll),
  structs: const Structs(include: Declarations.includeAll),
  typedefs: const Typedefs(include: Declarations.includeAll),
  // GdkInterpType is a C enum whose integer width is implementation-defined;
  // ffigen mimics the common compiler choice (unsigned int on Linux/x64). The
  // example app's drive_linux integration test drives scale_simple with
  // GDK_INTERP_HYPER against the live library, so the width is verified, not
  // assumed. Silence the (now-checked) warning.
  enums: const Enums(include: Declarations.includeAll, silenceWarning: true),
);

void main() => config.generate();
