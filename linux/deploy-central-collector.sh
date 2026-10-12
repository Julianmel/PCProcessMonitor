#!/bin/bash
# Script de Implantação do Coletor Central PCProcessMonitor no JFMELGACO-1 (Linux Mint)

set -e

INSTALL_DIR="/opt/pc-processmonitor"
DATA_DIR="${INSTALL_DIR}/data"
SERVICE_FILE="/etc/systemd/system/pc-central-collector.service"

echo "=========================================================="
echo " Implantando PCProcessMonitor Coletor Central no Linux Mint"
echo "=========================================================="

# 1. Cria diretórios
sudo mkdir -p "${INSTALL_DIR}"
sudo mkdir -p "${DATA_DIR}"
sudo chown -R julian:julian "${INSTALL_DIR}"

# 2. Copia arquivos da pasta local para /opt/pc-processmonitor
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cp "${SCRIPT_DIR}/central_collector.py" "${INSTALL_DIR}/"
cp "${PARENT_DIR}/dashboard_desempenho.html" "${INSTALL_DIR}/"
if [ -f "${PARENT_DIR}/dashboard_data.js" ]; then
    cp "${PARENT_DIR}/dashboard_data.js" "${INSTALL_DIR}/"
fi
if [ -f "${PARENT_DIR}/monitor_config.json" ]; then
    cp "${PARENT_DIR}/monitor_config.json" "${INSTALL_DIR}/"
fi
if [ -f "${PARENT_DIR}/machines.json" ]; then
    cp "${PARENT_DIR}/machines.json" "${INSTALL_DIR}/"
fi

chmod +x "${INSTALL_DIR}/central_collector.py"
sudo chown -R julian:julian "${INSTALL_DIR}"

# 3. Configura serviço systemd
sudo cp "${SCRIPT_DIR}/pc-central-collector.service" "${SERVICE_FILE}"
sudo chmod 644 "${SERVICE_FILE}"

sudo systemctl daemon-reload
sudo systemctl enable pc-central-collector.service
sudo systemctl restart pc-central-collector.service

echo "=========================================================="
echo " Coletor Central ativado com sucesso!"
echo " Status do serviço:"
sudo systemctl status pc-central-collector.service --no-pager
echo "=========================================================="
echo " Acesse o Dashboard em: http://192.168.3.57:8080/"
echo "=========================================================="
