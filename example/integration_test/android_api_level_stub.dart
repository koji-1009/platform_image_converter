/// The API level of the Android device running the test. Never called on Web,
/// which has no Android API level.
int androidApiLevel() =>
    throw UnsupportedError('No Android API level on this platform.');
