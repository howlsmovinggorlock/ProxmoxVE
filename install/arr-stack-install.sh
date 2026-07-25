#!/usr/bin/env bash
# Installs Prowlarr, Sonarr, Radarr, Lidarr, and Seerr in one LXC.
# Intended to be called by ct/arr-stack.sh through community-scripts build.func.
set -eEuo pipefail
export DEBIAN_FRONTEND=noninteractive

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) ASSET_ARCH="x64" ;;
  arm64) ASSET_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

log() { printf '\n==> %s\n' "$*"; }

install_dependencies() {
  log "Installing dependencies"
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl jq sqlite3 mediainfo tzdata git gnupg \
    libicu-dev libcurl4 libssl3 libgssapi-krb5-2 libgdiplus
}

create_media_user() {
  if ! getent group media >/dev/null; then groupadd --gid 1000 media; fi
  if ! id media >/dev/null 2>&1; then
    useradd --system --uid 1000 --gid media --home-dir /var/lib/media \
      --create-home --shell /usr/sbin/nologin media
  fi
  install -d -o media -g media -m 0775 \
    /data /data/torrents /data/usenet /data/media \
    /data/media/tv /data/media/movies /data/media/music
}

latest_arr_asset() {
  local repo="$1" pattern="$2"
  curl -fsSL -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -r --arg pattern "$pattern" \
      '.assets[] | select(.name | test($pattern)) | .browser_download_url' \
    | head -n1
}

install_arr() {
  local app="$1" repo="$2" service="$3"
  local url archive tmp
  url="$(latest_arr_asset "$repo" "linux-core-${ASSET_ARCH}\\.tar\\.gz$")"
  if [[ -z "$url" || "$url" == "null" ]]; then
    echo "No ${app} linux-core-${ASSET_ARCH} release asset found." >&2
    exit 1
  fi

  log "Installing ${app}"
  systemctl stop "$service" 2>/dev/null || true
  tmp="$(mktemp -d)"
  archive="${tmp}/${app}.tar.gz"
  curl -fL --retry 3 "$url" -o "$archive"
  rm -rf "/opt/${app}"
  install -d -o media -g media -m 0775 "/opt/${app}" "/var/lib/${service}"
  tar -xzf "$archive" -C "/opt/${app}" --strip-components=1
  rm -rf "$tmp"
  chown -R media:media "/opt/${app}" "/var/lib/${service}"
  chmod 0755 "/opt/${app}/${app}"

  cat >"/etc/systemd/system/${service}.service" <<EOF
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

install_node() {
  log "Installing Node.js 22"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' \
    >/etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
  corepack enable
}

install_seerr() {
  log "Installing Seerr"
  install_node
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
Type=simple
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

main() {
  install_dependencies
  create_media_user
  install_arr Prowlarr Prowlarr/Prowlarr prowlarr
  install_arr Sonarr Sonarr/Sonarr sonarr
  install_arr Radarr Radarr/Radarr radarr
  install_arr Lidarr Lidarr/Lidarr lidarr
  install_seerr
  log "Installed services"
  systemctl --no-pager --full status prowlarr sonarr radarr lidarr seerr || true
}

main "$@"
