import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedStatementFile {
  const SharedStatementFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.extractedText = '',
    this.shareId = '',
  });

  final String shareId;
  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String extractedText;

  static SharedStatementFile? fromPlatform(dynamic value) {
    if (value is! Map) return null;
    try {
      return SharedStatementFile(
        shareId: '${value['shareId'] ?? ''}',
        name: '${value['name']}',
        mimeType: '${value['mimeType']}',
        bytes: base64Decode('${value['contentBase64']}'),
        extractedText: '${value['extractedText'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}

class SharedStatementService extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.ektiasystems/shared_statement');

  SharedStatementFile? _pending;
  SharedStatementFile? get pending => _pending;

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedFile') await _receive(call.arguments);
    });
    try {
      await _receive(await _channel.invokeMethod<dynamic>('getInitialShare'));
    } on MissingPluginException {
      // Execuções que não são Android não oferecem o canal nativo.
    }
  }

  Future<void> _receive(dynamic value) async {
    final file = SharedStatementFile.fromPlatform(value);
    if (file == null || file.bytes.isEmpty) return;
    if (_pending?.shareId == file.shareId && file.shareId.isNotEmpty) return;
    _pending = file;
    notifyListeners();
  }

  // Explicit user cancellation, unlike automatic receipt of a platform file.
  Future<void> clear() async {
    final file = _pending;
    if (file != null) await complete(file);
  }

  // A decoded share is not an uploaded receipt. Acknowledge only after the
  // server confirms success, and only the exact file that was sent.
  Future<void> complete(SharedStatementFile file) async {
    if (!identical(_pending, file)) return;
    if (file.shareId.isNotEmpty) {
      await _channel
          .invokeMethod<void>('acknowledgeShare', {'shareId': file.shareId});
    }
    if (identical(_pending, file)) {
      _pending = null;
      notifyListeners();
    }
  }
}

final sharedStatementService = SharedStatementService();
