import 'dart:typed_data';

class BankingPickedFile {
  const BankingPickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<BankingPickedFile?> pickBankingFile() async => null;
