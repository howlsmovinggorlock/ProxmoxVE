#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Custom single-LXC Servarr stack
# Installs: Prowlarr, Sonarr, Radarr, Lidarr, Seerr

APP="Arr Stack"
var_tags="${var_tags:-arr;servarr}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Use the same container IP for all services:${CL}"
echo -e "${GATEWAY}${BGN}Prowlarr: http://${IP}:9696${CL}"
echo -e "${GATEWAY}${BGN}Sonarr:   http://${IP}:8989${CL}"
echo -e "${GATEWAY}${BGN}Radarr:   http://${IP}:7878${CL}"
echo -e "${GATEWAY}${BGN}Lidarr:   http://${IP}:8686${CL}"
echo -e "${GATEWAY}${BGN}Seerr:    http://${IP}:5055${CL}"