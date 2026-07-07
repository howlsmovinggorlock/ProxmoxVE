#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://prometheus.io/ | Github: https://github.com/prometheus/prometheus

APP="Prometheus"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
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
  if [[ ! -f /etc/systemd/system/prometheus.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "prometheus" "prometheus/prometheus"; then
    msg_info "Stopping Service"
    systemctl stop prometheus
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "prometheus" "prometheus/prometheus" "prebuild" "latest" "/usr/local/bin" "*linux-$(arch_resolve).tar.gz"
    rm -f /usr/local/bin/prometheus.yml

    msg_info "Starting Service"
    systemctl start prometheus
    msg_ok "Started Service"

    msg_ok "Updated successfully!"
  fi
  exit
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s grafana >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit 233
  fi

  if [[ -f /etc/apt/sources.list.d/grafana.list ]] || [[ ! -f /etc/apt/sources.list.d/grafana.sources ]]; then
    setup_deb822_repo \
      "grafana" \
      "https://apt.grafana.com/gpg.key" \
      "https://apt.grafana.com" \
      "stable" \
      "main"
  fi

  msg_info "Updating Grafana LXC"
  $STD apt update
  $STD apt --only-upgrade install -y grafana
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9090${CL}"
