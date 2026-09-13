import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/api_client.dart';
import 'package:ekt_ia_flutter_frontend/native_session_store.dart';
import 'package:ekt_ia_flutter_frontend/shared_statement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const shareChannel = MethodChannel('com.ektiasystems/shared_statement');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(shareChannel, null);
    messenger.setMockMethodCallHandler(NativeSessionStore.channel, null);
  });

  test('receber e reiniciar não apaga comprovante; só confirmação remove',
      () async {
    var acknowledgements = 0;
    final payload = {
      'shareId': 'receipt_test',
      'name': 'teste.pdf',
      'mimeType': 'application/pdf',
      'contentBase64': base64Encode([1, 2, 3])
    };
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'getInitialShare') return payload;
      if (call.method == 'acknowledgeShare') {
        expect(call.arguments['shareId'], 'receipt_test');
        acknowledgements++;
      }
      return null;
    });
    final service = SharedStatementService();
    await service.initialize();
    expect(service.pending?.name, 'teste.pdf');
    expect(acknowledgements, 0);
    final restarted = SharedStatementService();
    await restarted.initialize();
    expect(restarted.pending?.shareId, 'receipt_test');
    await restarted.complete(restarted.pending!);
    expect(acknowledgements, 1);
    expect(restarted.pending, isNull);
    service.dispose();
    restarted.dispose();
  });

  test('falha ao confirmar mantém comprovante para nova tentativa', () async {
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'getInitialShare') {
        return {
          'shareId': 'receipt_test',
          'name': 'teste.pdf',
          'mimeType': 'application/pdf',
          'contentBase64': base64Encode([1])
        };
      }
      throw PlatformException(code: 'storage');
    });
    final service = SharedStatementService();
    await service.initialize();
    await expectLater(
        service.complete(service.pending!), throwsA(isA<PlatformException>()));
    expect(service.pending, isNotNull);
    service.dispose();
  });

  test('sessão é recuperada apenas para a origem correta, sem guardar senha',
      () async {
    String? saved;
    messenger.setMockMethodCallHandler(NativeSessionStore.channel,
        (call) async {
      switch (call.method) {
        case 'write':
          saved = call.arguments as String;
        case 'read':
          return saved;
        case 'clear':
          saved = null;
      }
      return null;
    });
    final token = '${base64Url.encode(utf8.encode(jsonEncode({
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))}.signature';
    final api = ApiClient();
    api.startSession(
        accessToken: token,
        refreshToken: 'refresh',
        uriBuilder: (p) => Uri.parse('https://example.test$p'),
        user: {'login': 'test'});
    await Future<void>.delayed(Duration.zero);
    expect(saved, isNotNull);
    expect(saved, isNot(contains('password')));
    final restored = ApiClient();
    await restored.restoreSession((p) => Uri.parse('https://example.test$p'));
    expect(restored.isAuthenticated, isTrue);
    final different = ApiClient();
    await different.restoreSession((p) => Uri.parse('https://other.test$p'));
    expect(different.isAuthenticated, isFalse);
    api.clearSession();
    restored.clearSession();
    await Future<void>.delayed(Duration.zero);
    expect(saved, isNull);
  });
}
