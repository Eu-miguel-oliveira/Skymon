#!/usr/bin/env bash
# Instalador completo do SkyMon para Raspberry Pi OS / Debian.
# Uso: bash install.sh
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"
ENV_FILE="$PROJECT_DIR/.env"
SERVICE_NAME="skymon"
APP_HOME=""

log() { printf '\n\033[1;36m[SkyMon]\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31m[SkyMon] Erro:\033[0m %s\n' "$1" >&2; exit 1; }

[[ -f "$PROJECT_DIR/app.py" && -f "$PROJECT_DIR/requirements.txt" ]] || fail "Execute este script na pasta raiz do repositório SkyMon."
command -v apt-get >/dev/null 2>&1 || fail "Este instalador requer Raspberry Pi OS ou Debian (apt-get não encontrado)."
command -v sudo >/dev/null 2>&1 || fail "O comando sudo é necessário."
[[ "$EUID" -ne 0 ]] || fail "Execute 'bash install.sh' como seu usuário normal, sem sudo."

# O serviço precisa usar o usuário que clonou o repositório, não o root.
APP_USER="${SUDO_USER:-$(id -un)}"
[[ "$APP_USER" != "root" ]] || fail "Execute 'bash install.sh' como seu usuário normal, sem sudo."
getent passwd "$APP_USER" >/dev/null || fail "Não foi possível localizar o usuário '$APP_USER'."
APP_GROUP="$(id -gn "$APP_USER")"
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
[[ -n "$APP_HOME" && -d "$APP_HOME" ]] || fail "Não foi possível localizar a pasta pessoal de '$APP_USER'."

# Corrige permissões deixadas por uma instalação anterior executada com sudo.
sudo chown -R "$APP_USER:$APP_GROUP" "$PROJECT_DIR"

log "Instalando dependências do sistema"
sudo apt-get update
if apt-cache show chromium-browser >/dev/null 2>&1; then
  BROWSER_PACKAGE="chromium-browser"
else
  BROWSER_PACKAGE="chromium"
fi

# Raspberry Pi OS Lite não possui ambiente gráfico. Nas imagens atuais os
# pacotes rpd-* compõem o desktop Wayland; em versões anteriores usamos a
# pilha X tradicional.
if apt-cache show rpd-wayland-core >/dev/null 2>&1; then
  DESKTOP_PACKAGES=(rpd-wayland-core rpd-theme rpd-preferences rpd-applications rpd-utilities rpd-graphics rpd-wayland-extras)
else
  DESKTOP_PACKAGES=(xserver-xorg lightdm raspberrypi-ui-mods)
fi
sudo apt-get install -y python3 python3-venv python3-pip ca-certificates curl "$BROWSER_PACKAGE" "${DESKTOP_PACKAGES[@]}"

log "Criando e atualizando o ambiente Python"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install -r "$PROJECT_DIR/requirements.txt"

log "Preparando configuração e armazenamento local"
mkdir -p "$PROJECT_DIR/data" "$PROJECT_DIR/logs"
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$PROJECT_DIR/.env.example" "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
chown "$APP_USER:$APP_GROUP" "$ENV_FILE"

log "Configurando o acesso ao OpenSky"
echo "Crie um API Client na sua conta OpenSky. O segredo digitado não será exibido."
read -r -p "OpenSky Client ID (Enter para usar acesso anônimo): " OPENSKY_CLIENT_ID
OPENSKY_CLIENT_SECRET=""
POLL_INTERVAL_SECONDS="300"
if [[ -n "$OPENSKY_CLIENT_ID" ]]; then
  while [[ -z "$OPENSKY_CLIENT_SECRET" ]]; do
    read -r -s -p "OpenSky Client Secret: " OPENSKY_CLIENT_SECRET
    echo
    [[ -n "$OPENSKY_CLIENT_SECRET" ]] || echo "O Client Secret não pode ficar vazio quando há um Client ID."
  done
  POLL_INTERVAL_SECONDS="10"
else
  log "Acesso anônimo selecionado (atualização a cada 5 minutos para respeitar a cota)."
fi

# Atualiza somente as chaves gerenciadas pelo instalador e preserva os demais
# ajustes locais, como o centro do mapa e o raio padrão.
SKYMON_ENV_FILE="$ENV_FILE" \
SKYMON_CLIENT_ID="$OPENSKY_CLIENT_ID" \
SKYMON_CLIENT_SECRET="$OPENSKY_CLIENT_SECRET" \
SKYMON_POLL_INTERVAL="$POLL_INTERVAL_SECONDS" \
"$VENV_DIR/bin/python" - <<'PY'
import os
import re
from pathlib import Path

