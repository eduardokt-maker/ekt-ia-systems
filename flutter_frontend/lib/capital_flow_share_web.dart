import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> shareCapitalFlowImage(Uint8List bytes, String filename) async {
  final file = web.File(
    <web.BlobPart>[bytes.toJS].toJS,
    filename,
    web.FilePropertyBag(type: 'image/png'),
  );
  final data = web.ShareData(
    files: <web.File>[file].toJS,
    title: 'Fluxo de Capital Estrangeiro — B3',
    text: 'Consulta do fluxo de capital estrangeiro — EKT Desenvolvimento',
  );
  if (!web.window.navigator.canShare(data)) return false;
  await web.window.navigator.share(data).toDart;
  return true;
}
