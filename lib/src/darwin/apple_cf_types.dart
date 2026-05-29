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
