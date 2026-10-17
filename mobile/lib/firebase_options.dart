import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// Default FirebaseOptions for use with your Firebase apps.
/// Generated for Android package: com.dgs.chatspace
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyARULWNr8f6_NkjSKnLnNmfT7RsZJVoFX8',
    appId: '1:714556716:android:8b85fa1f1ce81f5b075889',
    messagingSenderId: '714556716',
    projectId: 'chatspace-android',
    storageBucket: 'chatspace-android.firebasestorage.app',
  );
}
