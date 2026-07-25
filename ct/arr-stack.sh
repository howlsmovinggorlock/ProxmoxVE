#!/usr/bin/env bash
# Single-LXC Servarr stack creator for Proxmox VE
set -eEo pipefail

source <(curl -fsSL \
https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Arr Stack"
var_tags="${var_tags:-arr;servarr}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

CUSTOM_INSTALLER_URL="https://raw.githubusercontent.com/howlsmovinggorlock/ProxmoxVE/main/install/arr-stack-install.sh"

header_info "$APP"
variables
color
catch_errors

start
build_container
description

msg_info "Installing Arr Stack services inside LXC..."

if ! curl -fsSL "$CUSTOM_INSTALLER_URL" | lxc-attach -n "$CTID" -- bash; then
  msg_error "Custom Arr Stack installation failed."
  msg_error "The container was created, but its services may be incomplete."
  exit 1
fi

msg_ok "Completed successfully!"
echo
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}All services use the same container IP:${CL}"
echo -e "${GATEWAY}${BGN}Prowlarr: http://${IP}:9696${CL}"
echo -e "${GATEWAY}${BGN}Sonarr:   http://${IP}:8989${CL}"
echo -e "${GATEWAY}${BGN}Radarr:   http://${IP}:7878${CL}"
echo -e "${GATEWAY}${BGN}Lidarr:   http://${IP}:8686${CL}"
echo -e "${GATEWAY}${BGN}Seerr:    http://${IP}:5055${CL}"
