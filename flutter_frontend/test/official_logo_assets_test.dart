import 'package:ekt_ia_flutter_frontend/official_logo_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AXIA3 usa a marca oficial armazenada localmente', () {
    expect(officialLogoAssets['AXIA3'], 'nosso_repositorio/logos/AXIA3.svg');
  });
}
