# EKT IA Systems — Flutter

Frontend multiplataforma para Web, Windows, Android e iOS. Todas as plataformas
consomem a API Python publicada no Render e compartilham o mesmo PostgreSQL na
nuvem. Os aplicativos nunca acessam o banco diretamente.

## Arquitetura oficial

```text
Web / Windows / Android / iOS
              |
            HTTPS
              |
 https://ekt-ia-systems.onrender.com
              |
        PostgreSQL na nuvem
```

Em aplicativos nativos, a URL de producao acima e usada automaticamente. Para
apontar uma compilacao a outro backend, use `--dart-define=API_BASE_URL=...`.

## Como rodar

Instale o Flutter SDK e execute:

```powershell
cd flutter_frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://ekt-ia-systems.onrender.com
```

Para rodar contra um backend local, informe a URL local:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

O backend local pode ser iniciado na raiz do repositorio com:

```powershell
uvicorn web_app:app --host 127.0.0.1 --port 8000
```

## Gerar versoes instalaveis

Windows:

```powershell
flutter build windows --release
```

O executavel e suas bibliotecas serao gerados em
`build/windows/x64/runner/Release/`. A pasta inteira deve ser distribuida ou
empacotada em um instalador; apenas o arquivo `.exe` nao e suficiente.

Android para homologacao:

```powershell
flutter build apk --release
```

Android para Google Play:

```powershell
flutter build appbundle --release
```

O APK sera gerado em `build/app/outputs/flutter-apk/`. Antes da distribuicao
publica, configure uma chave Android definitiva fora do Git. Todas as futuras
atualizacoes precisam usar a mesma chave e um numero de versao superior.

iOS:

```bash
flutter build ipa --release
```

A estrutura iOS esta versionada, mas essa compilacao precisa ser executada em
um Mac com Xcode e uma conta Apple Developer configurada.

## Versionamento e atualizacoes

A versao fica no `pubspec.yaml`, no formato `versao+compilacao`:

```yaml
version: 0.1.0+1
```

Em cada publicacao, aumente a versao e o numero de compilacao. Preserve estes
identificadores para que Windows, Android e iOS reconhecam novas entregas como
atualizacoes do mesmo produto:

- Android: `com.ektiasystems.ekt_ia_flutter_frontend`.
- iOS: `com.ektiasystems.ektIaFlutterFrontend`.
- Windows: `ekt_ia_systems.exe`.

Segredos, credenciais do banco e chaves de assinatura nao devem ser enviados ao
GitHub. Alteracoes somente no backend continuam sendo publicadas pelo Render e
nao exigem recompilar os aplicativos. Alteracoes no Flutter exigem novos pacotes.

## Assinatura Android oficial

Execute uma unica vez no PowerShell:

```powershell
.\tool\create_android_keystore.ps1
```

O comando pede uma senha forte, cria
`android/keystore/ekt-ia-systems-upload.jks` e prepara automaticamente
`android/key.properties`. Os dois arquivos estao ignorados pelo Git.

Guarde a chave e as senhas em pelo menos dois locais seguros. Perder essa chave
impede atualizar o aplicativo Android instalado ou publicado na Play Store.

Para a automacao do GitHub, configure estes Actions secrets:

- `ANDROID_KEYSTORE_BASE64`: conteudo Base64 do arquivo `.jks`.
- `ANDROID_STORE_PASSWORD`: senha do arquivo.
- `ANDROID_KEY_PASSWORD`: senha da chave.
- `ANDROID_KEY_ALIAS`: `ekt-ia-systems`.

## Instalador Windows

Depois de `flutter build windows --release`, compile o instalador com Inno Setup:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\ekt-ia-systems.iss
```

O instalador usa um `AppId` permanente. Versoes futuras substituem a instalacao
anterior quando o numero em `pubspec.yaml` for aumentado.

## Releases automaticos

O workflow `.github/workflows/release-apps.yml` gera:

- APK Android para instalacao direta.
- AAB Android para Google Play.
- Instalador Windows.

Ele pode ser iniciado manualmente em `Actions > Release dos aplicativos`.
Quando uma tag como `v0.1.0` for enviada, os tres arquivos tambem serao anexados
a uma GitHub Release.

## Requisitos de compilacao no Windows

- Flutter SDK.
- Android Studio e Android SDK para APK/AAB.
- Visual Studio com a carga `Desktop development with C++` para Windows.
- Java JDK compativel com o Flutter/Android.

## Escopo atual

- Login de investimentos via backend Python.
- Painel logado com os tres modulos: Meus investimentos, Meu orcamento e Operacoes day trade.
- Meus investimentos com cadastro manual, opcoes Santander, carteira, exclusao e valores aplicados.
- Meu orcamento com totais mensais, filtros e cadastro, edicao, status e exclusao de lancamentos.
- Operacoes day trade reproduz o estado atual do modulo Python, que ainda esta em preparacao.
- Persistencia de Meu orcamento pela API Python em `/api/budget`.
- Persistencia da carteira e dos valores aplicados pela API Python em `/api/investments`.
