#!/usr/bin/env bash
# Custom Arr Stack creator: one LXC containing Prowlarr, Sonarr, Radarr, Lidarr, and Seerr.
set -eEo pipefail

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

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

run_custom_installer() {
  local installer
  installer="$(mktemp /tmp/arr-stack-install.XXXXXX.sh)"
  trap 'rm -f "$installer"' RETURN

  msg_info "Downloading custom Arr Stack installer"
  curl -fsSL "$CUSTOM_INSTALLER_URL" -o "$installer" || {
    msg_error "Unable to download $CUSTOM_INSTALLER_URL"
    return 1
  }
  sed -i 's/\r$//' "$installer"
  head -n1 "$installer" | grep -q '^#!/usr/bin/env bash' || {
    msg_error "Downloaded file is not a Bash script"
    return 1
  }

  pct push "$CTID" "$installer" /root/arr-stack-install.sh --perms 700
  msg_info "Installing Arr Stack inside CT ${CTID}"
  pct exec "$CTID" -- bash /root/arr-stack-install.sh
  pct exec "$CTID" -- rm -f /root/arr-stack-install.sh
}

start
# build_container attempts an upstream install/arr-stack.sh lookup that does not
# exist. It may print one 404; this does not prevent CT creation. The custom
# installer below performs the actual application installation.
build_container
run_custom_installer || {
  msg_error "CT ${CTID} exists, but Arr Stack installation failed."
  exit 1
}

description
msg_ok "Completed successfully!"
echo -e "${INFO}${YW}All services use the same container IP:${CL}"
echo -e "${GATEWAY}${BGN}Prowlarr: http://${IP}:9696${CL}"
echo -e "${GATEWAY}${BGN}Sonarr:   http://${IP}:8989${CL}"
echo -e "${GATEWAY}${BGN}Radarr:   http://${IP}:7878${CL}"
echo -e "${GATEWAY}${BGN}Lidarr:   http://${IP}:8686${CL}"
echo -e "${GATEWAY}${BGN}Seerr:    http://${IP}:5055${CL}"
