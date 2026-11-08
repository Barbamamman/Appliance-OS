#!/usr/bin/env bash
# ============================================================
# build-iso.sh – bygger HomeAppliance OS (Debian 13 "trixie")
# Använder Debians officiella live-build (reproducerbart, CI-vänligt).
#
# Körs på en Debian-värd som root:
#   sudo apt install live-build
#   sudo ./scripts/build-iso.sh
# ============================================================
set -euo pipefail

# ---------- Inställningar ----------
DISTRO_NAME="HomeAppliance OS"
DISTRO_SLUG="homeappliance"
SUITE="trixie"            # Debian 13
ARCH="amd64"
VERSION="${VERSION:-0.1.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${REPO_DIR}/work"

# ---------- Förkontroller ----------
[[ $EUID -eq 0 ]] || { echo "Kör som root (sudo)."; exit 1; }
command -v lb >/dev/null || { echo "Installera live-build: apt install live-build"; exit 1; }

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Rensa tidigare bygge men behåll cache
lb clean --purge 2>/dev/null || true

# ---------- Grundkonfiguration ----------
lb config \
  --distribution "${SUITE}" \
  --architectures "${ARCH}" \
  --archive-areas "main contrib non-free-firmware" \
  --binary-images iso-hybrid \
  --bootloaders "grub-efi,syslinux" \
  --debian-installer none \
  --firmware-chroot true \
  --apt-recommends false \
  --apt-indices false \
  --iso-application "${DISTRO_NAME}" \
  --iso-publisher "${DISTRO_NAME} project" \
  --iso-volume "${DISTRO_SLUG}-${VERSION}" \
  --image-name "${DISTRO_SLUG}-${VERSION}" \
  --bootappend-live "boot=live components quiet splash hostname=${DISTRO_SLUG} username=live"

# ---------- Paketlistor ----------
mkdir -p config/package-lists

cat > config/package-lists/base.list.chroot <<'EOF'
# --- System ---
sudo curl wget ca-certificates gnupg git jq unzip
openssh-server avahi-daemon network-manager
htop smartmontools lm-sensors ufw
# --- Firmware/drivrutiner för äldre hårdvara ---
firmware-linux firmware-misc-nonfree
firmware-iwlwifi firmware-realtek firmware-atheros
firmware-brcm80211 firmware-intel-sound
# --- Python för GUI/monitor ---
python3 python3-venv python3-pip python3-tk python3-psutil
# --- Live + installerare ---
live-boot live-config live-config-systemd
calamares calamares-settings-debian
# --- Minimalt skrivbord för wizard (kan bytas ut mot webb-wizard) ---
xorg lightdm xfce4 xfce4-terminal
EOF

# ---------- Overlay: filer som kopieras in i systemet ----------
mkdir -p config/includes.chroot
if [[ -d "${REPO_DIR}/overlay" ]]; then
  cp -a "${REPO_DIR}/overlay/." config/includes.chroot/
fi
if [[ -f "${SCRIPT_DIR}/first-boot.sh" ]]; then
  install -D -m 0755 "${SCRIPT_DIR}/first-boot.sh" \
    config/includes.chroot/opt/applianceos/first-boot.sh
fi
if [[ -d "${REPO_DIR}/gui" ]]; then
  mkdir -p config/includes.chroot/opt/applianceos/gui
  cp -a "${REPO_DIR}/gui/." config/includes.chroot/opt/applianceos/gui/
fi

# ---------- Chroot-hooks (körs under bygget, i ordning) ----------
mkdir -p config/hooks/live

# 1) Docker (officiellt repo) + Tailscale
cat > config/hooks/live/0100-repos-and-docker.hook.chroot <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

install -m 0755 -d /etc/apt/keyrings

# Docker
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" \
  > /etc/apt/sources.list.d/docker.list

# Tailscale
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
  -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
  -o /etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  tailscale

# Aktivera tjänster (startas först vid körande system, inte i chroot)
systemctl enable docker containerd tailscaled ssh avahi-daemon NetworkManager || true
EOF

# 2) Python-bibliotek för GUI (isolerad venv)
cat > config/hooks/live/0200-python-gui.hook.chroot <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail
python3 -m venv --system-site-packages /opt/applianceos/venv
/opt/applianceos/venv/bin/pip install --no-cache-dir customtkinter psutil pyyaml
EOF

# 3) Aktivera first-boot-tjänsten om den finns i overlay
cat > config/hooks/live/0300-enable-first-boot.hook.chroot <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail
if [ -f /etc/systemd/system/applianceos-first-boot.service ]; then
  systemctl enable applianceos-first-boot.service
fi
EOF

# 4) Städning för mindre ISO
cat > config/hooks/live/9000-cleanup.hook.chroot <<'EOF'
#!/usr/bin/env bash
set -eux
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

chmod +x config/hooks/live/*.hook.chroot

# ---------- Bygg ----------
echo ">>> Bygger ${DISTRO_NAME} ${VERSION} (kan ta 20–60 min)..."
lb build 2>&1 | tee "${WORK_DIR}/build.log"

# ---------- Checksummor ----------
ISO="$(ls -1 "${WORK_DIR}"/*.iso | head -n1)"
( cd "${WORK_DIR}" && sha256sum "$(basename "${ISO}")" > "$(basename "${ISO}").sha256" )

echo ">>> Klart: ${ISO}"
echo ">>> Testa i QEMU: qemu-system-x86_64 -m 4096 -enable-kvm -cdrom '${ISO}'"
