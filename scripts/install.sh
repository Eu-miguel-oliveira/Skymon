#!/usr/bin/env bash
# Instala o SkyMon em Raspberry Pi OS/Debian.
# Uso: bash scripts/install.sh
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
ENV_FILE="$ROOT_DIR/.env"

log() { printf '\n\033[1;36m[SkyMon]\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31m[SkyMon] Erro:\033[0m %s\n' "$1" >&2; exit 1; }

if ! command -v apt-get >/dev/null 2>&1; then
  fail "Este instalador foi feito para Raspberry Pi OS/Debian (apt-get não encontrado)."
fi

if ! command -v sudo >/dev/null 2>&1; then
  fail "O comando sudo é necessário para instalar os pacotes do sistema."
fi

log "Instalando dependências do sistema"
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip ca-certificates

log "Criando/atualizando a virtualenv"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install -r "$ROOT_DIR/requirements.txt"

log "Preparando diretórios locais"
mkdir -p "$ROOT_DIR/data" "$ROOT_DIR/logs"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  log "Arquivo .env criado. Preencha OPENSKY_CLIENT_ID e OPENSKY_CLIENT_SECRET antes do uso contínuo."
else
  log "O arquivo .env já existe; ele foi preservado."
fi

cat <<EOF

Instalação concluída.

Para testar:
  cd "$ROOT_DIR"
  .venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000

Abra no Raspberry: http://127.0.0.1:8000
EOF
