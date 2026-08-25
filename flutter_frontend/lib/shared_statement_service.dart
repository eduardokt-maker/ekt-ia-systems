import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedStatementFile {
  const SharedStatementFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.extractedText = '',
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String extractedText;

  static SharedStatementFile? fromPlatform(dynamic value) {
    if (value is! Map) return null;
    try {
      return SharedStatementFile(
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
      if (call.method == 'sharedFile') _receive(call.arguments);
    });
    try {
      _receive(await _channel.invokeMethod<dynamic>('getInitialShare'));
    } on MissingPluginException {
      // Execuções que não são Android não oferecem o canal nativo.
    }
  }

  void _receive(dynamic value) {
    final file = SharedStatementFile.fromPlatform(value);
    if (file == null || file.bytes.isEmpty) return;
    _pending = file;
    notifyListeners();
  }

  void clear() {
    _pending = null;
    notifyListeners();
  }
}

final sharedStatementService = SharedStatementService();
