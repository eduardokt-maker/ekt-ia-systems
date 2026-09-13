import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeSessionStore {
  static const channel = MethodChannel('com.ektiasystems/session');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<String?> read() async =>
      supported ? await channel.invokeMethod<String>('read') : null;
  Future<void> write(String value) async {
    if (supported) await channel.invokeMethod<void>('write', value);
  }

  Future<void> clear() async {
    if (supported) await channel.invokeMethod<void>('clear');
  }
}
