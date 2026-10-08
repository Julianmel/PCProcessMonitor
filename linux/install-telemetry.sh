#!/bin/bash
set -e

echo "============================================================"
echo "Instalador do PCProcessMonitor Telemetry Agent (Linux Mint)"
echo "============================================================"

# Garante privilégios de root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute este instalador como root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cria diretório de destino
mkdir -p /opt/pcprocessmonitor

# Copia script python
if [ -f "$SCRIPT_DIR/pc_telemetry.py" ]; then
    cp "$SCRIPT_DIR/pc_telemetry.py" /opt/pcprocessmonitor/pc_telemetry.py
else
    echo "Baixando pc_telemetry.py do GitHub..."
    curl -sSL "https://raw.githubusercontent.com/Julianmel/PCProcessMonitor/main/linux/pc_telemetry.py" -o /opt/pcprocessmonitor/pc_telemetry.py
fi

chmod +x /opt/pcprocessmonitor/pc_telemetry.py

# Cria serviço systemd
cat << 'EOF' > /etc/systemd/system/pc-telemetry.service
[Unit]
Description=PCProcessMonitor - Linux Telemetry Agent
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/pcprocessmonitor/pc_telemetry.py
Restart=always
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# Recarrega e habilita serviço
systemctl daemon-reload
systemctl enable pc-telemetry.service
systemctl restart pc-telemetry.service

# Configura firewall ufw se estiver ativo
if command -v ufw >/dev/null 2>&1; then
    ufw allow 9123/tcp comment "PCProcessMonitor Telemetry" >/dev/null 2>&1 || true
fi

echo ""
echo "=== Telemetria instalada e em execucao com sucesso na porta 9123! ==="
echo "Testando resposta local:"
curl -s http://127.0.0.1:9123/metrics | cut -c 1-120
echo ""
