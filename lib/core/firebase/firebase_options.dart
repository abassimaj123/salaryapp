// Generated from google-services.json — project android-app-54282
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Unsupported platform');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAVdM2OBORjb4fgCtWiqCwOJkkc5yhPRSY',
    appId: '1:385086392226:android:d4437b5c04dce5f1a6d4fb',
    messagingSenderId: '385086392226',
    projectId: 'android-app-54282',
    storageBucket: 'android-app-54282.firebasestorage.app',
  );
}
