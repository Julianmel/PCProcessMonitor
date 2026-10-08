#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Agente de Telemetria Ultraleve para Linux Mint / Ubuntu / Debian
PCProcessMonitor - https://github.com/Julianmel/PCProcessMonitor
Exporta métricas de CPU, RAM, Disco, Rede, Temperatura e Processos em JSON via HTTP (porta 9123).
"""

import os
import sys
import time
import json
import socket
import datetime
import threading
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 9123
HOST = "0.0.0.0"

class MetricsCollector:
    def __init__(self):
        self.lock = threading.Lock()
        self.prev_cpu_total = 0
        self.prev_cpu_idle = 0
        self.prev_disk_read = 0
        self.prev_disk_write = 0
        self.prev_net_rx = 0
        self.prev_net_tx = 0
        self.prev_time = time.time()
        self.metrics = self.collect_initial()

    def collect_initial(self):
        return {
            "Cpu": 0,
            "TotalRam": 2.0,
            "UsedRam": 0.0,
            "PctRam": 0,
            "DiskTotal": 0.0,
            "DiskFree": 0.0,
            "DiskPct": 0,
            "DiskReadBytes": 0.0,
            "DiskWriteBytes": 0.0,
            "RxBytes": 0.0,
            "TxBytes": 0.0,
            "Temp": None,
            "Uptime": "0h 0m",
            "BootDate": "N/D",
            "TopProcesses": []
        }

    def read_cpu(self):
        try:
            with open("/proc/stat", "r") as f:
                line = f.readline()
            parts = [float(x) for x in line.strip().split()[1:]]
            idle = parts[3] + (parts[4] if len(parts) > 4 else 0.0)
            total = sum(parts)
            return total, idle
        except Exception:
            return 0.0, 0.0

    def read_memory(self):
        mem_total = 0.0
        mem_avail = 0.0
        try:
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        mem_total = float(line.split()[1]) / 1024.0 / 1024.0
                    elif line.startswith("MemAvailable:"):
                        mem_avail = float(line.split()[1]) / 1024.0 / 1024.0
            used = max(0.0, mem_total - mem_avail)
            pct = round((used / mem_total) * 100) if mem_total > 0 else 0
            return round(mem_total, 1), round(used, 1), int(pct)
        except Exception:
            return 2.0, 0.5, 25

    def read_disk(self):
        try:
            st = os.statvfs("/")
            total_gb = round((st.f_blocks * st.f_frsize) / (1024.0 ** 3), 1)
            free_gb = round((st.f_bavail * st.f_frsize) / (1024.0 ** 3), 1)
            used_gb = max(0.0, total_gb - free_gb)
            pct = round((used_gb / total_gb) * 100) if total_gb > 0 else 0
            return total_gb, free_gb, int(pct)
        except Exception:
            return 0.0, 0.0, 0

    def read_disk_io(self):
        r_bytes = 0.0
        w_bytes = 0.0
        try:
            with open("/proc/diskstats", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 14:
                        dev = parts[2]
                        # Discos físicos principais (ex: sda, nvme0n1, vda, mmcblk0)
                        if dev.startswith("sd") or dev.startswith("nvme0n1") or dev.startswith("vd"):
                            if not any(char.isdigit() for char in dev.replace("nvme0n1", "")):
                                r_bytes += float(parts[5]) * 512.0
                                w_bytes += float(parts[9]) * 512.0
        except Exception:
            pass
        return r_bytes, w_bytes

    def read_net(self):
        rx_total = 0.0
        tx_total = 0.0
        try:
            with open("/proc/net/dev", "r") as f:
                for line in f.readlines()[2:]:
                    if ":" in line:
                        iface, data = line.split(":", 1)
                        iface = iface.strip()
                        if iface != "lo":
                            parts = data.strip().split()
                            rx_total += float(parts[0])
                            tx_total += float(parts[8])
        except Exception:
            pass
        return rx_total, tx_total

    def read_temp(self):
        # 1. Tenta zonas térmicas ACPI / sysfs
        candidates = []
        try:
            base_dir = "/sys/class/thermal"
            if os.path.isdir(base_dir):
                for d in os.listdir(base_dir):
                    if d.startswith("thermal_zone"):
                        path = os.path.join(base_dir, d, "temp")
                        if os.path.isfile(path):
                            with open(path, "r") as tf:
                                val = float(tf.read().strip()) / 1000.0
                                if 15.0 <= val <= 115.0:
                                    candidates.append(val)
        except Exception:
            pass

        # 2. Tenta hwmon (sensores de coretemp/cpu)
        try:
            hwmon_dir = "/sys/class/hwmon"
            if os.path.isdir(hwmon_dir):
                for d in os.listdir(hwmon_dir):
                    sub = os.path.join(hwmon_dir, d)
                    for f in os.listdir(sub):
                        if f.startswith("temp") and f.endswith("_input"):
                            path = os.path.join(sub, f)
                            with open(path, "r") as tf:
                                val = float(tf.read().strip()) / 1000.0
                                if 15.0 <= val <= 115.0:
                                    candidates.append(val)
        except Exception:
            pass

        if candidates:
            return round(max(candidates), 0)
        return None

    def read_uptime(self):
        try:
            with open("/proc/uptime", "r") as f:
                up_sec = float(f.readline().split()[0])
            days = int(up_sec // 86400)
            hours = int((up_sec % 86400) // 3600)
            mins = int((up_sec % 3600) // 60)
            up_str = f"{days}d {hours}h" if days > 0 else f"{hours}h {mins}m"
            boot_dt = datetime.datetime.now() - datetime.timedelta(seconds=up_sec)
            boot_str = boot_dt.strftime("%d/%m/%Y %H:%M")
            return up_str, boot_str
        except Exception:
            return "N/D", "N/D"

    def read_top_processes(self):
        procs = []
        try:
            # ps -eo pid,comm,%cpu,rss --sort=-%cpu --no-headers
            cmd = ["ps", "-eo", "pid,comm,%cpu,rss", "--sort=-%cpu", "--no-headers"]
            out = subprocess.check_output(cmd, timeout=1).decode("utf-8", errors="ignore")
            lines = out.strip().split("\n")
            for line in lines[:10]:
                parts = line.strip().split()
                if len(parts) >= 4:
                    pid = int(parts[0])
                    name = parts[1]
                    cpu = float(parts[2].replace(",", "."))
                    rss_mb = round(float(parts[3]) / 1024.0, 1)
                    procs.append({
                        "Pid": pid,
                        "Name": name,
                        "Cpu": cpu,
                        "MemMB": rss_mb
                    })
        except Exception:
            pass
        return procs

    def update_cycle(self):
        now = time.time()
        dt = max(0.1, now - self.prev_time)
        self.prev_time = now

        # CPU %
        c_tot, c_idle = self.read_cpu()
        d_tot = max(1.0, c_tot - self.prev_cpu_total)
        d_idle = c_idle - self.prev_cpu_idle
        cpu_pct = max(0.0, min(100.0, round((1.0 - (d_idle / d_tot)) * 100.0, 0)))
        self.prev_cpu_total = c_tot
        self.prev_cpu_idle = c_idle

        # RAM
        tot_ram, used_ram, pct_ram = self.read_memory()

        # DISCO
        tot_disk, free_disk, pct_disk = self.read_disk()

        # DISK IO
        r_bytes, w_bytes = self.read_disk_io()
        dr_rate = max(0.0, (r_bytes - self.prev_disk_read) / dt) if self.prev_disk_read > 0 else 0.0
        dw_rate = max(0.0, (w_bytes - self.prev_disk_write) / dt) if self.prev_disk_write > 0 else 0.0
        self.prev_disk_read = r_bytes
        self.prev_disk_write = w_bytes

        # NET
        rx_b, tx_b = self.read_net()
        rx_rate = max(0.0, (rx_b - self.prev_net_rx) / dt) if self.prev_net_rx > 0 else 0.0
        tx_rate = max(0.0, (tx_b - self.prev_net_tx) / dt) if self.prev_net_tx > 0 else 0.0
        self.prev_net_rx = rx_b
        self.prev_net_tx = tx_b

        # TEMP, UPTIME, PROCS
        temp = self.read_temp()
        uptime_str, boot_str = self.read_uptime()
        procs = self.read_top_processes()

        data = {
            "Cpu": int(cpu_pct),
            "TotalRam": tot_ram,
            "UsedRam": used_ram,
            "PctRam": pct_ram,
            "DiskTotal": tot_disk,
            "DiskFree": free_disk,
            "DiskPct": pct_disk,
            "DiskReadBytes": round(dr_rate, 1),
            "DiskWriteBytes": round(dw_rate, 1),
            "RxBytes": round(rx_rate, 1),
            "TxBytes": round(tx_rate, 1),
            "Temp": temp,
            "Uptime": uptime_str,
            "BootDate": boot_str,
            "TopProcesses": procs
        }

        with self.lock:
            self.metrics = data

    def start_loop(self):
        # Inicializa baselines
        self.prev_cpu_total, self.prev_cpu_idle = self.read_cpu()
        self.prev_disk_read, self.prev_disk_write = self.read_disk_io()
        self.prev_net_rx, self.prev_net_tx = self.read_net()
        self.prev_time = time.time()
        time.sleep(1.0)
        self.update_cycle()

        while True:
            time.sleep(1.0)
            try:
                self.update_cycle()
            except Exception as e:
                pass

    def get_json(self):
        with self.lock:
            return json.dumps(self.metrics)

collector = MetricsCollector()

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ["/metrics", "/", "/data.json"]:
            payload = collector.get_json().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(payload)
        elif self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Silencia logs de requisição para não poluir o stdout
        return

def main():
    # Inicia coletor em thread de background
    t = threading.Thread(target=collector.start_loop, daemon=True)
    t.start()

    server = HTTPServer((HOST, PORT), MetricsHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
