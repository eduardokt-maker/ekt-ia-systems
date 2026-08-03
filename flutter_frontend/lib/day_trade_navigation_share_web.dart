import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> shareNavigationReportPdf(
  Uint8List bytes,
  String filename,
) async {
  final file = web.File(
    <web.BlobPart>[bytes.toJS].toJS,
    filename,
    web.FilePropertyBag(type: 'application/pdf'),
  );
  final data = web.ShareData(
    files: <web.File>[file].toJS,
    title: 'Relatório de Operações Day Trade',
    text: 'Relatório de Navegação de Operações - EKT IA Systems',
  );
  if (!web.window.navigator.canShare(data)) return false;
  await web.window.navigator.share(data).toDart;
  return true;
}
