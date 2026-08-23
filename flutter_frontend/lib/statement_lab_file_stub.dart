import 'dart:typed_data';

class StatementPickedFile {
  const StatementPickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<StatementPickedFile?> pickStatementFile() async => null;
void downloadStatementFile(Uint8List bytes, String name, String mimeType) {}
