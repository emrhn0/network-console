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


def port_free(port, retries=0, delay=0.3):
    # Guncelleme sirasinda eski surum az once kapatilmis olabilir; Windows
    # soketi bir sure TIME_WAIT'te tutar. Tercih edilen port icin kisa bir
    # sure yeniden denemek, gereksiz yere farklı bir porta (ve dolayisiyla
    # tarayicinin porta bagli localStorage'inda farklı bir kokene) dusmeyi
    # onler.
    for attempt in range(retries + 1):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            if attempt < retries:
                time.sleep(delay)
        finally:
            s.close()
    return False


def port_file():
    return os.path.join(HERE, "port.txt")


def load_preferred_port():
    try:
        with open(port_file(), "r", encoding="utf-8") as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def save_preferred_port(port):
    try:
        with open(port_file(), "w", encoding="utf-8") as f:
            f.write(str(port))
    except OSError:
        pass


def pick_port():
    # Onceki calistirmada kullanilan portu once dener - boylece tarayicinin
    # kaydettigi ayarlar (orn. VirusTotal anahtari, localStorage kokene/porta
    # bagli oldugu icin) surum guncellemelerinde de ayni adreste kalir.
    preferred = load_preferred_port()
    if preferred and probe_agent(preferred):
        return preferred, False
    for port in PORT_RANGE:
        if probe_agent(port):
            return port, False
    if preferred and preferred in PORT_RANGE and port_free(preferred, retries=8):
        return preferred, True
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


def agent_binary():
    """Derlenmis pakette ajan, yanimizda ayri bir calistirilabilir olarak gelir.
    Adi Windows'ta .exe uzantili, macOS/Linux'ta uzantisizdir."""
    return os.path.join(HERE, "NetworkConsole-Agent.exe" if WIN else "NetworkConsole-Agent")


def start_agent(port):
    agent_exe = agent_binary()
    if getattr(sys, "frozen", False) and os.path.isfile(agent_exe):
        cmd = [agent_exe, "--port", str(port)]
    else:
        # Kaynaktan calisirken ajani ayni yorumlayiciyla baslat.
        script = os.path.join(HERE, "ping-agent.py")
        cmd = [sys.executable, script, "--port", str(port)]
    kwargs = {}
    if WIN:
        kwargs["creationflags"] = NO_WINDOW
    return subprocess.Popen(cmd, **kwargs)


class Api:
    """window.pywebview.api uzerinden JS'e acilan kopru.
    Sadece bu app kabugundan (webview penceresi) cagrilabilir - duz
    tarayicidan sayfa acildiginda window.pywebview hic olusmaz."""

    def __init__(self, port):
        self.port = port

    def agent_status(self):
        return {"running": probe_agent(self.port)}

    def start_agent(self):
        if not probe_agent(self.port):
            start_agent(self.port)
            wait_ready(self.port, timeout=8)
        return {"running": probe_agent(self.port)}

    # VT anahtari icin ikinci bir kopya: tarayicinin localStorage'i porta
    # (kokene) bagli oldugu icin port kayarsa anahtar "kaybolur". Bu dosya
    # port'tan bagimsiz - sayfa acilista burayi da kontrol eder.
    def get_vt_key(self):
        try:
            with open(os.path.join(HERE, "user-vt-key.txt"), "r", encoding="utf-8") as f:
                return f.read().strip()
        except OSError:
            return ""

    def set_vt_key(self, value):
        try:
            with open(os.path.join(HERE, "user-vt-key.txt"), "w", encoding="utf-8") as f:
                f.write((value or "").strip())
        except OSError:
            pass
        return {"ok": True}


def main():
    port, need_start = pick_port()
    save_preferred_port(port)
    proc = None
    if need_start:
        proc = start_agent(port)
        wait_ready(port)

    # varsayilan olarak kapali - yoksa "Export" (CSV indirme) sessizce iptal edilir
    webview.settings["ALLOW_DOWNLOADS"] = True

    url = "http://127.0.0.1:%d/?platform=app" % port
    icon_path = os.path.join(HERE, "network-console-icon.ico")
    # Kenar cubugu 232px yer kapliyor; varsayilan pencere ona gore genis.
    # min_size, kenar cubugunun daralmis (76px) haline gore secildi.
    window = webview.create_window(
        "Network Console", url,
        width=1320, height=900, min_size=(900, 640),
        background_color="#08080D",
        js_api=Api(port),
    )
    webview.start(icon=icon_path if os.path.isfile(icon_path) else None)

    if proc:
        try:
            proc.terminate()
        except OSError:
            pass


if __name__ == "__main__":
    main()
