import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class BankingPickedFile {
  const BankingPickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<BankingPickedFile?> pickBankingFile() async {
  final completer = Completer<BankingPickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.pdf,.csv,.txt,.ofx,.xlsx'
    ..style.display = 'none';
  var finished = false;

  void finish(BankingPickedFile? value) {
    if (finished) return;
    finished = true;
    input.remove();
    completer.complete(value);
  }

  void changed(web.Event _) async {
    final file = input.files?.item(0);
    if (file == null) {
      finish(null);
      return;
    }
    try {
      final buffer = await file.arrayBuffer().toDart;
      finish(BankingPickedFile(file.name, buffer.toDart.asUint8List()));
    } catch (_) {
      finish(null);
    }
  }

  void cancelled(web.Event _) => finish(null);

  input.addEventListener('change', changed.toJS);
  input.addEventListener('cancel', cancelled.toJS);
  web.document.body?.appendChild(input);
  input.click();
  return completer.future;
}
