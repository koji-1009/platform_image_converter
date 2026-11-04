// ignore: implementation_imports
import 'package:platform_image_converter/src/android/bindings.g.dart'
    show Build$VERSION;

/// The API level of the Android device running the test.
int androidApiLevel() => Build$VERSION.SDK_INT;

/// The major and minor SDK version of the Android device running the test
/// (`Build.VERSION.SDK_INT_FULL`, API 36+).
int androidSdkFull() => Build$VERSION.SDK_INT_FULL;
