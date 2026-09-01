#!/usr/bin/env python3
"""
Network Console - Setup

Uygulamayi ve yerel ajani bu bilgisayara kurar. Yonetici hakki GEREKMEZ
(kullanici profiline kurulur, VSCode/Discord gibi). Web'e/tarayiciya hic
girmez - dogrudan masaustu + Baslat Menusu kisayollari olusturur.

Bagimlilik yok, sadece Python 3 standart kutuphanesi.
"""

import ctypes
import os
import subprocess
import sys
import time
import winreg

APP_NAME = "Network Console"
VERSION = "1.5.3"
PUBLISHER = "Network Console"
INSTALL_DIR = os.path.join(os.environ["LOCALAPPDATA"], "Programs", "NetworkConsole")
PAYLOAD = ("NetworkConsole.exe", "NetworkConsole-Agent.exe", "ag-konsolu.html", "network-console-icon.ico")
NO_WINDOW = 0x08000000

UNINSTALL_KEY = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\NetworkConsole"


def bundle_dir():
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return sys._MEIPASS
    return os.path.dirname(os.path.abspath(__file__))


def say(msg):
    print("  " + msg)
    sys.stdout.flush()


def ps(script, wait=True):
    args = ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script]
    if wait:
        subprocess.run(args, creationflags=NO_WINDOW, capture_output=True)
    else:
        subprocess.Popen(args, creationflags=NO_WINDOW)


def kill_running():
    for exe in ("NetworkConsole.exe", "NetworkConsole-Agent.exe"):
        subprocess.run(["taskkill", "/IM", exe, "/F"], creationflags=NO_WINDOW, capture_output=True)
    time.sleep(0.4)


def copy_payload():
    os.makedirs(INSTALL_DIR, exist_ok=True)
    src = bundle_dir()
    for name in PAYLOAD:
        s = os.path.join(src, name)
        d = os.path.join(INSTALL_DIR, name)
        with open(s, "rb") as f_in, open(d, "wb") as f_out:
            f_out.write(f_in.read())


def make_shortcut(lnk_path, target, workdir, icon, description=""):
    script = (
        '$W = New-Object -ComObject WScript.Shell; '
        '$S = $W.CreateShortcut("{lnk}"); '
        '$S.TargetPath = "{target}"; '
        '$S.WorkingDirectory = "{workdir}"; '
        '$S.IconLocation = "{icon}"; '
        '$S.Description = "{desc}"; '
        '$S.Save()'
    ).format(lnk=lnk_path, target=target, workdir=workdir, icon=icon, desc=description)
    ps(script)


def create_shortcuts():
    exe = os.path.join(INSTALL_DIR, "NetworkConsole.exe")
    agent = os.path.join(INSTALL_DIR, "NetworkConsole-Agent.exe")
    icon = os.path.join(INSTALL_DIR, "network-console-icon.ico")

    desktop = os.path.join(os.environ["USERPROFILE"], "Desktop", "Network Console.lnk")
    make_shortcut(desktop, exe, INSTALL_DIR, icon, "Network Console")

    start_menu_dir = os.path.join(os.environ["APPDATA"], r"Microsoft\Windows\Start Menu\Programs")
    start_menu = os.path.join(start_menu_dir, "Network Console.lnk")
    make_shortcut(start_menu, exe, INSTALL_DIR, icon, "Network Console")

    startup_dir = os.path.join(os.environ["APPDATA"], r"Microsoft\Windows\Start Menu\Programs\Startup")
    startup = os.path.join(startup_dir, "NetworkConsole-Agent.lnk")
    make_shortcut(startup, agent, INSTALL_DIR, icon, "Network Console ajanini sessizce baslatir")


