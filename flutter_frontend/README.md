# EKT IA Flutter Frontend

Frontend Flutter para toda a experiencia apos o login, mantendo o backend e o banco em Python.

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

## Escopo atual

- Login de investimentos via backend Python.
- Painel logado com os tres modulos: Meus investimentos, Meu orcamento e Operacoes day trade.
- Meus investimentos com cadastro manual, opcoes Santander, carteira, exclusao e valores aplicados.
- Meu orcamento com totais mensais, filtros e cadastro, edicao, status e exclusao de lancamentos.
- Operacoes day trade reproduz o estado atual do modulo Python, que ainda esta em preparacao.
- Persistencia de Meu orcamento pela API Python em `/api/budget`.
- Persistencia da carteira e dos valores aplicados pela API Python em `/api/investments`.
