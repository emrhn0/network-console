#!/usr/bin/env python3
"""
Network Console - masaustu uygulamasi (gercek native pencere)

Edge/Chrome kullanmaz - pywebview (Windows'ta WebView2 motoru) ile
bagimsiz bir uygulama penceresi acar. Gorev cubugunda ve Alt+Tab'de
kendi ikonumuz gorunur, "Edge" gorunmez; cunku calisan surec artik
tarayici degil, bizim kendi derlenmis exe'miz.

Yerel ajani (NetworkConsole-Agent.exe) arka planda baslatir (zaten
calisiyorsa yenisini baslatmaz). Pencere kapatilinca, ajani SADECE
kendisi baslattiysa durdurur.

Bagimlilik: pywebview (+ Windows'ta WebView2 Runtime, cogu Win10/11'de
zaten kurulu).
"""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import webview

WIN = sys.platform.startswith("win")
HERE = (os.path.dirname(sys.executable) if getattr(sys, "frozen", False)
        else os.path.dirname(os.path.abspath(__file__)))
PORT_RANGE = range(8787, 8797)
NO_WINDOW = 0x08000000 if WIN else 0


def probe_agent(port, timeout=0.6):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/api/health" % port, timeout=timeout) as r:
            data = json.loads(r.read().decode("utf-8"))
            return data.get("agent") == "ping-konsolu"
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        return False


def port_free(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def pick_port():
    for port in PORT_RANGE:
        if probe_agent(port):
            return port, False
    for port in PORT_RANGE:
        if port_free(port):
            return port, True
    return PORT_RANGE[0], True


def wait_ready(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if probe_agent(port, timeout=1):
            return True
        time.sleep(0.25)
    return False


def start_agent(port):
    agent_exe = os.path.join(HERE, "NetworkConsole-Agent.exe")
    if getattr(sys, "frozen", False) and os.path.isfile(agent_exe):
        cmd = [agent_exe, "--port", str(port)]
    else:
        script = os.path.join(HERE, "ping-agent.py")
        cmd = [sys.executable, script, "--port", str(port)]
    kwargs = {}
    if WIN:
        kwargs["creationflags"] = NO_WINDOW
    return subprocess.Popen(cmd, **kwargs)


def main():
    port, need_start = pick_port()
    proc = None
    if need_start:
        proc = start_agent(port)
        wait_ready(port)

    url = "http://127.0.0.1:%d/?platform=app" % port
    icon_path = os.path.join(HERE, "network-console-icon.ico")
    # Kenar cubugu 232px yer kapliyor; varsayilan pencere ona gore genis.
    # min_size, kenar cubugunun daralmis (76px) haline gore secildi.
    window = webview.create_window(
        "Network Console", url,
        width=1320, height=900, min_size=(900, 640),
        background_color="#08080D",
    )
    webview.start(icon=icon_path if os.path.isfile(icon_path) else None)

    if proc:
        try:
            proc.terminate()
        except OSError:
            pass


if __name__ == "__main__":
    main()
