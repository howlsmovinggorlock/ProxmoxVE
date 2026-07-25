#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"

case "$ARCH" in
  amd64) ARR_ARCH="linux-core-x64" ;;
  arm64) ARR_ARCH="linux-core-arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

install_deps() {
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    sqlite3 \
    tzdata \
    libicu-dev \
    libcurl4 \
    libssl3 \
    libgssapi-krb5-2 \
    libgdiplus \
    libchromiumcontent1 \
    mediainfo \
    xmlstarlet
}

create_user() {
  if ! id media >/dev/null 2>&1; then
    useradd \
      --system \
      --uid 1000 \
      --gid users \
      --home-dir /var/lib/media \
      --create-home \
      --shell /usr/sbin/nologin \
      media
  fi

  install -d -o media -g users -m 775 \
    /data \
    /data/torrents \
    /data/usenet \
    /data/media \
    /data/media/tv \
    /data/media/movies \
    /data/media/music
}

latest_tag() {
  local repo="$1"
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -r '.tag_name'
}

install_arr() {
  local app="$1"
  local repo="$2"
  local service="$3"
  local port="$4"
  local tag url archive tmpdir

  tag="$(latest_tag "$repo")"
  url="https://github.com/${repo}/releases/download/${tag}/${app}.master.${ARR_ARCH}.tar.gz"

  echo "Installing ${app} ${tag}"

  systemctl stop "$service" 2>/dev/null || true
  rm -rf "/opt/${app}"

  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/${app}.tar.gz"

  curl -fL "$url" -o "$archive"
  mkdir -p "/opt/${app}"
  tar -xzf "$archive" -C "/opt/${app}" --strip-components=1
  rm -rf "$tmpdir"

  chown -R media:users "/opt/${app}"
  chmod 775 "/opt/${app}"

  install -d -o media -g users -m 775 "/var/lib/${app}"

  cat > "/etc/systemd/system/${service}.service" <<EOF
[Unit]
Description=${app}
After=network-online.target
Wants=network-online.target

[Service]
User=media
Group=users
Type=simple
ExecStart=/opt/${app}/${app} -nobrowser -data=/var/lib/${app}/
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$service"

  echo "${app} available on port ${port}"
}

install_seerr() {
  local keyring="/usr/share/keyrings/nodesource.gpg"
  local repo_file="/etc/apt/sources.list.d/nodesource.list"

  echo "Installing Seerr"

  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o "$keyring"

  echo \
    "deb [signed-by=${keyring}] https://deb.nodesource.com/node_22.x nodistro main" \
    > "$repo_file"

  apt-get update
  apt-get install -y nodejs

  install -d -o media -g users -m 775 /opt/seerr /var/lib/seerr

  if [[ ! -d /opt/seerr/.git ]]; then
    git clone --depth=1 https://github.com/seerr-team/seerr.git /opt/seerr
  else
    git -C /opt/seerr pull --ff-only
  fi

  cd /opt/seerr
  npm ci --omit=dev
  npm run build

  chown -R media:users /opt/seerr /var/lib/seerr

  cat > /etc/systemd/system/seerr.service <<'EOF'
[Unit]
Description=Seerr
After=network-online.target
Wants=network-online.target

[Service]
User=media
Group=users
Type=simple
WorkingDirectory=/opt/seerr
Environment=NODE_ENV=production
Environment=PORT=5055
Environment=CONFIG_DIRECTORY=/var/lib/seerr
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now seerr
}

main() {
  install_deps
  create_user

  install_arr "Prowlarr" "Prowlarr/Prowlarr" "prowlarr" "9696"
  install_arr "Sonarr" "Sonarr/Sonarr" "sonarr" "8989"
  install_arr "Radarr" "Radarr/Radarr" "radarr" "7878"
  install_arr "Lidarr" "Lidarr/Lidarr" "lidarr" "8686"

  apt-get install -y git jq
  install_seerr

  systemctl --no-pager --full status \
    prowlarr sonarr radarr lidarr seerr || true
}

main "$@"