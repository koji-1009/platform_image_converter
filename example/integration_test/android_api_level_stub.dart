/// The API level of the Android device running the test. Never called on Web,
/// which has no Android API level.
int androidApiLevel() =>
    throw UnsupportedError('No Android API level on this platform.');

/// The major and minor SDK version of the Android device running the test.
/// Never called on Web.
int androidSdkFull() =>
    throw UnsupportedError('No Android SDK version on this platform.');
