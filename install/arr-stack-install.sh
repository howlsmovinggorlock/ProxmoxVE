#!/usr/bin/env bash
# Runs inside the Arr Stack LXC; do not run directly on the Proxmox host.
set -eEuo pipefail
export DEBIAN_FRONTEND=noninteractive
export TZ="${TZ:-Asia/Hong_Kong}"

case "$(dpkg --print-architecture)" in
  amd64) ASSET_ARCH="x64" ;;
  arm64) ASSET_ARCH="arm64" ;;
  *) echo "Unsupported architecture" >&2; exit 1 ;;
esac

log() { printf '\n==> %s\n' "$*"; }

install_dependencies() {
  log "Installing dependencies"
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl jq git gnupg \
    sqlite3 mediainfo tzdata libicu-dev libcurl4 libssl3 libgssapi-krb5-2 libgdiplus
}

create_media_user() {
  getent group media >/dev/null || groupadd --gid 1000 media
  id media >/dev/null 2>&1 || useradd --system --uid 1000 --gid media --create-home \
    --home-dir /var/lib/media --shell /usr/sbin/nologin media
  install -d -o media -g media -m 0775 /data /data/torrents /data/usenet \
    /data/media /data/media/tv /data/media/movies /data/media/music
}

latest_asset() {
  local repo="$1" prefix="$2" suffix="-${ASSET_ARCH}.tar.gz"
  curl -fsSL -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -r --arg prefix "$prefix" --arg suffix "$suffix" '
        .assets[]
        | select(.name | startswith($prefix))
        | select(.name | contains(".linux-"))
        | select(.name | endswith($suffix))
        | .browser_download_url
      ' | head -n1
}

install_arr() {
  local app="$1" repo="$2" service="$3" url tmp
  url="$(latest_asset "$repo" "$app")"
  [[ -n "$url" && "$url" != "null" ]] || {
    echo "No compatible Linux ${ASSET_ARCH} release asset found for ${app}" >&2
    exit 1
  }

  log "Installing ${app}"
  systemctl stop "$service" 2>/dev/null || true
  tmp="$(mktemp -d)"
  curl -fL --retry 3 "$url" -o "$tmp/${app}.tar.gz"
  rm -rf "/opt/${app}"
  install -d -o media -g media -m 0775 "/opt/${app}" "/var/lib/${service}"
  tar -xzf "$tmp/${app}.tar.gz" -C "/opt/${app}" --strip-components=1
  rm -rf "$tmp"
  chown -R media:media "/opt/${app}" "/var/lib/${service}"
  chmod 0755 "/opt/${app}/${app}"

  cat > "/etc/systemd/system/${service}.service" <<EOF
[Unit]
Description=${app}
After=network-online.target
Wants=network-online.target

[Service]
User=media
Group=media
Type=simple
ExecStart=/opt/${app}/${app} -nobrowser -data=/var/lib/${service}/
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$service"
}

install_seerr() {
  log "Installing Node.js 22 and Seerr"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
  corepack enable
  rm -rf /opt/seerr
  git clone --depth=1 https://github.com/seerr-team/seerr.git /opt/seerr
  install -d -o media -g media -m 0775 /var/lib/seerr
  cd /opt/seerr
  corepack pnpm install --frozen-lockfile
  corepack pnpm build
  chown -R media:media /opt/seerr /var/lib/seerr

  cat >/etc/systemd/system/seerr.service <<'EOF'
[Unit]
Description=Seerr
After=network-online.target
Wants=network-online.target

[Service]
User=media
Group=media
WorkingDirectory=/opt/seerr
Environment=NODE_ENV=production
Environment=PORT=5055
Environment=CONFIG_DIRECTORY=/var/lib/seerr
ExecStart=/usr/bin/corepack pnpm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now seerr
}

enable_console_autologin() {
  log "Enabling root autologin on the Proxmox tty1 console"
  install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
  cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
Type=idle
EOF
  systemctl daemon-reload
  systemctl enable getty@tty1.service
}

main() {
  install_dependencies
  create_media_user
  install_arr Prowlarr Prowlarr/Prowlarr prowlarr
  install_arr Sonarr Sonarr/Sonarr sonarr
  install_arr Radarr Radarr/Radarr radarr
  install_arr Lidarr Lidarr/Lidarr lidarr
  install_seerr
  enable_console_autologin
  log "Verifying services"
  systemctl is-active --quiet prowlarr sonarr radarr lidarr seerr
}

main "$@"
