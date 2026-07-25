#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://prowlarr.com/ | Github: https://github.com/Prowlarr/Prowlarr

APP="Prowlarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/lib/prowlarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "prowlarr" "Prowlarr/Prowlarr"; then
    msg_info "Stopping Service"
    systemctl stop prowlarr
    msg_ok "Stopped Service"

    rm -rf /opt/Prowlarr
    fetch_and_deploy_gh_release "prowlarr" "Prowlarr/Prowlarr" "prebuild" "latest" "/opt/Prowlarr" "Prowlarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz"
    chmod 775 /opt/Prowlarr

    msg_info "Starting Service"
    systemctl start prowlarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/radarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Radarr" "Radarr/Radarr"; then
    msg_info "Stopping Service"
    systemctl stop radarr
    msg_ok "Stopped Service"

    rm -rf /opt/Radarr
    fetch_and_deploy_gh_release "Radarr" "Radarr/Radarr" "prebuild" "latest" "/opt/Radarr" "Radarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz"
    chmod 775 /opt/Radarr

    msg_info "Starting Service"
    systemctl start radarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/sonarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Sonarr" "Sonarr/Sonarr"; then
    msg_info "Stopping Service"
    systemctl stop sonarr
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Sonarr" "Sonarr/Sonarr" "prebuild" "latest" "/opt/Sonarr" "Sonarr.main.*.linux-$(arch_resolve "x64" "arm64").tar.gz"

    msg_info "Starting Service"
    systemctl start sonarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/lidarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "lidarr" "Lidarr/Lidarr"; then
    msg_info "Stopping service"
    systemctl stop lidarr
    msg_ok "Service stopped"

    fetch_and_deploy_gh_release "lidarr" "Lidarr/Lidarr" "prebuild" "latest" "/opt/Lidarr" "Lidarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz"
    chmod 775 /opt/Lidarr

    msg_info "Starting service"
    systemctl start lidarr
    msg_ok "Service started"
    msg_ok "Updated successfully!"
  fi
  exit
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/seerr && ! -d /opt/jellyseerr && ! -d /opt/overseerr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Start Migration from Jellyseerr
  if [[ -f /etc/systemd/system/jellyseerr.service ]]; then
    msg_info "Stopping Jellyseerr"
    $STD systemctl stop jellyseerr || true
    $STD systemctl disable jellyseerr || true
    [ -f /etc/systemd/system/jellyseerr.service ] && rm -f /etc/systemd/system/jellyseerr.service
    msg_ok "Stopped Jellyseerr"

    msg_info "Creating Backup (Patience)"
    tar -czf /opt/jellyseerr_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C /opt jellyseerr
    msg_ok "Created Backup"

    msg_info "Migrating Jellyseerr to seerr"
    [ -d /opt/jellyseerr ] && mv /opt/jellyseerr /opt/seerr
    [ -d /etc/jellyseerr ] && mv /etc/jellyseerr /etc/seerr
    [ -f /etc/seerr/jellyseerr.conf ] && mv /etc/seerr/jellyseerr.conf /etc/seerr/seerr.conf
    cat <<EOF >/etc/systemd/system/seerr.service
[Unit]
Description=Seerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/seerr/seerr.conf
Environment=NODE_ENV=production
Type=exec
Restart=on-failure
WorkingDirectory=/opt/seerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q --now seerr
    msg_ok "Migrated Jellyserr to Seerr"
  fi
  # END Jellyseerr Migration

  # Start Migration from Overseerr
  if [[ -f /etc/systemd/system/overseerr.service ]]; then
    msg_info "Stopping Overseerr"
    $STD systemctl stop overseerr || true
    $STD systemctl disable overseerr || true
    [ -f /etc/systemd/system/overseerr.service ] && rm -f /etc/systemd/system/overseerr.service
    msg_ok "Stopped Overseerr"

    msg_info "Creating Backup (Patience)"
    tar -czf /opt/overseerr_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C /opt overseerr
    msg_ok "Created Backup"

    msg_info "Migrating Overseerr to seerr"
    [ -d /opt/overseerr ] && mv /opt/overseerr /opt/seerr
    mkdir -p /etc/seerr
    cat <<EOF >/etc/seerr/seerr.conf
## Seerr's default port is 5055, if you want to use both, change this.
## specify on which port to listen
PORT=5055

## specify on which interface to listen, by default seerr listens on all interfaces
#HOST=127.0.0.1

## Uncomment if you want to force Node.js to resolve IPv4 before IPv6 (advanced users only)
# FORCE_IPV4_FIRST=true
EOF
    cat <<EOF >/etc/systemd/system/seerr.service
[Unit]
Description=Seerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/seerr/seerr.conf
Environment=NODE_ENV=production
Type=exec
Restart=on-failure
WorkingDirectory=/opt/seerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q --now seerr
    msg_ok "Migrated Overseerr to Seerr"
  fi
  # END Overseerr Migration

  if check_for_gh_release "seerr" "seerr-team/seerr"; then
    msg_info "Stopping Service"
    systemctl stop seerr
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    cp -a /opt/seerr/config /opt/seerr_backup
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "seerr" "seerr-team/seerr" "tarball"

    ensure_dependencies build-essential python3-setuptools

    msg_info "Updating PNPM Version"
    pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/seerr/package.json)
    NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs
    msg_ok "Updated PNPM Version"

    msg_info "Updating Seerr"
    cd /opt/seerr
    rm -rf dist .next node_modules
    export CYPRESS_INSTALL_BINARY=0
    $STD pnpm install --frozen-lockfile
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD pnpm build
    msg_ok "Updated Seerr"

    msg_info "Restoring Backup"
    rm -rf /opt/seerr/config
    mv /opt/seerr_backup /opt/seerr/config
    msg_ok "Restored Backup"

    msg_info "Starting Service"
    systemctl start seerr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9696${CL}"
