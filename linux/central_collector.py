#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Coletor Central e Servidor de Dashboard do PCProcessMonitor
Desenvolvido para execução leve e de alta performance em Linux Mint / Debian / Ubuntu.
Compatível com Python 3.8+ sem dependências externas.
"""

import os
import sys
import time
import json
import socket
import datetime
import threading
import subprocess
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT_WEB = 8080
DEFAULT_DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
WEB_DIR = os.path.dirname(os.path.abspath(__file__))

MACHINES = ["JFMELGACO-1", "JFMELGACO-2", "JFMELGACO-3", "JFMELGACO-4"]
HOST_MAP = {
    "JFMELGACO-1": "127.0.0.1",
    "JFMELGACO-2": "192.168.3.87",
    "JFMELGACO-3": "192.168.3.41",
    "JFMELGACO-4": "192.168.3.39"
}

RESOLVED_IPS = dict(HOST_MAP)

MAX_POINTS = 300


def resolve_host(pc):
    """Retorna o IP cacheado de pc, com fallback para HOST_MAP."""
    if pc == "JFMELGACO-1":
        return "127.0.0.1"
    return RESOLVED_IPS.get(pc, HOST_MAP.get(pc, "127.0.0.1"))


def try_refresh_host(pc):
    """Atualiza o cache de IP via mDNS caso o DHCP tenha alterado o endereço."""
    if pc == "JFMELGACO-1":
        return "127.0.0.1"
    for candidate in [f"{pc.lower()}.local", f"{pc}.local", pc.lower(), pc]:
        try:
            ip = socket.gethostbyname(candidate)
            if ip:
                RESOLVED_IPS[pc] = ip
                return ip
        except Exception:
            pass
    return RESOLVED_IPS.get(pc, HOST_MAP.get(pc, "127.0.0.1"))


def format_speed(bytes_per_sec):
    if not bytes_per_sec or bytes_per_sec <= 0:
        return "   0 KB/s"
    mb = 1024.0 * 1024.0
    kb = 1024.0
    if bytes_per_sec >= mb:
        return f"{bytes_per_sec / mb:6.1f} MB/s"
    return f"{bytes_per_sec / kb:6.0f} KB/s"


def ping_host(host):
    """Executa ping ICMP rápido (timeout 1s) e retorna RTT em ms ou None."""
    try:
        t0 = time.time()
        res = subprocess.run(
            ["ping", "-c", "1", "-W", "1", host],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        rtt_ms = round((time.time() - t0) * 1000)
        if res.returncode == 0:
            return max(1, rtt_ms)
        return None
    except Exception:
        return None


def fetch_metrics(pc):
    """Consulta métricas via HTTP (porta 9123) com timeout de 2.5s."""
    host = resolve_host(pc)
    url = f"http://{host}:9123/metrics"
    t0 = time.time()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "PCProcessMonitor-Central/2.0"})
        with urllib.request.urlopen(req, timeout=2.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed_ms = round((time.time() - t0) * 1000)
            return {
                "success": True,
                "pc": pc,
                "data": data,
                "ping": elapsed_ms
            }
    except Exception as e:
        # Se falhou, tenta atualizar o IP via mDNS caso o DHCP tenha alterado o IP
        new_host = try_refresh_host(pc)
        if new_host and new_host != host:
            try:
                retry_url = f"http://{new_host}:9123/metrics"
                req = urllib.request.Request(retry_url, headers={"User-Agent": "PCProcessMonitor-Central/2.0"})
                with urllib.request.urlopen(req, timeout=2.0) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    elapsed_ms = round((time.time() - t0) * 1000)
                    return {
                        "success": True,
                        "pc": pc,
                        "data": data,
                        "ping": elapsed_ms
                    }
            except Exception:
                pass
        return {
            "success": False,
            "pc": pc,
            "error": str(e),
            "ping": ping_host(new_host or host)
        }


class CentralCollector:
    def __init__(self, data_dir=None, web_dir=None):
        self.data_dir = data_dir or DEFAULT_DATA_DIR
        self.web_dir = web_dir or WEB_DIR
        os.makedirs(self.data_dir, exist_ok=True)

        self.lock = threading.Lock()
        self.interval = 1
        self.running = True

        # Buffers históricos em memória para os gráficos (até MAX_POINTS)
        self.timestamps = []
        self.machine_data = {}
        for pc in MACHINES:
            self.machine_data[pc] = {
                "cpu": [], "ramPct": [], "ramUsed": [], "ramTotal": 0.0,
                "diskFree": [], "diskTotal": 0.0, "diskPct": [],
                "ioR": [], "ioW": [], "rx": [], "tx": [],
                "ping": [], "uptime": [], "bootDate": [],
                "temp": [], "internet": []
            }

        self.latest_stats = {}
        self.latest_top_processes = {}
        self.log_file_path = None
        self.current_log_date = None

        self.session_start_dt = datetime.datetime.now()
        self.session_start_time = self.session_start_dt.strftime("%H:%M:%S")
        self.total_collected = 0

        # Tenta restaurar início da sessão e contagem acumulada do log diário se já existir
        self._init_session_from_existing_log()

        # Resolve IPs dinâmicos dos nós remotos na inicialização
        for pc in MACHINES:
            if pc != "JFMELGACO-1":
                try_refresh_host(pc)

    def _init_session_from_existing_log(self):
        """Inicializa startTime e total_collected a partir do log diário se já existir."""
        today_prefix = datetime.datetime.now().strftime("%Y%m%d")
        try:
            if not os.path.exists(self.data_dir):
                return
            files = [f for f in os.listdir(self.data_dir) if f.startswith(today_prefix) and f.endswith(".txt")]
            if not files:
                return
            files.sort()
            latest_file = os.path.join(self.data_dir, files[-1])
            first_ts = None
            sample_count = 0
            with open(latest_file, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if "DESEMPENHO DA REDE" in line:
                        sample_count += 1
                        if not first_ts and line.startswith("["):
                            end_bracket = line.find("]")
                            if end_bracket != -1:
                                first_ts = line[1:end_bracket].strip()
            if first_ts:
                self.session_start_time = first_ts
            if sample_count > 0:
                self.total_collected = sample_count
                self.log_file_path = latest_file
                self.current_log_date = today_prefix
                print(f"[COLETOR] Sessao restaurada do log: inicio={self.session_start_time}, amostras_anteriores={self.total_collected}")
        except Exception as e:
            print(f"[COLETOR] Aviso ao inspecionar log existente: {e}")

    def get_log_file(self):
        now_str = datetime.datetime.now().strftime("%Y%m%d")
        if self.current_log_date != now_str or not self.log_file_path or not os.path.exists(self.log_file_path):
            self.current_log_date = now_str
            timestamp = datetime.datetime.now().strftime("%Y%m%d - %H%M")
            self.log_file_path = os.path.join(self.data_dir, f"{timestamp} - PC Processmonitor.txt")
        return self.log_file_path

    def collect_cycle(self):
        # 1. Coleta concorrente dos 4 nós
        results = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            future_to_pc = {
                executor.submit(fetch_metrics, pc): pc
                for pc in MACHINES
            }
            for fut in future_to_pc:
                res = fut.result()
                results[res["pc"]] = res

        now = datetime.datetime.now()
        ts_str = now.strftime("%H:%M:%S")

        with self.lock:
            self.total_collected += 1
            self.timestamps.append(ts_str)
            if len(self.timestamps) > MAX_POINTS:
                self.timestamps.pop(0)

            console_lines = []
            file_lines = []

            for pc in MACHINES:
                res = results.get(pc, {"success": False})
                md = self.machine_data[pc]

                if res["success"]:
                    d = res["data"]
                    cpu = int(round(d.get("Cpu", 0)))
                    tot_ram = float(d.get("TotalRam", 0.0))
                    used_ram = float(d.get("UsedRam", 0.0))
                    pct_ram = int(round(d.get("PctRam", 0)))
                    disk_tot = float(d.get("DiskTotal", 0.0))
                    disk_free = float(d.get("DiskFree", 0.0))
                    disk_pct = int(round(d.get("DiskPct", 0)))
                    io_r = float(d.get("DiskReadBytes", 0.0))
                    io_w = float(d.get("DiskWriteBytes", 0.0))
                    rx = float(d.get("RxBytes", 0.0))
                    tx = float(d.get("TxBytes", 0.0))
                    ping = res["ping"]
                    uptime = str(d.get("Uptime", "---"))
                    boot = str(d.get("BootDate", "---"))
                    temp = d.get("Temp")
                    temp_val = int(round(float(temp))) if temp is not None else None
                    top_procs = d.get("TopProcesses", [])

                    md["ramTotal"] = tot_ram
                    md["diskTotal"] = disk_tot

                    md["cpu"].append(cpu)
                    md["ramPct"].append(pct_ram)
                    md["ramUsed"].append(round(used_ram, 1))
                    md["diskFree"].append(round(disk_free, 1))
                    md["diskPct"].append(disk_pct)
                    md["ioR"].append(round(io_r / 1024.0, 1))  # KB/s
                    md["ioW"].append(round(io_w / 1024.0, 1))  # KB/s
                    md["rx"].append(round(rx / 1024.0, 1))    # KB/s
                    md["tx"].append(round(tx / 1024.0, 1))    # KB/s
                    md["ping"].append(ping)
                    md["uptime"].append(uptime)
                    md["bootDate"].append(boot)
                    md["temp"].append(temp_val)
                    md["internet"].append(round((rx + tx) / (1024.0 * 1024.0) * 8.0, 2)) # Mbps

                    if top_procs:
                        self.latest_top_processes[pc] = top_procs

                    # Barras de caracteres para log texto
                    fill_cpu = min(10, max(0, round((cpu / 100.0) * 10)))
                    bar_cpu = ("=" * fill_cpu) + ("-" * (10 - fill_cpu))
                    fill_ram = min(10, max(0, round((pct_ram / 100.0) * 10)))
                    bar_ram = ("=" * fill_ram) + ("-" * (10 - fill_ram))

                    r_str = format_speed(io_r)
                    w_str = format_speed(io_w)
                    rx_str = format_speed(rx)
                    tx_str = format_speed(tx)
                    temp_str = f"Temp: {temp_val}°C" if temp_val is not None else "Temp: ---"
                    ping_str = f"Ping: {ping:3d}ms" if ping is not None else "Ping: ---"

                    boot_short = boot[:16] if len(boot) >= 16 else boot
                    display_pc = f"{pc} (Local)" if pc == "JFMELGACO-1" else pc

                    f_line = (f"ONLINE     {display_pc:<22} [{bar_cpu}] {cpu:3d}% "
                              f"[{bar_ram}] {used_ram:4.1f}/{tot_ram:4.1f} GB ({pct_ram:2d}%) "
                              f"{disk_free:5.1f} GB liv ({disk_pct:2d}% us)  "
                              f"R: {r_str} | W: {w_str} "
                              f"Rx: {rx_str} | Tx: {tx_str}  "
                              f"{ping_str}  Uptime: {uptime:>7} (Boot: {boot_short})  {temp_str}")
                    file_lines.append(f_line)
                    console_lines.append(f_line)

                else:
                    # Falha na coleta
                    ping = res.get("ping")
                    status_str = "SEM ACESSO" if ping is not None else "OFFLINE   "
                    ping_str = f"Ping: {ping:3d}ms" if ping is not None else "Ping: ---"
                    display_pc = f"{pc} (Local)" if pc == "JFMELGACO-1" else pc

                    md["cpu"].append(None)
                    md["ramPct"].append(None)
                    md["ramUsed"].append(None)
                    md["diskFree"].append(None)
                    md["diskPct"].append(None)
                    md["ioR"].append(None)
                    md["ioW"].append(None)
                    md["rx"].append(None)
                    md["tx"].append(None)
                    md["ping"].append(ping)
                    md["uptime"].append("---")
                    md["bootDate"].append("---")
                    md["temp"].append(None)
                    md["internet"].append(0)

                    f_line = (f"{status_str:<10} {display_pc:<22} ---              "
                              f"---                          ---                    "
                              f"---                      ---                       "
                              f"{ping_str}  Uptime:     ---  Temp: ---")
                    file_lines.append(f_line)
                    console_lines.append(f_line)

                # Mantém buffers limitados a MAX_POINTS
                for key in ["cpu", "ramPct", "ramUsed", "diskFree", "diskPct", "ioR", "ioW", "rx", "tx", "ping", "uptime", "bootDate", "temp", "internet"]:
                    if len(md[key]) > MAX_POINTS:
                        md[key].pop(0)

            # Atualiza stats consolidado para cada nó
            for pc in MACHINES:
                md = self.machine_data[pc]
                valid_cpu = [v for v in md["cpu"] if v is not None]
                valid_ram = [v for v in md["ramPct"] if v is not None]
                valid_ping = [v for v in md["ping"] if v is not None]
                valid_temps = [v for v in md["temp"] if v is not None and v > 0]
                valid_disk = [v for v in md["diskFree"] if v is not None]
                valid_disk_pct = [v for v in md["diskPct"] if v is not None]
                valid_rx = [v for v in md["rx"] if v is not None]
                valid_tx = [v for v in md["tx"] if v is not None]
                valid_io_r = [v for v in md["ioR"] if v is not None]
                valid_io_w = [v for v in md["ioW"] if v is not None]

                is_online = bool(md["cpu"] and md["cpu"][-1] is not None)
                latest_cpu = md["cpu"][-1] if is_online else 0
                latest_ram = md["ramPct"][-1] if is_online else 0
                latest_temp = valid_temps[-1] if (is_online and valid_temps) else None
                latest_ping = valid_ping[-1] if valid_ping else 0
                disk_free_val = valid_disk[-1] if valid_disk else 0.0
                disk_pct_val = valid_disk_pct[-1] if valid_disk_pct else 0
                uptime_val = md["uptime"][-1] if (is_online and md["uptime"]) else "---"
                boot_val = md["bootDate"][-1] if (is_online and md["bootDate"]) else "---"

                avg_cpu = round(sum(valid_cpu) / len(valid_cpu), 1) if valid_cpu else 0
                avg_ram = round(sum(valid_ram) / len(valid_ram), 1) if valid_ram else 0
                avg_ping = round(sum(valid_ping) / len(valid_ping), 1) if valid_ping else 0
                max_cpu = max(valid_cpu) if valid_cpu else 0
                max_ram = max(valid_ram) if valid_ram else 0
                max_ping = max(valid_ping) if valid_ping else 0
                max_rx = max(valid_rx) if valid_rx else 0
                max_tx = max(valid_tx) if valid_tx else 0
                max_io_r = max(valid_io_r) if valid_io_r else 0
                max_io_w = max(valid_io_w) if valid_io_w else 0

                is_cpu_alert = bool(is_online and (latest_cpu >= 85 or avg_cpu >= 85))
                is_ram_alert = bool(is_online and (latest_ram >= 90 or avg_ram >= 90))
                is_disk_alert = bool(is_online and (disk_pct_val >= 90 or (0 < disk_free_val <= 15)))
                is_temp_alert = bool(is_online and latest_temp and latest_temp >= 75)
                has_alert = is_cpu_alert or is_ram_alert or is_disk_alert or is_temp_alert

                alert_reasons = []
                if is_cpu_alert: alert_reasons.append(f"CPU: {latest_cpu}% (>=85%)")
                if is_ram_alert: alert_reasons.append(f"RAM: {latest_ram}% (>=90%)")
                if is_disk_alert: alert_reasons.append(f"Disco: {disk_free_val}GB livres")
                if is_temp_alert: alert_reasons.append(f"Temp: {latest_temp}°C (>=75°C)")
                alert_title = ("Alerta: " + " | ".join(alert_reasons)) if alert_reasons else ""

                self.latest_stats[pc] = {
                    "isOnline": is_online,
                    "statusText": "Online" if is_online else "Offline",
                    "onlineTextClass": "text-emerald-400" if is_online else "text-red-400 font-bold",
                    "onlineDotClass": "bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.8)]" if is_online else "bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.9)]",
                    "latestCpu": latest_cpu,
                    "latestRam": latest_ram,
                    "latestTemp": latest_temp,
                    "latestRx": md["rx"][-1] if is_online else 0,
                    "latestTx": md["tx"][-1] if is_online else 0,
                    "latestIoR": md["ioR"][-1] if is_online else 0,
                    "latestIoW": md["ioW"][-1] if is_online else 0,
                    "ping": latest_ping,
                    "avgCpu": avg_cpu,
                    "avgRam": avg_ram,
                    "avgPing": avg_ping,
                    "maxCpu": max_cpu,
                    "maxRam": max_ram,
                    "maxPing": max_ping,
                    "maxRx": max_rx,
                    "maxTx": max_tx,
                    "maxIoR": max_io_r,
                    "maxIoW": max_io_w,
                    "diskFree": disk_free_val,
                    "diskPct": disk_pct_val,
                    "ramTotal": md["ramTotal"],
                    "uptime": uptime_val,
                    "bootDate": boot_val,
                    "isCpuAlert": is_cpu_alert,
                    "isRamAlert": is_ram_alert,
                    "isDiskAlert": is_disk_alert,
                    "isTempAlert": is_temp_alert,
                    "hasAlert": has_alert,
                    "alertTitle": alert_title
                }

            # 2. Grava bloco no arquivo texto canônico diário
            log_path = self.get_log_file()
            block_lines = [
                f"[{ts_str}] ============================== DESEMPENHO DA REDE (JFMELGACO) ==============================",
                "Status     Computador             CPU              RAM                          Disco C:               Disco I/O (R / W)        Rede (Rx / Tx)            Latência (Ping)     Uptime / Último Boot             Temperatura",
                "---------- ----------             ---              ---                          --------               -----------------        --------------            ---------------     --------------------             -----------"
            ] + file_lines
            block_content = "\n".join(block_lines) + "\n"
            try:
                with open(log_path, "a", encoding="utf-8") as f:
                    f.write(block_content)
            except Exception as e:
                print(f"[ERRO] Falha ao gravar log texto: {e}", file=sys.stderr)

            # 3. Grava dashboard_data.js e top_processes.json
            payload = {
                "startTime": self.session_start_time,
                "endTime": self.timestamps[-1] if self.timestamps else "--:--:--",
                "windowStartTime": self.timestamps[0] if self.timestamps else "--:--:--",
                "totalPoints": self.total_collected,
                "windowPoints": len(self.timestamps),
                "timestamps": list(self.timestamps),
                "rawData": self.machine_data,
                "stats": self.latest_stats,
                "topProcesses": self.latest_top_processes
            }

            js_path = os.path.join(self.web_dir, "dashboard_data.js")
            tmp_js_path = js_path + ".tmp"
            try:
                js_content = f"window.updateDashboardData({json.dumps(payload, ensure_ascii=False)});\n"
                with open(tmp_js_path, "w", encoding="utf-8") as f:
                    f.write(js_content)
                os.replace(tmp_js_path, js_path)
            except Exception as e:
                print(f"[ERRO] Falha ao gravar dashboard_data.js: {e}", file=sys.stderr)

            # Top processes JSON
            tp_path = os.path.join(self.data_dir, "top_processes.json")
            tmp_tp_path = tp_path + ".tmp"
            try:
                with open(tmp_tp_path, "w", encoding="utf-8") as f:
                    json.dump(self.latest_top_processes, f, ensure_ascii=False)
                os.replace(tmp_tp_path, tp_path)
            except Exception:
                pass

        return ts_str, len(self.timestamps)

    def run_collector_loop(self):
        print(f"[COLETOR] Loop de amostragem iniciado (intervalo: {self.interval}s)...")
        while self.running:
            t_start = time.time()
            try:
                ts, n = self.collect_cycle()
                # Recarrega intervalo de monitor_config.json dinamicamente se existir
                cfg_path = os.path.join(self.web_dir, "monitor_config.json")
                if os.path.exists(cfg_path):
                    try:
                        with open(cfg_path, "r", encoding="utf-8") as cf:
                            cfg = json.load(cf)
                            if "intervalSeconds" in cfg and cfg["intervalSeconds"] >= 1:
                                self.interval = int(cfg["intervalSeconds"])
                    except Exception:
                        pass
            except Exception as e:
                print(f"[ERRO] Falha no ciclo de coleta: {e}", file=sys.stderr)

            elapsed = time.time() - t_start
            sleep_time = max(0.1, self.interval - elapsed)
            time.sleep(sleep_time)


class DashboardHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        # Desativa expressamente o cache HTTP para dados dinamicos e paginas do dashboard
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def do_GET(self):
        if self.path in ["/", "/index.html", "/dashboard"]:
            self.path = "/dashboard_desempenho.html"
        elif self.path == "/api/status":
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            data = {
                "status": "online",
                "host": socket.gethostname(),
                "time": datetime.datetime.now().isoformat()
            }
            if collector_instance:
                data["sessionStartTime"] = collector_instance.session_start_time
                data["totalCollected"] = collector_instance.total_collected
            self.wfile.write(json.dumps(data).encode("utf-8"))
            return
        return super().do_GET()

    def log_message(self, format, *args):
        # Desativa logs de requisicoes HTTP para economizar IO e CPU
        pass


collector_instance = None


def run_web_server(port=PORT_WEB):
    server = HTTPServer(("0.0.0.0", port), DashboardHandler)
    print(f"[WEB] Dashboard Web Server ativo em http://0.0.0.0:{port}/ (acesso: http://192.168.3.57:{port}/)")
    server.serve_forever()


if __name__ == "__main__":
    print("=" * 70)
    print(" PCProcessMonitor - Servidor Coletor Central (Linux Mint / Debian)")
    print("=" * 70)
    
    collector = CentralCollector(data_dir=DEFAULT_DATA_DIR, web_dir=WEB_DIR)
    collector_instance = collector

    # Inicia o servidor Web em thread de background
    web_thread = threading.Thread(target=run_web_server, args=(PORT_WEB,), daemon=True)
    web_thread.start()

    # Executa a primeira coleta antes de rodar o loop
    print("[COLETOR] Executando primeira amostragem de calibração...")
    collector.collect_cycle()
    print("[COLETOR] Primeira amostragem concluída com sucesso.")

    # Roda o loop contínuo do coletor
    try:
        collector.run_collector_loop()
    except KeyboardInterrupt:
        print("\n[COLETOR] Encerrando serviço...")
        collector.running = False
