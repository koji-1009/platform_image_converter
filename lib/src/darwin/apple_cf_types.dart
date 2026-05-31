import 'dart:ffi' as ffi;

/// CoreFoundation / CoreGraphics types that ffigen otherwise sources from
/// `package:objective_c` via its built-in type table. Defined locally and
/// wired in through ffigen's `importedTypesByUsr` so the Darwin bindings carry
/// no `objective_c` dependency. Only their pointers/fields are used here.

/// Opaque CoreFoundation `CFString`.
final class CFString extends ffi.Opaque {}

/// CoreGraphics `CGPoint`. `CGFloat` is a 64-bit `double` on all current Apple
/// ABIs (arm64 / x86_64).
final class CGPoint extends ffi.Struct {
  @ffi.Double()
  external double x;

  @ffi.Double()
  external double y;
}

/// CoreGraphics `CGSize`.
final class CGSize extends ffi.Struct {
  @ffi.Double()
  external double width;

  @ffi.Double()
  external double height;
}

/// CoreGraphics `CGRect` (`{CGPoint origin; CGSize size;}`).
final class CGRect extends ffi.Struct {
  external CGPoint origin;

  external CGSize size;
}

/// CoreGraphics `CGAffineTransform` (`{CGFloat a, b, c, d, tx, ty;}`). Maps a
/// user-space point `(x, y)` to `(a*x + c*y + tx, b*x + d*y + ty)`. Passed by
/// value to `CGContextConcatCTM` to apply the EXIF orientation transform.
final class CGAffineTransform extends ffi.Struct {
  @ffi.Double()
  external double a;

  @ffi.Double()
  external double b;

  @ffi.Double()
  external double c;

  @ffi.Double()
  external double d;

  @ffi.Double()
  external double tx;

  @ffi.Double()
  external double ty;
}
