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

## Instalação no Raspberry Pi

Com o repositório já copiado ou clonado no Raspberry Pi OS, execute na raiz do projeto:

```bash
bash install.sh
```

O instalador solicita o `Client ID` e o `Client Secret` OAuth2 do OpenSky (o segredo não aparece no terminal). Ele instala os pacotes do sistema, cria `.venv`, prepara `.env`, cria e inicia o serviço `skymon.service`, configura login gráfico automático no Raspberry Pi OS e adiciona a abertura do Chromium em modo quiosque. Assim, após cada boot, o painel abre na tela touch e também fica disponível em `http://IP-DO-RASPBERRY:8000`.

Pressione Enter no `Client ID` somente se quiser usar acesso anônimo: nesse modo o painel atualiza a cada cinco minutos para respeitar a cota do OpenSky.

O aplicativo salva uma amostra por minuto em `data/skymon.db`, preparando a Fase 2 (histórico e estatísticas) sem sobrecarregar o cartão SD. A coleta REST usa uma caixa geográfica de 200 km e o navegador recebe somente atualizações WebSocket; o mapa permanece aberto.

## Limites e fonte dos dados

Os dados ao vivo vêm da [API REST do OpenSky](https://openskynetwork.github.io/opensky-api/rest.html). Ela usa OAuth2 client credentials; para uma região desse tamanho cada consulta custa poucos créditos, conforme a área da caixa geográfica. Sem credenciais, o instalador usa 5 minutos para respeitar a cota diária. Com OAuth2, altere `POLL_INTERVAL_SECONDS` para `10` no `.env`.
