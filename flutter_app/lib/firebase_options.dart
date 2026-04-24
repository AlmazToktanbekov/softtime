// File generated manually for Firebase configuration.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('DefaultFirebaseOptions have not been configured for web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Using iOS options as fallback since android is not requested yet
        return ios;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAJ3IvMXg2vP6qmeITl0te3j_aesxU_20o',
    appId: '1:701430347456:ios:e612f3434120e25c08df25',
    messagingSenderId: '701430347456',
    projectId: 'softjol-11565',
    storageBucket: 'softjol-11565.firebasestorage.app',
    iosBundleId: 'com.thekuba.softtime',
  );
}
