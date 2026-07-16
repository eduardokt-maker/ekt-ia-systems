import 'package:ekt_ia_flutter_frontend/official_logo_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AXIA3 usa a marca oficial armazenada localmente', () {
    expect(officialLogoAssets['AXIA3'], 'nosso_repositorio/logos/AXIA3.svg');
  });

  test('todos os ativos atuais do Ibovespa possuem logo local', () {
    expect(officialLogoAssets, hasLength(78));
    for (final ticker in <String>[
      'ABEV3',
      'AURE3',
      'BBAS3',
      'BPAC11',
      'CYRE3',
      'EMBJ3',
      'ENGI11',
      'GGBR4',
      'GOAU4',
      'HYPE3',
      'IGTI11',
      'ITUB4',
      'KLBN11',
      'MGLU3',
      'NATU3',
      'POMO4',
      'RECV3',
      'RENT3',
      'SANB11',
      'SBSP3',
      'TAEE11',
      'UGPA3',
      'VALE3',
      'VIVT3',
      'WEGE3',
    ]) {
      expect(officialLogoAssets, contains(ticker));
    }
  });

  test('logos bancárias incompatíveis foram convertidas para SVG local', () {
    expect(officialLogoAssets['BBDC3'], 'nosso_repositorio/logos/BBDC3.svg');
    expect(officialLogoAssets['BBDC4'], 'nosso_repositorio/logos/BBDC4.svg');
    expect(officialLogoAssets['BRAP4'], 'nosso_repositorio/logos/BRAP4.svg');
  });

  test('catálogo não contém formatos ICO incompatíveis com Flutter Web', () {
    expect(officialLogoAssets.values.where((path) => path.endsWith('.ico')),
        isEmpty);
    expect(officialLogoAssets['PETR3'], 'nosso_repositorio/logos/PETR3.svg');
    expect(officialLogoAssets['PETR4'], 'nosso_repositorio/logos/PETR4.svg');
    expect(officialLogoAssets['PSSA3'], 'nosso_repositorio/logos/PSSA3.svg');
  });
}
