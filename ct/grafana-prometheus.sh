#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Grafana-Prometheus"
var_tags="${var_tags:-monitoring;grafana;prometheus}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if command -v grafana-server >/dev/null 2>&1; then
    msg_info "Updating Grafana"
    apt-get update >/dev/null 2>&1
    apt-get install -y grafana >/dev/null 2>&1 || true
    systemctl restart grafana-server >/dev/null 2>&1 || true
    msg_ok "Grafana updated"
  else
    msg_error "Grafana not installed, skipping"
  fi

  if command -v prometheus >/dev/null 2>&1; then
    msg_info "Updating Prometheus"
    RELEASE=$(curl -fsSL https://api.github.com/repos/prometheus/prometheus/releases/latest | awk -F'"' '/tag_name/{print $4}' | sed 's/^v//')
    cd /tmp || exit
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${RELEASE}/prometheus-${RELEASE}.linux-amd64.tar.gz"
    tar -xzf "prometheus-${RELEASE}.linux-amd64.tar.gz"
    cd "prometheus-${RELEASE}.linux-amd64" || exit
    install -m 0755 prometheus /usr/local/bin/prometheus
    install -m 0755 promtool /usr/local/bin/promtool
    cp -r consoles console_libraries /etc/prometheus/
    systemctl restart prometheus >/dev/null 2>&1 || true
    cd /tmp || exit
    rm -rf "prometheus-${RELEASE}.linux-amd64" "prometheus-${RELEASE}.linux-amd64.tar.gz"
    msg_ok "Prometheus updated"
  else
    msg_error "Prometheus not installed, skipping"
  fi

  exit
}

start
build_container
description

msg_info "Installing dependencies in LXC"
pct exec "$CTID" -- bash -c "apt-get update && apt-get install -y curl wget gnupg apt-transport-https software-properties-common"
msg_ok "Dependencies installed"

msg_info "Installing Grafana"
pct exec "$CTID" -- bash -c "
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key &&
echo 'deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list &&
apt-get update &&
apt-get install -y grafana &&
systemctl enable grafana-server &&
systemctl start grafana-server
"
msg_ok "Grafana installed"

msg_info "Installing Prometheus"
pct exec "$CTID" -- bash -c '
set -e
useradd --no-create-home --shell /usr/sbin/nologin prometheus 2>/dev/null || true
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /var/lib/prometheus

cd /tmp
RELEASE=$(curl -fsSL https://api.github.com/repos/prometheus/prometheus/releases/latest | awk -F" "/tag_name/{print \$4}" | sed "s/^v//")
wget -q "https://github.com/prometheus/prometheus/releases/download/v${RELEASE}/prometheus-${RELEASE}.linux-amd64.tar.gz"
tar -xzf "prometheus-${RELEASE}.linux-amd64.tar.gz"
cd "prometheus-${RELEASE}.linux-amd64"

install -m 0755 prometheus /usr/local/bin/prometheus
install -m 0755 promtool /usr/local/bin/promtool
cp -r consoles console_libraries /etc/prometheus/
cp prometheus.yml /etc/prometheus/prometheus.yml

chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

cat >/etc/systemd/system/prometheus.service <<EOF2
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

cd /tmp
rm -rf "prometheus-${RELEASE}.linux-amd64" "prometheus-${RELEASE}.linux-amd64.tar.gz"
'
msg_ok "Prometheus installed"

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')

msg_ok "Completed Successfully!"
echo -e "${INFO}${YW}Grafana:${CL} ${BL}http://${IP}:3000${CL}"
echo -e "${INFO}${YW}Prometheus:${CL} ${BL}http://${IP}:9090${CL}"
