# SkyMon

Radar de tráfego aéreo para Raspberry Pi com painel touch, FastAPI, WebSocket, SQLite e Leaflet. O ponto inicial é o Aeroporto de Viracopos (VCP), em Campinas.

## Rodar localmente

Requer Python 3.10 ou superior.

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
uvicorn app:app --host 0.0.0.0 --port 8000
```

Abra `http://localhost:8000`. Sem credenciais, o OpenSky permite consultas anônimas, porém com resolução de 10 s e cota menor. Para o uso contínuo, crie um cliente OAuth2 na conta OpenSky e preencha `OPENSKY_CLIENT_ID` e `OPENSKY_CLIENT_SECRET` no `.env` — as credenciais não devem ir para o Git.

## Inicialização no Raspberry Pi

1. Copie o projeto para o Pi e instale as dependências na virtualenv.
2. Crie um serviço `systemd` para executar `uvicorn app:app --host 127.0.0.1 --port 8000` na pasta do projeto.
3. Configure o Chromium para abrir `http://127.0.0.1:8000` com `--kiosk` no login gráfico.

O aplicativo salva uma amostra por minuto em `data/skymon.db`, preparando a Fase 2 (histórico e estatísticas) sem sobrecarregar o cartão SD. A coleta REST usa uma caixa geográfica de 200 km e o navegador recebe somente atualizações WebSocket; o mapa permanece aberto.

## Limites e fonte dos dados

Os dados ao vivo vêm da [API REST do OpenSky](https://openskynetwork.github.io/opensky-api/rest.html). Ela usa OAuth2 client credentials; para uma região desse tamanho cada consulta custa poucos créditos, conforme a área da caixa geográfica. O intervalo padrão foi ajustado para 10 segundos, compatível também com acesso anônimo.