path = Path(os.environ["SKYMON_ENV_FILE"])
text = path.read_text(encoding="utf-8")

for key, value in {
    "OPENSKY_CLIENT_ID": os.environ["SKYMON_CLIENT_ID"],
    "OPENSKY_CLIENT_SECRET": os.environ["SKYMON_CLIENT_SECRET"],
    "POLL_INTERVAL_SECONDS": os.environ["SKYMON_POLL_INTERVAL"],
}.items():
    pattern = rf"(?m)^{re.escape(key)}=.*$"
    replacement = f"{key}={value}"
    text = re.sub(pattern, lambda _match: replacement, text) if re.search(pattern, text) else text.rstrip() + "\n" + replacement + "\n"

path.write_text(text, encoding="utf-8")
PY

log "Criando o serviço systemd"
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=SkyMon flight radar
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${PROJECT_DIR}
Environment=PYTHONUNBUFFERED=1
ExecStart=${VENV_DIR}/bin/python -m uvicorn app:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

log "Configurando abertura automática na tela do Raspberry"
sudo tee /usr/local/bin/skymon-kiosk >/dev/null <<'EOF'
#!/usr/bin/env bash
set -eu

if command -v xset >/dev/null 2>&1; then
  xset s off -dpms s noblank || true
fi

for _ in $(seq 1 30); do
  curl --silent --fail http://127.0.0.1:8000/ >/dev/null 2>&1 && break
  sleep 1
done

if command -v chromium-browser >/dev/null 2>&1; then
  BROWSER="chromium-browser"
else
  BROWSER="chromium"
fi

exec "$BROWSER" --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble --password-store=basic --disable-gpu --disable-gpu-compositing http://127.0.0.1:8000
EOF
sudo chmod 755 /usr/local/bin/skymon-kiosk

AUTOSTART_DIR="$APP_HOME/.config/autostart"
sudo -u "$APP_USER" mkdir -p "$AUTOSTART_DIR"
sudo tee "$AUTOSTART_DIR/skymon-kiosk.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=SkyMon Kiosk
Comment=Abre o painel SkyMon automaticamente
Exec=/usr/local/bin/skymon-kiosk
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
sudo chown "$APP_USER:$APP_GROUP" "$AUTOSTART_DIR/skymon-kiosk.desktop"

if command -v raspi-config >/dev/null 2>&1; then
  # Em Raspberry Pi OS, seleciona desktop com login automático para que o
  # atalho de inicialização possa abrir o painel após cada boot.
  sudo raspi-config nonint do_boot_behaviour B4 || log "Não foi possível habilitar o login gráfico automático; o painel abrirá após o login gráfico."
fi
sudo systemctl set-default graphical.target

# Algumas telas touch SPI usam o framebuffer legado (/dev/fb0), sem DRM.
# Forçar o driver fbdev evita que o Xorg encerre antes de iniciar o desktop.
if [[ -e /dev/fb0 && ! -d /dev/dri ]]; then
  log "Configurando a tela framebuffer legada"
  FB_DEVICE="/dev/fb0"
  FB_DEPTH="24"
  # Displays SPI FBTFT antigos (ILI9486, ILI9341 etc.) normalmente são o
  # segundo framebuffer. O fb0 continua sendo a saída HDMI do firmware.
  if [[ -e /dev/fb1 ]] && grep -qE '^(fb_ili|fbtft)' /proc/modules; then
    FB_DEVICE="/dev/fb1"
    FB_DEPTH="16"
  fi
  sudo install -d -m 755 /etc/X11/xorg.conf.d
  sudo tee /etc/X11/xorg.conf.d/99-skymon-fbdev.conf >/dev/null <<EOF
Section "Monitor"
    Identifier "Monitor0"
EndSection

Section "Device"
    Identifier "Card0"
    Driver "fbdev"
    Option "fbdev" "${FB_DEVICE}"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Card0"
    Monitor "Monitor0"
    DefaultDepth ${FB_DEPTH}
    SubSection "Display"
        Depth ${FB_DEPTH}
        Modes "480x320"
    EndSubSection
EndSection
EOF
fi
sleep 2
sudo systemctl --no-pager --full status "$SERVICE_NAME"

IP_ADDRESS="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<EOF

Instalação concluída: o SkyMon está registrado para iniciar automaticamente.
Abra no navegador: http://${IP_ADDRESS:-IP-DO-RASPBERRY}:8000

No Raspberry, o Chromium abrirá o painel em modo tela cheia no próximo login/boot.

Comandos úteis:
  sudo systemctl status ${SERVICE_NAME}
  sudo journalctl -u ${SERVICE_NAME} -f
EOF
