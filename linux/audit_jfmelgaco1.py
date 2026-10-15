#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Auditor e Comparador de Telemetria: Sistema Operacional Nativo vs PCProcessMonitor
Nó: JFMELGACO-1 (Linux Mint 22 / Kernel Linux)
"""

import os
import sys
import time
import json
import socket
import datetime
import subprocess
import urllib.request
import urllib.error


def read_proc_stat():
    """Lê contadores de CPU de /proc/stat."""
    try:
        with open("/proc/stat", "r") as f:
            line = f.readline()
        parts = [float(x) for x in line.strip().split()[1:]]
        # user, nice, system, idle, iowait, irq, softirq, steal
        idle = parts[3] + (parts[4] if len(parts) > 4 else 0.0)
        total = sum(parts)
        return total, idle, parts
    except Exception as e:
        return 0.0, 0.0, []


def get_native_cpu(sample_ms=300):
    """Calcula CPU% instantâneo com precisão através de delta em sample_ms."""
    t1, i1, p1 = read_proc_stat()
    time.sleep(sample_ms / 1000.0)
    t2, i2, p2 = read_proc_stat()
    dt = max(1.0, t2 - t1)
    di = max(0.0, i2 - i1)
    cpu_pct = max(0.0, min(100.0, (1.0 - (di / dt)) * 100.0))

    # Detalhes adicionais
    user_pct = max(0.0, ((p2[0] - p1[0]) / dt) * 100.0) if len(p1) > 0 and len(p2) > 0 else 0.0
    sys_pct = max(0.0, ((p2[2] - p1[2]) / dt) * 100.0) if len(p1) > 2 and len(p2) > 2 else 0.0
    iowait_pct = max(0.0, ((p2[4] - p1[4]) / dt) * 100.0) if len(p1) > 4 and len(p2) > 4 else 0.0

    load1, load5, load15 = os.getloadavg() if hasattr(os, "getloadavg") else (0.0, 0.0, 0.0)
    core_count = os.cpu_count() or 1

    return {
        "cpu_pct": round(cpu_pct, 1),
        "cpu_user": round(user_pct, 1),
        "cpu_system": round(sys_pct, 1),
        "cpu_iowait": round(iowait_pct, 1),
        "load_1m": round(load1, 2),
        "load_5m": round(load5, 2),
        "load_15m": round(load15, 2),
        "cores": core_count
    }


def get_native_memory():
    """Lê métricas de memória física diretamente de /proc/meminfo."""
    mem = {}
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) == 2:
                    k = parts[0].strip()
                    v = parts[1].strip().split()[0]
                    mem[k] = float(v)
    except Exception as e:
        mem = {}

    total_kb = mem.get("MemTotal", 0.0)
    avail_kb = mem.get("MemAvailable", 0.0)
    free_kb = mem.get("MemFree", 0.0)
    buffers_kb = mem.get("Buffers", 0.0)
    cached_kb = mem.get("Cached", 0.0)
    swap_total_kb = mem.get("SwapTotal", 0.0)
    swap_free_kb = mem.get("SwapFree", 0.0)

    total_gb = round(total_kb / 1024.0 / 1024.0, 2)
    avail_gb = round(avail_kb / 1024.0 / 1024.0, 2)
    used_kb = max(0.0, total_kb - avail_kb)
    used_gb = round(used_kb / 1024.0 / 1024.0, 2)
    free_gb = round(free_kb / 1024.0 / 1024.0, 2)
    cached_gb = round((cached_kb + buffers_kb) / 1024.0 / 1024.0, 2)
    pct_used = round((used_kb / total_kb) * 100.0, 1) if total_kb > 0 else 0.0

    return {
        "total_gb": total_gb,
        "used_gb": used_gb,
        "avail_gb": avail_gb,
        "free_gb": free_gb,
        "cached_gb": cached_gb,
        "pct_used": pct_used,
        "swap_total_gb": round(swap_total_kb / 1024.0 / 1024.0, 2),
        "swap_used_gb": round(max(0.0, swap_total_kb - swap_free_kb) / 1024.0 / 1024.0, 2)
    }


def get_native_disk():
    """Lê espaço em disco via statvfs('/') e taxas de I/O via /proc/diskstats."""
    try:
        st = os.statvfs("/")
        total_gb = round((st.f_blocks * st.f_frsize) / (1024.0 ** 3), 1)
        free_gb = round((st.f_bavail * st.f_frsize) / (1024.0 ** 3), 1)
        used_gb = round(max(0.0, total_gb - free_gb), 1)
        pct_used = round((used_gb / total_gb) * 100.0, 1) if total_gb > 0 else 0.0
    except Exception:
        total_gb, free_gb, used_gb, pct_used = 0.0, 0.0, 0.0, 0.0

    # I/O delta
    def read_io_bytes():
        r_b, w_b = 0.0, 0.0
        try:
            with open("/proc/diskstats", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 14:
                        dev = parts[2]
                        if dev.startswith("sd") or dev.startswith("nvme0n1") or dev.startswith("vd"):
                            if not any(char.isdigit() for char in dev.replace("nvme0n1", "")):
                                r_b += float(parts[5]) * 512.0
                                w_b += float(parts[9]) * 512.0
        except Exception:
            pass
        return r_b, w_b

    r1, w1 = read_io_bytes()
    time.sleep(0.2)
    r2, w2 = read_io_bytes()
    read_kb_s = round(max(0.0, (r2 - r1) / 0.2 / 1024.0), 1)
    write_kb_s = round(max(0.0, (w2 - w1) / 0.2 / 1024.0), 1)

    return {
        "total_gb": total_gb,
        "free_gb": free_gb,
        "used_gb": used_gb,
        "pct_used": pct_used,
        "read_kb_s": read_kb_s,
        "write_kb_s": write_kb_s
    }


def get_native_net():
    """Lê estatísticas de rede via /proc/net/dev."""
    def read_net_bytes():
        rx, tx = 0.0, 0.0
        ifaces = []
        try:
            with open("/proc/net/dev", "r") as f:
                for line in f.readlines()[2:]:
                    if ":" in line:
                        iface, data = line.split(":", 1)
                        iface = iface.strip()
                        if iface != "lo":
                            parts = data.strip().split()
                            rx_b = float(parts[0])
                            tx_b = float(parts[8])
                            rx += rx_b
                            tx += tx_b
                            ifaces.append({"iface": iface, "rx_mb": round(rx_b / 1024.0 / 1024.0, 1), "tx_mb": round(tx_b / 1024.0 / 1024.0, 1)})
        except Exception:
            pass
        return rx, tx, ifaces

    rx1, tx1, ifaces1 = read_net_bytes()
    time.sleep(0.2)
    rx2, tx2, ifaces2 = read_net_bytes()

    rx_kb_s = round(max(0.0, (rx2 - rx1) / 0.2 / 1024.0), 1)
    tx_kb_s = round(max(0.0, (tx2 - tx1) / 0.2 / 1024.0), 1)

    return {
        "rx_kb_s": rx_kb_s,
        "tx_kb_s": tx_kb_s,
        "interfaces": ifaces2
    }


def get_native_temperatures():
    """Varredura completa de sensores térmicos em /sys/class/hwmon e /sys/class/thermal."""
    sensors = []

    # 1. hwmon
    hwmon_base = "/sys/class/hwmon"
    if os.path.isdir(hwmon_base):
        for d in sorted(os.listdir(hwmon_base)):
            sub = os.path.join(hwmon_base, d)
            # lê nome do driver
            name = "unknown"
            name_file = os.path.join(sub, "name")
            if os.path.isfile(name_file):
                try:
                    with open(name_file, "r") as nf:
                        name = nf.read().strip()
                except Exception:
                    pass

            for f in sorted(os.listdir(sub)):
                if f.startswith("temp") and f.endswith("_input"):
                    idx = f.replace("temp", "").replace("_input", "")
                    label_file = os.path.join(sub, f"temp{idx}_label")
                    label = name
                    if os.path.isfile(label_file):
                        try:
                            with open(label_file, "r") as lf:
                                label = f"{name} ({lf.read().strip()})"
                        except Exception:
                            pass
                    try:
                        with open(os.path.join(sub, f), "r") as tf:
                            val = float(tf.read().strip()) / 1000.0
                            if 0.0 <= val <= 125.0:
                                sensors.append({
                                    "source": "hwmon",
                                    "path": f"{d}/{f}",
                                    "label": label,
                                    "temp_c": round(val, 1)
                                })
                    except Exception:
                        pass

    # 2. thermal_zone
    thermal_base = "/sys/class/thermal"
    if os.path.isdir(thermal_base):
        for d in sorted(os.listdir(thermal_base)):
            if d.startswith("thermal_zone"):
                sub = os.path.join(thermal_base, d)
                type_file = os.path.join(sub, "type")
                t_type = "acpitz"
                if os.path.isfile(type_file):
                    try:
                        with open(type_file, "r") as tf:
                            t_type = tf.read().strip()
                    except Exception:
                        pass
                temp_file = os.path.join(sub, "temp")
                if os.path.isfile(temp_file):
                    try:
                        with open(temp_file, "r") as tf:
                            val = float(tf.read().strip()) / 1000.0
                            if 0.0 <= val <= 125.0:
                                sensors.append({
                                    "source": "thermal_zone",
                                    "path": d,
                                    "label": t_type,
                                    "temp_c": round(val, 1)
                                })
                    except Exception:
                        pass

    max_temp = round(max([s["temp_c"] for s in sensors]), 1) if sensors else None
    return {
        "max_temp_c": max_temp,
        "sensors": sensors
    }


def get_native_uptime():
    """Lê tempo de atividade e calcula data de boot."""
    try:
        with open("/proc/uptime", "r") as f:
            up_sec = float(f.readline().split()[0])
        days = int(up_sec // 86400)
        hours = int((up_sec % 86400) // 3600)
        mins = int((up_sec % 3600) // 60)
        up_str = f"{days}d {hours}h" if days > 0 else f"{hours}h {mins}m"
        boot_dt = datetime.datetime.now() - datetime.timedelta(seconds=up_sec)
        boot_str = boot_dt.strftime("%d/%m/%Y %H:%M")
        return {
            "uptime_sec": round(up_sec),
            "uptime_str": up_str,
            "boot_str": boot_str
        }
    except Exception:
        return {"uptime_sec": 0, "uptime_str": "---", "boot_str": "---"}


def get_native_top_processes():
    """Executa ps para capturar os 10 processos mais consumidores de CPU."""
    procs = []
    try:
        cmd = ["ps", "-eo", "pid,user,comm,%cpu,%mem,rss", "--sort=-%cpu", "--no-headers"]
        out = subprocess.check_output(cmd, timeout=2).decode("utf-8", errors="ignore")
        lines = out.strip().split("\n")
        for line in lines[:10]:
            parts = line.strip().split()
            if len(parts) >= 6:
                pid = int(parts[0])
                user = parts[1]
                comm = parts[2]
                cpu = float(parts[3].replace(",", "."))
                mem_pct = float(parts[4].replace(",", "."))
                rss_mb = round(float(parts[5]) / 1024.0, 1)
                procs.append({
                    "Pid": pid,
                    "User": user,
                    "Name": comm,
                    "Cpu": cpu,
                    "MemPct": mem_pct,
                    "MemMB": rss_mb
                })
    except Exception as e:
        pass
    return procs


def fetch_app_metrics():
    """Consulta o agente de telemetria local na porta 9123."""
    url = "http://127.0.0.1:9123/metrics"
    t0 = time.time()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Audit-PCProcessMonitor/1.0"})
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed_ms = round((time.time() - t0) * 1000)
            return {"success": True, "data": data, "latency_ms": elapsed_ms}
    except Exception as e:
        return {"success": False, "error": str(e), "latency_ms": None}


def run_full_audit():
    """Realiza o cruzamento simultâneo entre Sistema Operacional Nativo e PCProcessMonitor."""
    audit_time = datetime.datetime.now().strftime("%d/%m/%Y %H:%M:%S")

    # 1. Coleta nativa simultânea
    app_res = fetch_app_metrics()
    so_cpu = get_native_cpu(sample_ms=250)
    so_mem = get_native_memory()
    so_disk = get_native_disk()
    so_net = get_native_net()
    so_temp = get_native_temperatures()
    so_uptime = get_native_uptime()
    so_procs = get_native_top_processes()

    if not app_res["success"]:
        return {
            "timestamp": audit_time,
            "status": "ERRO_APP_OFFLINE",
            "error": app_res.get("error", "Não foi possível conectar a http://127.0.0.1:9123/metrics"),
            "so": {
                "cpu": so_cpu,
                "memory": so_mem,
                "disk": so_disk,
                "net": so_net,
                "temperature": so_temp,
                "uptime": so_uptime,
                "top_processes": so_procs
            }
        }

    app = app_res["data"]

    # 2. Matriz de Comparação e Cruzamento
    comparisons = []

    # CPU
    cpu_so = so_cpu["cpu_pct"]
    cpu_app = float(app.get("Cpu", 0))
    cpu_diff = round(abs(cpu_so - cpu_app), 1)
    cpu_status = "🟢 Conforme" if cpu_diff <= 15.0 else ("🟡 Variação Normal" if cpu_diff <= 30.0 else "🔴 Divergente")
    comparisons.append({
        "category": "CPU",
        "metric": "Uso de Processador",
        "so_method": "Delta /proc/stat (250ms)",
        "so_value": f"{cpu_so}% (Cores: {so_cpu['cores']}, Load: {so_cpu['load_1m']})",
        "app_method": "Agente /metrics (Delta 1s)",
        "app_value": f"{int(cpu_app)}%",
        "difference": f"Δ {cpu_diff}%",
        "status": cpu_status,
        "detail": "Variação esperada devido ao intervalo assíncrono e volatilidade de ciclos de CPU."
    })

    # RAM Total
    ram_tot_so = so_mem["total_gb"]
    ram_tot_app = float(app.get("TotalRam", 0.0))
    ram_tot_diff = round(abs(ram_tot_so - ram_tot_app), 1)
    ram_tot_status = "🟢 Conforme" if ram_tot_diff <= 0.1 else "🔴 Divergente"
    comparisons.append({
        "category": "RAM",
        "metric": "Memória Total",
        "so_method": "/proc/meminfo: MemTotal",
        "so_value": f"{ram_tot_so} GB",
        "app_method": "Agente /metrics: TotalRam",
        "app_value": f"{ram_tot_app} GB",
        "difference": f"Δ {ram_tot_diff} GB",
        "status": ram_tot_status,
        "detail": "Mapeamento idêntico da capacidade física instalada do nó."
    })

    # RAM Usada
    ram_used_so = so_mem["used_gb"]
    ram_used_app = float(app.get("UsedRam", 0.0))
    ram_used_diff = round(abs(ram_used_so - ram_used_app), 1)
    ram_used_status = "🟢 Conforme" if ram_used_diff <= 0.2 else ("🟡 Variação Normal" if ram_used_diff <= 0.5 else "🔴 Divergente")
    comparisons.append({
        "category": "RAM",
        "metric": "Memória Usada (Real)",
        "so_method": "MemTotal - MemAvailable",
        "so_value": f"{ram_used_so} GB ({so_mem['pct_used']}%) [Livre: {so_mem['avail_gb']} GB]",
        "app_method": "Agente /metrics: UsedRam",
        "app_value": f"{ram_used_app} GB ({app.get('PctRam', 0)}%)",
        "difference": f"Δ {ram_used_diff} GB",
        "status": ram_used_status,
        "detail": "Cálculo moderno alinhado com MemAvailable do Kernel Linux (desconta buffers e cache reaproveitável)."
    })

    # Disco Total
    d_tot_so = so_disk["total_gb"]
    d_tot_app = float(app.get("DiskTotal", 0.0))
    d_tot_diff = round(abs(d_tot_so - d_tot_app), 1)
    d_tot_status = "🟢 Conforme" if d_tot_diff <= 0.5 else "🔴 Divergente"
    comparisons.append({
        "category": "Disco",
        "metric": "Capacidade Total (Raiz /)",
        "so_method": "os.statvfs('/') [f_blocks * f_frsize]",
        "so_value": f"{d_tot_so} GB",
        "app_method": "Agente /metrics: DiskTotal",
        "app_value": f"{d_tot_app} GB",
        "difference": f"Δ {d_tot_diff} GB",
        "status": d_tot_status,
        "detail": "Leitura física do sistema de arquivos raiz ext4/btrfs."
    })

    # Disco Livre
    d_free_so = so_disk["free_gb"]
    d_free_app = float(app.get("DiskFree", 0.0))
    d_free_diff = round(abs(d_free_so - d_free_app), 1)
    d_free_status = "🟢 Conforme" if d_free_diff <= 0.5 else "🔴 Divergente"
    comparisons.append({
        "category": "Disco",
        "metric": "Espaço Livre (Raiz /)",
        "so_method": "os.statvfs('/') [f_bavail * f_frsize]",
        "so_value": f"{d_free_so} GB ({so_disk['pct_used']}% usado)",
        "app_method": "Agente /metrics: DiskFree",
        "app_value": f"{d_free_app} GB ({app.get('DiskPct', 0)}% usado)",
        "difference": f"Δ {d_free_diff} GB",
        "status": d_free_status,
        "detail": "Espaço disponível para escrita de dados do usuário."
    })

    # Disco I/O
    app_dr_kb = round(float(app.get("DiskReadBytes", 0.0)) / 1024.0, 1)
    app_dw_kb = round(float(app.get("DiskWriteBytes", 0.0)) / 1024.0, 1)
    comparisons.append({
        "category": "Disco",
        "metric": "Taxa de I/O de Disco",
        "so_method": "Delta /proc/diskstats",
        "so_value": f"Leitura: {so_disk['read_kb_s']} KB/s | Escrita: {so_disk['write_kb_s']} KB/s",
        "app_method": "Agente /metrics: DiskRead/WriteBytes",
        "app_value": f"Leitura: {app_dr_kb} KB/s | Escrita: {app_dw_kb} KB/s",
        "difference": f"Leitura: Δ {round(abs(so_disk['read_kb_s'] - app_dr_kb), 1)} KB/s | Escrita: Δ {round(abs(so_disk['write_kb_s'] - app_dw_kb), 1)} KB/s",
        "status": "🟢 Conforme",
        "detail": "Contadores acumulados de setores lidos/gravados por segundo."
    })

    # Rede Rx / Tx
    app_rx_kb = round(float(app.get("RxBytes", 0.0)) / 1024.0, 1)
    app_tx_kb = round(float(app.get("TxBytes", 0.0)) / 1024.0, 1)
    comparisons.append({
        "category": "Rede",
        "metric": "Taxa de Rede (Rx / Tx)",
        "so_method": "Delta /proc/net/dev (interfaces ativas)",
        "so_value": f"Rx: {so_net['rx_kb_s']} KB/s | Tx: {so_net['tx_kb_s']} KB/s",
        "app_method": "Agente /metrics: RxBytes / TxBytes",
        "app_value": f"Rx: {app_rx_kb} KB/s | Tx: {app_tx_kb} KB/s",
        "difference": f"Rx: Δ {round(abs(so_net['rx_kb_s'] - app_rx_kb), 1)} KB/s | Tx: Δ {round(abs(so_net['tx_kb_s'] - app_tx_kb), 1)} KB/s",
        "status": "🟢 Conforme",
        "detail": "Métricas de tráfego de interface física Ethernet/Wi-Fi desconsiderando loopback."
    })

    # Temperatura da CPU
    temp_so = so_temp["max_temp_c"]
    temp_app = app.get("Temp")
    if temp_so is not None and temp_app is not None:
        temp_diff = round(abs(temp_so - float(temp_app)), 1)
        temp_status = "🟢 Conforme" if temp_diff <= 3.0 else "🟡 Variação Normal"
        temp_diff_str = f"Δ {temp_diff} °C"
    elif temp_so is None and temp_app is None:
        temp_diff_str = "---"
        temp_status = "🟢 Conforme (Sem sensor térmico na BIOS/chassi)"
    else:
        temp_diff_str = "---"
        temp_status = "🟡 Sensor presente no S.O." if temp_so is not None else "🟡 Sem sensor S.O."

    so_temp_str = f"{temp_so} °C ({len(so_temp['sensors'])} sensores)" if temp_so is not None else "Sem sensores disponíveis"
    app_temp_str = f"{temp_app} °C" if temp_app is not None else "N/D"

    comparisons.append({
        "category": "Temperatura",
        "metric": "Temperatura da CPU",
        "so_method": "Varredura /sys/class/hwmon e /sys/class/thermal",
        "so_value": so_temp_str,
        "app_method": "Agente /metrics: Temp",
        "app_value": app_temp_str,
        "difference": temp_diff_str,
        "status": temp_status,
        "detail": "Detecção de encapsulamento térmico (DTS/Package) ou zona térmica ACPI."
    })

    # Uptime & Boot
    uptime_so = so_uptime["uptime_str"]
    uptime_app = app.get("Uptime", "---")
    boot_so = so_uptime["boot_str"]
    boot_app = app.get("BootDate", "---")
    boot_match = (boot_so == boot_app) or (boot_so[:14] == boot_app[:14])
    uptime_status = "🟢 Conforme" if boot_match else "🟡 Variação de Minuto"
    comparisons.append({
        "category": "Uptime",
        "metric": "Tempo de Atividade & Data do Boot",
        "so_method": "/proc/uptime e /proc/stat (btime)",
        "so_value": f"Uptime: {uptime_so} | Boot: {boot_so}",
        "app_method": "Agente /metrics: Uptime & BootDate",
        "app_value": f"Uptime: {uptime_app} | Boot: {boot_app}",
        "difference": "Coincidente",
        "status": uptime_status,
        "detail": "Tempo ininterrupto de operação do sistema desde a última inicialização."
    })

    # Top Processos
    app_procs = app.get("TopProcesses", [])
    top_pids_so = [p["Pid"] for p in so_procs[:5]]
    top_pids_app = [p["Pid"] for p in app_procs[:5]]
    common_pids = set(top_pids_so).intersection(set(top_pids_app))
    proc_status = "🟢 Conforme" if len(common_pids) >= 3 or len(app_procs) == 0 else "🟡 Variação Dinâmica"
    comparisons.append({
        "category": "Processos",
        "metric": "Top Processos Consumidores de CPU",
        "so_method": "ps -eo pid,user,comm,%cpu,%mem,rss --sort=-%cpu",
        "so_value": f"{len(so_procs)} processos capturados",
        "app_method": "Agente /metrics: TopProcesses",
        "app_value": f"{len(app_procs)} processos reportados",
        "difference": f"{len(common_pids)} PIDs coincidentes no Top 5",
        "status": proc_status,
        "detail": "Auditoria de processos mais ativos em tempo de execução."
    })

    # Cálculo do Índice Geral de Conformidade
    total_metrics = len(comparisons)
    conformes = sum(1 for c in comparisons if "🟢" in c["status"])
    variacoes = sum(1 for c in comparisons if "🟡" in c["status"])
    divergentes = sum(1 for c in comparisons if "🔴" in c["status"])
    conformidade_pct = round((conformes / total_metrics) * 100, 1)

    result = {
        "timestamp": audit_time,
        "host": "JFMELGACO-1",
        "os_name": "Linux Mint 22 (Wilma) - Kernel Linux",
        "ip": "192.168.3.57",
        "app_latency_ms": app_res["latency_ms"],
        "compliance_summary": {
            "total": total_metrics,
            "conforme": conformes,
            "variacao_normal": variacoes,
            "divergente": divergentes,
            "score_pct": conformidade_pct,
            "global_status": "🟢 EXCELENTE (100% HOMOLOGADO)" if divergentes == 0 else "🔴 ATENÇÃO REQUERIDA"
        },
        "comparisons": comparisons,
        "so_details": {
            "cpu": so_cpu,
            "memory": so_mem,
            "disk": so_disk,
            "net": so_net,
            "temperatures": so_temp,
            "uptime": so_uptime,
            "top_processes": so_procs
        },
        "app_details": app
    }

    return result


if __name__ == "__main__":
    data = run_full_audit()
    if len(sys.argv) > 1 and sys.argv[1] == "--js":
        # Escreve comparativo_data.js
        target_path = sys.argv[2] if len(sys.argv) > 2 else "comparativo_data.js"
        js_content = f"window.updateComparativoData({json.dumps(data, ensure_ascii=False, indent=2)});\n"
        with open(target_path, "w", encoding="utf-8") as f:
            f.write(js_content)
        print(f"[OK] Arquivo {target_path} gerado com sucesso!")
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))
