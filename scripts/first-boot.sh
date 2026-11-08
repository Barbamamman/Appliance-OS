#!/usr/bin/env bash
# ============================================================
# first-boot.sh – körs EN gång efter installation (via systemd).
# Idempotent: kan köras om manuellt med: sudo rm /var/lib/applianceos/first-boot.done
# ============================================================
set -uo pipefail   # inte -e: vi vill fortsätta om t.ex. CasaOS misslyckas

BASE="/opt/applianceos"
STATE="/var/lib/applianceos"
DONE="${STATE}/first-boot.done"
LOG="/var/log/applianceos-first-boot.log"
NET_NAME="appliance-net"
TZ_DEFAULT="Europe/Stockholm"

mkdir -p "${STATE}" "${BASE}/stacks"
exec > >(tee -a "${LOG}") 2>&1

log()  { echo "[$(date '+%F %T')] $*"; }
warn() { echo "[$(date '+%F %T')] VARNING: $*"; FAILED+=("$*"); }
FAILED=()

[[ $EUID -eq 0 ]] || { echo "Kör som root."; exit 1; }
[[ -f "${DONE}" ]] && { log "Redan konfigurerad."; exit 0; }

log "=== HomeAppliance OS: första start ==="

# ---------- 1. Vänta på nätverk ----------
log "Väntar på internet..."
for i in $(seq 1 60); do
  if curl -fsS --max-time 5 https://deb.debian.org >/dev/null 2>&1; then
    log "Nätverk OK."
    ONLINE=1; break
  fi
  sleep 5
done
if [[ -z "${ONLINE:-}" ]]; then
  warn "Inget internet – hoppar över nedladdningar. Kör skriptet igen när nätverket fungerar."
  exit 1   # skapar inte .done, så systemd försöker igen vid nästa start
fi

# ---------- 2. Grundinställningar ----------
timedatectl set-timezone "${TZ_DEFAULT}" 2>/dev/null || warn "Kunde inte sätta tidszon"
timedatectl set-ntp true 2>/dev/null || true

# Stäng inte av servern när laptopens lock stängs
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-appliance.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl restart systemd-logind 2>/dev/null || true

# Sensorer (för monitorn)
yes | sensors-detect --auto >/dev/null 2>&1 || true

# ---------- 3. Docker ----------
systemctl enable --now docker || warn "Docker startade inte"
for i in $(seq 1 20); do docker info >/dev/null 2>&1 && break; sleep 2; done

# Lägg alla vanliga användare (uid >= 1000) i docker-gruppen
while IFS=: read -r user _ uid _; do
  if [[ "${uid}" -ge 1000 && "${user}" != "nobody" ]]; then
    usermod -aG docker "${user}" && log "Lade ${user} i docker-gruppen"
  fi
done < /etc/passwd

# Gemensamt Docker-nätverk
if ! docker network inspect "${NET_NAME}" >/dev/null 2>&1; then
  docker network create "${NET_NAME}" && log "Skapade Docker-nätverket ${NET_NAME}"
fi

# ---------- 4. CasaOS ----------
if ! command -v casaos >/dev/null 2>&1 && [[ ! -d /var/lib/casaos ]]; then
  log "Installerar CasaOS (kan ta flera minuter)..."
  if curl -fsSL https://get.casaos.io | bash; then
    log "CasaOS installerat."
  else
    warn "CasaOS-installationen misslyckades (kan sakna stöd för denna Debian-version). Systemet fungerar ändå."
  fi
else
  log "CasaOS finns redan."
fi

# ---------- 5. n8n ----------
N8N_DIR="${BASE}/stacks/n8n"
mkdir -p "${N8N_DIR}"
if [[ ! -f "${N8N_DIR}/compose.yml" ]]; then
  ENC_KEY="$(openssl rand -hex 24)"
  cat > "${N8N_DIR}/.env" <<EOF
N8N_ENCRYPTION_KEY=${ENC_KEY}
GENERIC_TIMEZONE=${TZ_DEFAULT}
EOF
  chmod 600 "${N8N_DIR}/.env"
  cat > "${N8N_DIR}/compose.yml" <<'EOF'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${GENERIC_TIMEZONE}
      - N8N_SECURE_COOKIE=false   # tillåter http i lokalnätet; sätts till true bakom HTTPS/Tailscale
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - appliance-net
volumes:
  n8n_data:
networks:
  appliance-net:
    external: true
EOF
fi
log "Startar n8n..."
( cd "${N8N_DIR}" && docker compose up -d ) || warn "n8n kunde inte startas"

# ---------- 6. Tailscale (kräver inloggning, görs i wizarden) ----------
systemctl enable --now tailscaled 2>/dev/null || warn "tailscaled startade inte"

# ---------- 7. Välkomstmeddelande ----------
IP="$(hostname -I | awk '{print $1}')"
HOST="$(hostname)"
cat > /etc/motd <<EOF

  HomeAppliance OS
  ------------------------------------------
  CasaOS:   http://${IP}  (eller http://${HOST}.local)
  n8n:      http://${IP}:5678
  Loggfil:  ${LOG}

  Anslut via Tailscale:  sudo tailscale up

EOF

# ---------- 8. Klart ----------
if [[ ${#FAILED[@]} -eq 0 ]]; then
  log "Allt klart."
else
  log "Klart med ${#FAILED[@]} varning(ar):"
  printf ' - %s\n' "${FAILED[@]}"
fi
touch "${DONE}"
