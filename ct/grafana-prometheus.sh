#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Combined Grafana + Prometheus LXC
# Based on community-scripts ProxmoxVE helper scripts by tteck (MIT license)

APP="Monitoring"
var_tags="${var_tags:-monitoring;grafana;prometheus}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2560}"
var_disk="${var_disk:-8}"
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

  if dpkg -s grafana >/dev/null 2>&1; then
    if [[ -f /etc/apt/sources.list.d/grafana.list ]]; then
      msg_info "Updating Grafana"
      $STD apt update
      $STD apt --only-upgrade install -y grafana
      msg_ok "Grafana updated successfully!"
    else
      msg_error "Grafana APT repo not found, skipping Grafana update."
    fi
  else
    msg_error "No Grafana installation found, skipping Grafana update."
  fi

  if [[ -f /etc/systemd/system/prometheus.service ]]; then
    msg_info "Updating Prometheus"
    RELEASE=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest \
      | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

    systemctl stop prometheus

    cd /tmp
    wget -q https://github.com/prometheus/prometheus/releases/download/v${RELEASE}/prometheus-${RELEASE}.linux-amd64.tar.gz
    tar -xf prometheus-${RELEASE}.linux-amd64.tar.gz
    cd prometheus-${RELEASE}.linux-amd64

    cp -f prometheus promtool /usr/local/bin/
    cp -rf consoles console_libraries /etc/prometheus/
    cp -f prometheus.yml /etc/prometheus/prometheus.yml

    cd /tmp
    rm -rf prometheus-${RELEASE}.linux-amd64 prometheus-${RELEASE}.linux-amd64.tar.gz

    systemctl start prometheus
    msg_ok "Prometheus updated successfully!"
  else
    msg_error "No Prometheus installation found, skipping Prometheus update."
  fi

  exit
}

start
build_container
description

monitor_script="/tmp/monitoring-install.sh"

cat <<'EOF' > "$monitor_script"
#!/usr/bin/env bash
set -e

echo "Updating package index..."
apt update

echo "Installing dependencies..."
apt install -y apt-transport-https software-properties-common wget curl gnupg

echo "Setting up Grafana APT repository..."
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list

echo "Installing Grafana..."
apt update
apt install -y grafana

echo "Enabling and starting Grafana service..."
systemctl enable --now grafana-server

echo "Installing Prometheus..."
useradd --no-create-home --shell /bin/false prometheus || true

mkdir -p /etc/prometheus /var/lib/prometheus

cd /tmp
RELEASE=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest \
  | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

wget -q https://github.com/prometheus/prometheus/releases/download/v${RELEASE}/prometheus-${RELEASE}.linux-amd64.tar.gz
tar -xvf prometheus-${RELEASE}.linux-amd64.tar.gz

cd prometheus-${RELEASE}.linux-amd64
cp prometheus promtool /usr/local/bin/
cp -r consoles console_libraries /etc/prometheus/
cp prometheus.yml /etc/prometheus/prometheus.yml

cd /tmp
rm -rf prometheus-${RELEASE}.linux-amd64 prometheus-${RELEASE}.linux-amd64.tar.gz

chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

cat >/etc/systemd/system/prometheus.service <<SERVICEEOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
SERVICEEOF

echo "Enabling and starting Prometheus service..."
systemctl daemon-reload
systemctl enable --now prometheus

echo "Monitoring stack installation completed."
EOF

pct push "$CTID" "$monitor_script" /root/monitoring-install.sh
pct exec "$CTID" -- bash /root/monitoring-install.sh
rm "$monitor_script"

IP=$(pct exec "$CTID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access Grafana using:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW}Access Prometheus using:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9090${CL}"
