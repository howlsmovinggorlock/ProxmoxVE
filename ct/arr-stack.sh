#!/usr/bin/env bash
# Creates one LXC, then installs the complete Arr Stack from this fork.
# This script intentionally runs its own installer after build_container because
# the upstream build framework always resolves install scripts from its own repo.
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
  local host_script
  host_script="$(mktemp /tmp/arr-stack-install.XXXXXX.sh)"
  trap 'rm -f "$host_script"' RETURN

  msg_info "Downloading custom Arr Stack installer"
  if ! curl -fsSL "$CUSTOM_INSTALLER_URL" -o "$host_script"; then
    msg_error "Could not download: $CUSTOM_INSTALLER_URL"
    msg_error "Verify the repository is public and install/arr-stack-install.sh exists on branch main."
    return 1
  fi
  sed -i 's/\r$//' "$host_script"
  if ! head -n1 "$host_script" | grep -q '^#!/usr/bin/env bash'; then
    msg_error "Downloaded installer is not a Bash script."
    return 1
  fi

  pct push "$CTID" "$host_script" /root/arr-stack-install.sh --perms 700
  msg_info "Installing Prowlarr, Sonarr, Radarr, Lidarr, and Seerr"
  if ! pct exec "$CTID" -- bash /root/arr-stack-install.sh; then
    msg_error "Arr Stack installation failed. Inspect with: pct enter $CTID"
    return 1
  fi
  pct exec "$CTID" -- rm -f /root/arr-stack-install.sh
}

start
# build_container will emit one harmless upstream 404 because arr-stack is custom.
# It still creates and prepares the CT; the custom installer below performs the real install.
build_container

if ! run_custom_installer; then
  msg_error "Container $CTID was created but the Arr Stack was not installed successfully."
  exit 1
fi

description
msg_ok "Completed successfully!"
echo -e "${INFO}${YW}All services use the same container IP:${CL}"
echo -e "${GATEWAY}${BGN}Prowlarr: http://${IP}:9696${CL}"
echo -e "${GATEWAY}${BGN}Sonarr:   http://${IP}:8989${CL}"
echo -e "${GATEWAY}${BGN}Radarr:   http://${IP}:7878${CL}"
echo -e "${GATEWAY}${BGN}Lidarr:   http://${IP}:8686${CL}"
echo -e "${GATEWAY}${BGN}Seerr:    http://${IP}:5055${CL}"