def write_uninstaller():
    path = os.path.join(INSTALL_DIR, "uninstall.ps1")
    script = '''# Network Console - kaldirma
taskkill /IM NetworkConsole.exe /F 2>$null | Out-Null
taskkill /IM NetworkConsole-Agent.exe /F 2>$null | Out-Null
Start-Sleep -Milliseconds 400

$desktop = Join-Path $env:USERPROFILE "Desktop\\Network Console.lnk"
$startmenu = Join-Path $env:APPDATA "Microsoft\\Windows\\Start Menu\\Programs\\Network Console.lnk"
$startup = Join-Path $env:APPDATA "Microsoft\\Windows\\Start Menu\\Programs\\Startup\\NetworkConsole-Agent.lnk"
Remove-Item -Force -ErrorAction SilentlyContinue $desktop, $startmenu, $startup

Remove-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\NetworkConsole" -Recurse -ErrorAction SilentlyContinue

$installDir = "''' + INSTALL_DIR.replace("\\", "\\\\") + '''"
Start-Sleep -Milliseconds 300
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $installDir
'''
    with open(path, "w", encoding="utf-8") as f:
        f.write(script)
    return path


def register_uninstall(uninstall_ps1):
    icon = os.path.join(INSTALL_DIR, "network-console-icon.ico")
    uninstall_cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s"' % uninstall_ps1
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, UNINSTALL_KEY) as k:
        winreg.SetValueEx(k, "DisplayName", 0, winreg.REG_SZ, APP_NAME)
        winreg.SetValueEx(k, "DisplayVersion", 0, winreg.REG_SZ, VERSION)
        winreg.SetValueEx(k, "Publisher", 0, winreg.REG_SZ, PUBLISHER)
        winreg.SetValueEx(k, "InstallLocation", 0, winreg.REG_SZ, INSTALL_DIR)
        winreg.SetValueEx(k, "DisplayIcon", 0, winreg.REG_SZ, icon)
        winreg.SetValueEx(k, "UninstallString", 0, winreg.REG_SZ, uninstall_cmd)
        winreg.SetValueEx(k, "NoModify", 0, winreg.REG_DWORD, 1)
        winreg.SetValueEx(k, "NoRepair", 0, winreg.REG_DWORD, 1)
        winreg.SetValueEx(k, "EstimatedSize", 0, winreg.REG_DWORD, 20000)


def start_agent_now():
    agent = os.path.join(INSTALL_DIR, "NetworkConsole-Agent.exe")
    try:
        subprocess.Popen([agent], creationflags=NO_WINDOW)
        return True
    except OSError as e:
        say("      (simdi baslatilamadi: %s)" % e)
        say("      Masaustundeki kisayola tikladiginizda baslayacak.")
        return False


def main():
    print("")
    print("  Network Console %s - Kurulum" % VERSION)
    print("  " + "-" * 40)

    say("[1/6] Onceki surumler kapatiliyor...")
    kill_running()

    say("[2/6] Dosyalar kopyalaniyor -> %s" % INSTALL_DIR)
    copy_payload()

    say("[3/6] Kisayollar olusturuluyor (Masaustu, Baslat Menusu)...")
    create_shortcuts()

    say("[4/6] Ajan oturum acilisinda otomatik baslayacak sekilde ayarlaniyor...")
    # (create_shortcuts zaten Startup kisayolunu olusturdu)

    say("[5/6] Kaldirma kaydi olusturuluyor (Denetim Masasi > Program Ekle/Kaldir)...")
    uninstall_ps1 = write_uninstaller()
    register_uninstall(uninstall_ps1)

    say("[6/6] Ajan simdi baslatiliyor...")
    start_agent_now()

    print("")
    print("  Kurulum tamamlandi.")
    print("  Masaustunde ve Baslat Menusunde 'Network Console' kisayolunu bulabilirsiniz.")
    print("  Kaldirmak icin: Ayarlar > Uygulamalar > Network Console > Kaldir.")
    print("")
    try:
        input("  Kapatmak icin Enter'a basin...")
    except EOFError:
        pass


if __name__ == "__main__":
    if not sys.platform.startswith("win"):
        print("Bu kurulum sadece Windows icindir.")
        sys.exit(1)
    try:
        main()
    except Exception as e:
        print("")
        print("  Kurulum sirasinda bir hata olustu: %s" % e)
        try:
            input("  Kapatmak icin Enter'a basin...")
        except EOFError:
            pass
        sys.exit(1)
