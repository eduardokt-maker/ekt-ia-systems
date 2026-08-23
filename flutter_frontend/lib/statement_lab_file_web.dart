import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class StatementPickedFile {
  const StatementPickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<StatementPickedFile?> pickStatementFile() async {
  final completer = Completer<StatementPickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.pdf,.csv,.ofx,.xlsx'
    ..style.display = 'none';
  var finished = false;
  void finish(StatementPickedFile? value) {
    if (finished) return;
    finished = true;
    input.remove();
    completer.complete(value);
  }

  void changed(web.Event _) async {
    final file = input.files?.item(0);
    if (file == null) return finish(null);
    try {
      final buffer = await file.arrayBuffer().toDart;
      finish(StatementPickedFile(file.name, buffer.toDart.asUint8List()));
    } catch (_) {
      finish(null);
    }
  }

  input.addEventListener('change', changed.toJS);
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  web.document.body?.appendChild(input);
  input.click();
  return completer.future;
}

void downloadStatementFile(Uint8List bytes, String name, String mimeType) {
  final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
