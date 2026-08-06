# Motor de Análise — ES e EWZ

Módulo informativo de análise técnica, sem execução de ordens. Cada ativo é calculado isoladamente e somente depois os scores individuais são combinados em uma leitura contextual.

## Arquitetura

1. `data_provider.py`: obtém e valida candles. O adaptador atual usa dados indicativos e possivelmente atrasados do Yahoo Finance; ele pode ser substituído por um provedor licenciado sem alterar cálculos ou interface.
2. `ta_engine.py`: único ponto que chama o TA-Lib. Calcula EMA 9/21/80/200, ADX, RSI, MACD, SAR, Estocástico, ROC, Momentum, Williams %R, ATR, Bollinger, OBV, MFI e padrões de candle. A VWAP é calculada de forma isolada porque não faz parte do TA-Lib.
3. `signal_service.py`: interpreta indicadores e calcula o score técnico.
4. `service.py`: cache de 30 segundos, atualização, erros e leitura conjunta.
5. `analysis_engine_screen.dart`: somente apresenta os resultados prontos.

## Score

- Alinhamento de preço e EMA 9/21/80: ±30.
- Histograma do MACD: ±15.
- RSI em faixa direcional: ±10.
- Posição sobre a VWAP: ±15.
- Volume acima de 120% da média: até ±10, confirmando a direção existente.
- ADX a partir de 25: até ±10, confirmando a direção existente.

O resultado é limitado entre -100 e +100. Ele organiza a leitura técnica; não é probabilidade de ganho.

## Instalação

Use Python de 64 bits e execute `python -m pip install -r requirements.txt`. As versões atuais do pacote `TA-Lib` oferecem wheels binários que já incluem a biblioteca nativa para Windows e Python 3.12 ou mais recente.

## Fonte de dados

A primeira versão usa o mesmo padrão de fonte externa atrasada já adotado pelo Monitor Global. Antes de compartilhar o módulo com outros usuários ou comercializá-lo, substitua o adaptador por uma fonte licenciada para redistribuição e, se necessário, dados CME em tempo real.
