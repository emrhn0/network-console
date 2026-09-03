# Network Console

Native desktop network diagnostics toolkit, built with Flutter: ping, traceroute, DNS, TLS
certificates, HTTP checks, port/IP scanning, subnet math, VirusTotal URL reputation, plus
SSH/SNMP probes and Wake-on-LAN — all in one console.

The UI (`flutter_app/`) talks to a small local measurement agent (`ping-agent.py`) over
plain HTTP on `127.0.0.1`.

- Latest release (installer + portable zip, Windows and macOS): see [Releases](../../releases/latest).
- Source: [`flutter_app/`](flutter_app) (UI) + [`ping-agent.py`](ping-agent.py) (backend agent).
