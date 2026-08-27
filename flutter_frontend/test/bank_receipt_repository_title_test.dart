import 'package:ekt_ia_flutter_frontend/bank_outflows_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usa o destinatário da despesa como título do comprovante', () {
    final title = receiptRepositoryTitle(
      <String, dynamic>{'id': 42, 'filename': 'receipt.jpg'},
      <Map<String, dynamic>>[
        <String, dynamic>{
          'source_file_id': 42,
          'destination': 'Mercado Primavera',
        },
      ],
    );

    expect(title, 'Mercado Primavera');
  });

  test('mantém o nome original quando não há destinatário reconhecido', () {
    final title = receiptRepositoryTitle(
      <String, dynamic>{'id': 7, 'filename': 'comprovante.png'},
      const <Map<String, dynamic>>[],
    );

    expect(title, 'comprovante.png');
  });

  test('indica quando um extrato reúne pagamentos para vários destinatários',
      () {
    final title = receiptRepositoryTitle(
      <String, dynamic>{'id': 9, 'filename': 'extrato.pdf'},
      <Map<String, dynamic>>[
        <String, dynamic>{'source_file_id': 9, 'destination': 'Loja A'},
        <String, dynamic>{'source_file_id': 9, 'destination': 'Loja B'},
      ],
    );

    expect(title, '2 destinatários');
  });
}
