#!/usr/bin/env python3
"""
Network Console - yerel ajan (ping, traceroute, DNS, sertifika, HTTP, port kontrolu)

TEK KISI (varsayilan, sadece bu bilgisayar):
    python ping-agent.py
    -> http://localhost:8787

TUM AG (ekipteki herkes erisebilir):
    python ping-agent.py --lan
    -> http://<bu-makinenin-ip'si>:8787

Onemli: --lan modunda ping/port kontrolleri BU makineden cikar.
Ekiptekiler kendi bilgisayarlarindan degil, senin vantaj noktandan olcum yapar.

Secenekler:
    --lan               0.0.0.0'a baglanir, ozel ag araliklarina izin verir
    --bind 0.0.0.0      belirli bir arayuze baglar
    --allow 10.0.0.0/8,192.168.1.0/24   izinli kaynak agları (virgullu)
    --token GIZLI       istekler ?k=GIZLI ister (paylasilan sifre)
    --port 8787         dinlenen port
    --access-log        kim hangi hedefi sorgulamis, ekrana yazar
    --allow-remote-probe  uzak istemcilerin SENIN makinenden olcum yapmasina izin ver
                          (varsayilan: kapali - herkes kendi ajanini calistirmali)
                          DIKKAT: bunu acmak traceroute/dns/sertifika/http uclarini da
                          LAN'a acar - ajanin makinesi herhangi bir ic adrese istek
                          atabilen bir vekil (SSRF) haline gelir. Sadece guvendigin,
                          kapali bir agda ve bilerek ac.

Onemli (varsayilan, guvenli davranis):
    --lan modunda bile /api/* (health, ping, tcp, resolve, traceroute, dns,
    cert, http) sadece bu makineden (127.0.0.1) gelen isteklere acik.
    Sayfa (HTML) yine LAN'a acik kalir.
    Boylece web'den baglananlar SENIN ajanin uzerinden olcum YAPAMAZ; sayfa
    otomatik olarak kendi bilgisayarlarindaki 127.0.0.1:8787 ajanini arar.
    Herkes ayni ping-agent.py'yi (--lan OLMADAN) kendi makinesinde calistirirsa,
    olcum tam olarak kendi "ping" komutlariyla birebir ayni olur.
    Eski (paylasimli) davranisi geri istersen --allow-remote-probe kullan.

Bagimlilik yok, sadece Python 3 standart kutuphanesi. Windows'ta gorev
cubugu simgesi (pystray + Pillow) opsiyoneldir - kurulu degilse ajan
simgesiz calismaya devam eder; --no-tray ile de kapatilabilir.
"""

import argparse
import base64
import errno
import http.client
import ipaddress
import json
import os
import platform
import random
import re
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote, urlencode, urljoin, urlsplit

try:
    import pystray
    from PIL import Image
    TRAY_AVAILABLE = True
except ImportError:
    TRAY_AVAILABLE = False

WIN = platform.system().lower().startswith("win")
# macOS/BSD ile Linux'ta "ping -W" ayni bayrak, FARKLI birim:
#   Linux : -W <saniye>
#   BSD   : -W <milisaniye>
# Ayrimi yapmazsak BSD'de "-W 3" 3 milisaniye olur; 26 ms'lik bir hedef
# yanit verse bile ping onu gec sayip "time=" satirini hic basmaz ve
# olcum "yanit yok" gorunur. (traceroute -w her ikisinde de saniyedir.)
BSD = platform.system().lower() in ("darwin", "freebsd", "openbsd", "netbsd")
NO_WINDOW = 0x08000000 if WIN else 0

SAFE_HOST = re.compile(r"^[A-Za-z0-9._:\-\[\]]{1,255}$")
RE_TIME = re.compile(r"([=<])\s*([\d]+(?:[.,]\d+)?)\s*m?s\b", re.I)
RE_TTL = re.compile(r"\bTTL[=\s:]+(\d+)", re.I)

PRIVATE = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
           "127.0.0.0/8", "169.254.0.0/16", "::1/128", "fc00::/7", "fe80::/10"]

ALLOW_NETS = []          # bos = herkese acik
TOKEN = None
ACCESS_LOG = False
ALLOW_REMOTE_PROBE = False   # kapali = /api/ping,tcp,resolve sadece 127.0.0.1'den
GATE = threading.BoundedSemaphore(32)   # es zamanli olcum tavani
TRACE_GATE = threading.BoundedSemaphore(3)   # traceroute uzun surer, ayri tavan
VT_GATE = threading.BoundedSemaphore(2)   # VirusTotal kotasini korumak icin ayri, dar tavan
PING_SWEEP_POOL = 16   # sadece belgeleme amacli - gercek havuz tarayicida (JS)

# Uygulama surumu. Arayuz bunu /api/health'ten okuyup gosterir, boylece
# surum tek yerde tanimli kalir. setup.py ve macos/install.sh ile ayni
# olmali; CI her etiketde ucunun de etiketle esledigini dogrular.
APP_VERSION = "1.5.7"

PROBE_PATHS = ("/api/health", "/api/ping", "/api/tcp", "/api/resolve",
               "/api/traceroute", "/api/dns", "/api/cert", "/api/http", "/api/vtcheck",
               "/api/snmp", "/api/wol", "/api/ssh")

DNS_TYPES = {"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "PTR": 12, "MX": 15, "TXT": 16, "AAAA": 28}
DNS_TYPES_REV = {v: k for k, v in DNS_TYPES.items()}

APP_DIR = None   # main() icinde ayarlanir; vt anahtar dosyasi burada aranir

_dns_servers_cache = None
_vt_key_cache = None


def is_loopback(addr):
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.is_loopback


def log(*parts):
    if ACCESS_LOG:
        print("  %s  %s" % (datetime.now().strftime("%H:%M:%S"), "  ".join(str(p) for p in parts)))


def source_allowed(addr):
    if not ALLOW_NETS:
        return True
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return any(ip in net for net in ALLOW_NETS)


# -- ICMP ----------------------------------------------------------
def run_ping(host, timeout_ms=2000):
    if not SAFE_HOST.match(host or ""):
        return {"ok": False, "error": "gecersiz hedef"}

    host = host.strip("[]")
    if WIN:
        cmd = ["ping", "-n", "1", "-w", str(timeout_ms), host]
    elif BSD:
        # BSD/macOS: -W milisaniye alir
        cmd = ["ping", "-c", "1", "-W", str(max(1, int(timeout_ms))), host]
    else:
        # Linux: -W saniye alir
        secs = max(1, int(round(timeout_ms / 1000)))
        cmd = ["ping", "-c", "1", "-W", str(secs), host]

    if not GATE.acquire(timeout=5):
        return {"ok": False, "error": "ajan mesgul"}
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, errors="ignore",
                           timeout=timeout_ms / 1000 + 2, creationflags=NO_WINDOW)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "zaman asimi"}
    except FileNotFoundError:
        return {"ok": False, "error": "ping komutu bulunamadi"}
    finally:
        GATE.release()

    out = (p.stdout or "") + (p.stderr or "")
    m = RE_TIME.search(out)
    if not m:
        return {"ok": False, "error": "yanit yok"}

    ms = 0.5 if m.group(1) == "<" else float(m.group(2).replace(",", "."))
    ttl = RE_TTL.search(out)
    return {"ok": True, "ms": round(ms, 2), "ttl": int(ttl.group(1)) if ttl else None}


# -- TCP (telnet) --------------------------------------------------
def run_tcp(host, port, timeout_ms=2000):
    if not SAFE_HOST.match(host or ""):
        return {"ok": False, "state": "error", "error": "gecersiz hedef"}
    if not (1 <= port <= 65535):
        return {"ok": False, "state": "error", "error": "gecersiz port"}

    host = host.strip("[]")
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return {"ok": True, "state": "error", "error": "isim cozumlenemedi"}
    if not infos:
        return {"ok": True, "state": "error", "error": "adres bulunamadi"}

    if not GATE.acquire(timeout=5):
        return {"ok": False, "state": "error", "error": "ajan mesgul"}

    fam, stype, proto, _, sa = infos[0]
    s = socket.socket(fam, stype, proto)
    s.settimeout(timeout_ms / 1000)
    t0 = time.perf_counter()
    try:
        s.connect(sa)
        ms = (time.perf_counter() - t0) * 1000
        banner = None
        try:
            s.settimeout(0.7)
            data = s.recv(160)
            if data:
                banner = re.sub(r"[\r\n\t]+", " ", data.decode("utf-8", "ignore").strip())[:90]
        except Exception:
            pass
        return {"ok": True, "state": "open", "ms": round(ms, 2), "banner": banner, "ip": sa[0]}

    except socket.timeout:
        return {"ok": True, "state": "filtered", "ms": round((time.perf_counter() - t0) * 1000, 2), "ip": sa[0]}
    except ConnectionRefusedError:
        return {"ok": True, "state": "closed", "ms": round((time.perf_counter() - t0) * 1000, 2), "ip": sa[0]}
    except OSError as e:
        code = getattr(e, "errno", None)
        win = getattr(e, "winerror", None)
        if code == errno.ETIMEDOUT or win == 10060:
            return {"ok": True, "state": "filtered", "ip": sa[0]}
        if win == 10061:
            return {"ok": True, "state": "closed", "ip": sa[0]}
        return {"ok": True, "state": "error", "error": e.strerror or str(e), "ip": sa[0]}
    finally:
        try:
            s.close()
        except Exception:
            pass
        GATE.release()


# -- isim cozumleme (sistem resolver) ------------------------------
def run_resolve(host):
    if not SAFE_HOST.match(host or ""):
        return {"ok": False, "error": "gecersiz hedef"}

    host = host.strip("[]")
    ips, ipv6 = [], []
    try:
        for fam, _, _, _, sa in socket.getaddrinfo(host, None):
            if fam == socket.AF_INET and sa[0] not in ips:
                ips.append(sa[0])
            elif fam == socket.AF_INET6 and sa[0] not in ipv6:
                ipv6.append(sa[0])
    except socket.gaierror:
        return {"ok": False, "error": "cozumlenemedi"}

    ptr = None
    if ips:
        try:
            ptr = socket.gethostbyaddr(ips[0])[0]
        except Exception:
            ptr = None

    return {"ok": True, "ips": ips, "ipv6": ipv6, "ptr": ptr, "source": "system"}


# -- traceroute (MTR tarzi hop kesfi; surekli olcum tarayicida) ----
_MISS = object()


def parse_traceroute_line(line, expected_hop):
    m = re.match(r"^\s*(\d{1,3})\s+(.*)$", line)
    if not m or int(m.group(1)) != expected_hop:
        return _MISS
    ip = None
    for tok in re.split(r"[\s\[\]]+", m.group(2)):
        tok = tok.strip(",")
        if not tok:
            continue
        try:
            ipaddress.ip_address(tok)
            ip = tok
        except ValueError:
            continue
    return ip


def run_traceroute(host, maxhops=30, timeout_ms=1000):
    if not SAFE_HOST.match(host or ""):
        return {"ok": False, "error": "gecersiz hedef"}
    host = host.strip("[]")
    maxhops = max(1, min(maxhops, 64))
    timeout_ms = max(200, min(timeout_ms, 5000))

    if WIN:
        cmd = ["tracert", "-d", "-h", str(maxhops), "-w", str(timeout_ms), host]
    else:
        secs = max(1, int(round(timeout_ms / 1000)))
        cmd = ["traceroute", "-n", "-m", str(maxhops), "-w", str(secs), host]

    if not TRACE_GATE.acquire(timeout=5):
        return {"ok": False, "error": "ajan mesgul (traceroute)"}
    try:
        budget = maxhops * 3 * (timeout_ms / 1000) + 10
        p = subprocess.run(cmd, capture_output=True, text=True, errors="ignore",
                            timeout=budget, creationflags=NO_WINDOW)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "zaman asimi"}
    except FileNotFoundError:
        return {"ok": False, "error": "traceroute komutu bulunamadi"}
    finally:
        TRACE_GATE.release()

    out = (p.stdout or "") + (p.stderr or "")
    hops, expected = [], 1
    for line in out.splitlines():
        r = parse_traceroute_line(line, expected)
        if r is _MISS:
            continue
        hops.append({"n": expected, "ip": r})
        expected += 1
        if expected > maxhops:
            break

    target_ip = None
    tm = re.search(r"\[(\d{1,3}(?:\.\d{1,3}){3})\]", out)
    if tm:
        target_ip = tm.group(1)

    if not hops:
        return {"ok": False, "error": "hic hop bulunamadi"}
    return {"ok": True, "target_ip": target_ip, "hops": hops}


# -- DNS (ham UDP istemci, uclara bagimlilik yok) -------------------
def _dns_encode_name(name):
    name = (name or "").strip(".")
    try:
        name.encode("ascii")
    except UnicodeEncodeError:
        try:
            name = name.encode("idna").decode("ascii")
        except UnicodeError:
            pass
    out = b""
    for part in name.split("."):
        if not part:
            continue
        b = part.encode("ascii", "ignore")[:63]
        out += bytes([len(b)]) + b
    return out + b"\x00"


def _dns_decode_name(buf, offset, _depth=0):
    if _depth > 20:
        raise ValueError("dns isim cozumu cok derin")
    labels = []
    visited = set()
    pos = offset
    jumped_from = None
    total_len = 0
    while True:
        if pos >= len(buf):
            raise ValueError("dns tampon tasti")
        length = buf[pos]
        if length == 0:
            pos += 1
            break
        if (length & 0xC0) == 0xC0:
            if pos + 1 >= len(buf):
                raise ValueError("gecersiz isaretci")
            ptr = ((length & 0x3F) << 8) | buf[pos + 1]
            if ptr in visited:
                raise ValueError("dns isaretci dongusu")
            visited.add(ptr)
            if jumped_from is None:
                jumped_from = pos + 2
            pos = ptr
            continue
        pos += 1
        labels.append(buf[pos:pos + length].decode("ascii", "ignore"))
        pos += length
        total_len += length + 1
        if total_len > 255:
            raise ValueError("dns adi cok uzun")
    end = jumped_from if jumped_from is not None else pos
    return ".".join(labels), end


def _dns_build_query(name, qtype):
    txid = random.randint(0, 65535)
    flags = 0x0100  # RD=1
    header = struct.pack(">HHHHHH", txid, flags, 1, 0, 0, 1)  # ARCOUNT=1 (EDNS0)
    question = _dns_encode_name(name) + struct.pack(">HH", DNS_TYPES.get(qtype, 1), 1)
    # EDNS0 OPT sozde-kaydi: 4096 baytlik UDP yanit boyutu bildir, buyuk TXT/SOA
    # kayitlarinin klasik 512 bayt sinirinda kesilmesini (TC=1) onler.
    opt = b"\x00" + struct.pack(">HHIH", 41, 4096, 0, 0)
    return txid, header + question + opt


def _dns_parse_rr(buf, offset):
    name, offset = _dns_decode_name(buf, offset)
    if offset + 10 > len(buf):
        raise ValueError("kisa kayit")
    rtype, rclass, ttl, rdlen = struct.unpack(">HHIH", buf[offset:offset + 10])
    offset += 10
    rdata_start = offset
    tname = DNS_TYPES_REV.get(rtype, str(rtype))
    if tname == "A":
        data = socket.inet_ntoa(buf[rdata_start:rdata_start + 4])
    elif tname == "AAAA":
        data = socket.inet_ntop(socket.AF_INET6, buf[rdata_start:rdata_start + 16])
    elif tname in ("CNAME", "NS", "PTR"):
        data, _ = _dns_decode_name(buf, rdata_start)
    elif tname == "MX":
        pref = struct.unpack(">H", buf[rdata_start:rdata_start + 2])[0]
        exch, _ = _dns_decode_name(buf, rdata_start + 2)
        data = "%d %s" % (pref, exch)
    elif tname == "SOA":
        mname, p = _dns_decode_name(buf, rdata_start)
        rname, p = _dns_decode_name(buf, p)
        serial, refresh, retry, expire, minttl = struct.unpack(">IIIII", buf[p:p + 20])
        data = "%s %s %d %d %d %d %d" % (mname, rname, serial, refresh, retry, expire, minttl)
    elif tname == "TXT":
        chunks, p, end = [], rdata_start, rdata_start + rdlen
        while p < end:
            ln = buf[p]
            p += 1
            chunks.append(buf[p:p + ln].decode("utf-8", "ignore"))
            p += ln
        data = "".join(chunks)
    else:
        data = buf[rdata_start:rdata_start + rdlen].hex()
    return {"name": name, "type": tname, "ttl": ttl, "data": data}, rdata_start + rdlen


def run_dns(host, qtype, server, timeout_ms=3000):
    if not SAFE_HOST.match(host or ""):
        return {"ok": False, "error": "gecersiz hedef"}
    if qtype not in DNS_TYPES:
        return {"ok": False, "error": "gecersiz kayit turu"}
    if not server or not SAFE_HOST.match(server):
        return {"ok": False, "error": "gecersiz sunucu"}

    txid, query = _dns_build_query(host, qtype)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_ms / 1000)
    t0 = time.perf_counter()
    try:
        sock.sendto(query, (server, 53))
        while True:
            if time.perf_counter() - t0 > timeout_ms / 1000:
                return {"ok": False, "error": "zaman asimi"}
            try:
                data, addr = sock.recvfrom(4096)
            except socket.timeout:
                return {"ok": False, "error": "zaman asimi"}
            if addr[0] != server or len(data) < 12:
                continue
            if struct.unpack(">H", data[0:2])[0] != txid:
                continue
            break
    except OSError as e:
        return {"ok": False, "error": e.strerror or str(e)}
    finally:
        sock.close()

    flags, qdcount, ancount, nscount, arcount = struct.unpack(">HHHHH", data[2:12])
    rcode = flags & 0x000F
    truncated = bool(flags & 0x0200)
    if rcode == 3:
        return {"ok": True, "status": "nxdomain", "answers": [], "truncated": truncated}
    if rcode != 0:
        return {"ok": True, "status": "error", "rcode": rcode, "answers": [], "truncated": truncated}

    offset = 12
    try:
        for _ in range(qdcount):
            _, offset = _dns_decode_name(data, offset)
            offset += 4
        answers = []
        for _ in range(ancount):
            rr, offset = _dns_parse_rr(data, offset)
            answers.append(rr)
    except (ValueError, struct.error, IndexError):
        return {"ok": False, "error": "yanit ayristirilamadi"}

    return {"ok": True, "status": "ok", "answers": answers, "truncated": truncated}


def detect_dns_servers():
    global _dns_servers_cache
    if _dns_servers_cache is not None:
        return _dns_servers_cache
    found = []
    if WIN:
        import winreg
        roots = [r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"]
        try:
            base = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                   r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces")
            i = 0
            while True:
                try:
                    sub = winreg.EnumKey(base, i)
                except OSError:
                    break
                roots.append(r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\%s" % sub)
                i += 1
        except OSError:
            pass
        for path in roots:
            try:
                key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path)
            except OSError:
                continue
            for val_name in ("NameServer", "DhcpNameServer"):
                try:
                    val, _ = winreg.QueryValueEx(key, val_name)
                except OSError:
                    continue
                for s in re.split(r"[,\s]+", val or ""):
                    s = s.strip()
                    if s and s not in found:
                        found.append(s)
    else:
        try:
            with open("/etc/resolv.conf") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("nameserver"):
                        parts = line.split()
                        if len(parts) >= 2 and parts[1] not in found:
                            found.append(parts[1])
        except OSError:
            pass
    _dns_servers_cache = found
    return found


# -- sertifika -------------------------------------------------------
def run_cert(host, port=443, timeout_ms=3000):
    if not SAFE_HOST.match(host or ""):
        return {"ok": False, "error": "gecersiz hedef"}
    if not (1 <= port <= 65535):
        return {"ok": False, "error": "gecersiz port"}
    host = host.strip("[]")
    timeout = timeout_ms / 1000

    def handshake(ctx):
        with socket.create_connection((host, port), timeout=timeout) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ss:
                return ss.getpeercert(binary_form=True), ss.version(), ss.cipher()

    verified, chain_error = True, None
    if not GATE.acquire(timeout=5):
        return {"ok": False, "error": "ajan mesgul"}
    try:
        try:
            der, tls_version, cipher = handshake(ssl.create_default_context())
        except ssl.SSLCertVerificationError as e:
            verified = False
            chain_error = e.verify_message or str(e)
            der, tls_version, cipher = handshake(ssl._create_unverified_context())
    except (socket.timeout, ConnectionRefusedError, ssl.SSLError, OSError) as e:
        return {"ok": False, "error": getattr(e, "strerror", None) or str(e)}
    finally:
        GATE.release()

    result = {
        "ok": True, "verified": verified, "chain_error": chain_error,
        "tls_version": tls_version, "cipher": cipher[0] if cipher else None,
    }

    decoder = getattr(ssl._ssl, "_test_decode_cert", None)
    parsed = None
    if decoder and der:
        pem = ssl.DER_cert_to_PEM_cert(der)
        fd, path = tempfile.mkstemp(suffix=".pem")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(pem)
            parsed = decoder(path)
        except Exception:
            parsed = None
        finally:
            try:
                os.unlink(path)
            except OSError:
                pass

    if parsed:
        def cn(d):
            for rdn in d or ():
                for k, v in rdn:
                    if k == "commonName":
                        return v
            return None

        def field(d, key):
            for rdn in d or ():
                for k, v in rdn:
                    if k == key:
                        return v
            return None

        subject, issuer = parsed.get("subject"), parsed.get("issuer")
        not_before, not_after = parsed.get("notBefore"), parsed.get("notAfter")
        san = [v for k, v in parsed.get("subjectAltName", ()) if k == "DNS"]
        days_left = None
        if not_after:
            try:
                base = not_after.rsplit(" ", 1)[0]
                dt = datetime.strptime(base, "%b %d %H:%M:%S %Y")
                now = datetime.now(timezone.utc).replace(tzinfo=None)
                days_left = (dt - now).days
            except ValueError:
                days_left = None
        result.update({
            "subject_cn": cn(subject), "issuer_cn": cn(issuer), "issuer_o": field(issuer, "organizationName"),
            "not_before": not_before, "not_after": not_after, "days_left": days_left,
            "san": san, "detail": True,
        })
    else:
        result.update({"detail": False, "der_len": len(der) if der else 0})

    return result


# -- HTTP kontrolu (yonlendirme zinciri, TTFB, basliklar) -----------
def run_http(url, method="GET", timeout_ms=5000, max_redirects=10):
    timeout = timeout_ms / 1000
    visited = set()
    chain = []
    cur_url = url
    cur_method = (method or "GET").upper()
    if cur_method not in ("GET", "HEAD", "POST"):
        cur_method = "GET"
    total_t0 = time.perf_counter()
    budget = timeout * (max_redirects + 2)

    for _ in range(max_redirects + 1):
        if time.perf_counter() - total_t0 > budget:
            return {"ok": False, "error": "toplam zaman asimi", "chain": chain}

        parts = urlsplit(cur_url)
        if parts.scheme not in ("http", "https"):
            return {"ok": False, "error": "desteklenmeyen sema: " + (parts.scheme or "?"), "chain": chain}
        host = parts.hostname or ""
        if not SAFE_HOST.match(host):
            return {"ok": False, "error": "gecersiz hedef", "chain": chain}
        try:
            port = parts.port or (443 if parts.scheme == "https" else 80)
        except ValueError:
            return {"ok": False, "error": "gecersiz port", "chain": chain}
        if not (1 <= port <= 65535):
            return {"ok": False, "error": "gecersiz port", "chain": chain}
        path = parts.path or "/"
        if parts.query:
            path += "?" + parts.query

        if cur_url in visited:
            return {"ok": False, "error": "yonlendirme dongusu", "chain": chain}
        visited.add(cur_url)

        if not GATE.acquire(timeout=5):
            return {"ok": False, "error": "ajan mesgul", "chain": chain}
        t0 = time.perf_counter()
        try:
            if parts.scheme == "https":
                conn = http.client.HTTPSConnection(host, port, timeout=timeout,
                                                     context=ssl._create_unverified_context())
            else:
                conn = http.client.HTTPConnection(host, port, timeout=timeout)
            conn.putrequest(cur_method, path, skip_host=True, skip_accept_encoding=True)
            conn.putheader("Host", host)
            conn.putheader("User-Agent", "NetworkConsole-HTTP-Check/1.0")
            conn.putheader("Connection", "close")
            conn.endheaders()
            resp = conn.getresponse()
            ttfb_ms = round((time.perf_counter() - t0) * 1000, 2)
            resp_headers = {k: v for k, v in resp.getheaders()}
            status = resp.status
            location = resp_headers.get("Location") or resp_headers.get("location")
            conn.close()
        except (socket.timeout, ConnectionRefusedError, ssl.SSLError, OSError) as e:
            chain.append({"url": cur_url, "error": getattr(e, "strerror", None) or str(e)})
            return {"ok": False, "error": "baglanti hatasi", "chain": chain}
        finally:
            GATE.release()

        chain.append({"url": cur_url, "status": status, "ttfb_ms": ttfb_ms,
                       "headers": resp_headers, "location": location})

        if status not in (301, 302, 303, 307, 308) or not location:
            return {"ok": True, "chain": chain, "final_status": status,
                    "total_ms": round((time.perf_counter() - total_t0) * 1000, 2)}

        if status == 303:
            cur_method = "GET"
        cur_url = urljoin(cur_url, location)

    return {"ok": False, "error": "cok fazla yonlendirme", "chain": chain}


# -- VirusTotal URL kontrolu ------------------------------------------
VT_API_BASE = "https://www.virustotal.com/api/v3"


def load_vt_key():
    global _vt_key_cache
    if _vt_key_cache is not None:
        return _vt_key_cache
    key = ""
    if APP_DIR:
        for name in ("vt-key.txt", "vt_key.txt"):
            try:
                with open(os.path.join(APP_DIR, name), "r", encoding="utf-8") as f:
                    key = f.read().strip()
            except OSError:
                continue
            if key:
                break
    _vt_key_cache = key
    return key


def _vt_request(path, key, method="GET", data=None, timeout=10):
    body = None
    headers = {"x-apikey": key}
    if data is not None:
        body = urlencode(data).encode("ascii")
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(VT_API_BASE + path, data=body, headers=headers, method=method)
    # bazi yerel guvenlik yazilimlari (AV/proxy) HTTPS trafigini MITM ile inceler ve
    # eksik/gecersiz sertifika sunar (ornek: "Missing Authority Key Identifier").
    # bu durumda dogrulamasiz baglantiya dus - anahtar zaten o cihazdan geciyor.
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (ssl.SSLCertVerificationError, ssl.SSLError, urllib.error.URLError) as e:
        reason = getattr(e, "reason", e)
        if not isinstance(reason, (ssl.SSLCertVerificationError, ssl.SSLError)):
            raise
        with urllib.request.urlopen(req, timeout=timeout, context=ssl._create_unverified_context()) as resp:
            return json.loads(resp.read().decode("utf-8"))


def run_vtcheck(url, client_key=None):
    key = (client_key or "").strip() or load_vt_key()
    if not key:
        return {"ok": False, "error": "VirusTotal anahtari tanimli degil - uygulamada 'Aktive Et' ile kendi anahtarinizi ekleyin"}
    if not url or len(url) > 2048:
        return {"ok": False, "error": "gecersiz URL"}
    parts = urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        return {"ok": False, "error": "gecersiz URL"}

    url_id = base64.urlsafe_b64encode(url.encode("utf-8")).decode("ascii").rstrip("=")

    if not VT_GATE.acquire(timeout=5):
        return {"ok": False, "error": "ajan mesgul (VirusTotal)"}
    try:
        data = None
        try:
            data = _vt_request("/urls/" + url_id, key)
        except urllib.error.HTTPError as e:
            if e.code == 401:
                return {"ok": False, "error": "VirusTotal anahtari gecersiz"}
            if e.code == 429:
                return {"ok": False, "error": "VirusTotal kota asimi - biraz sonra tekrar dene"}
            if e.code != 404:
                return {"ok": False, "error": "VirusTotal hatasi (%d)" % e.code}
            # 404: bu URL daha once taranmamis - yeni analiz baslat
            try:
                sub = _vt_request("/urls", key, method="POST", data={"url": url})
            except urllib.error.HTTPError as e2:
                return {"ok": False, "error": "gonderim hatasi (%d)" % e2.code}
            analysis_id = (sub.get("data") or {}).get("id")
            if not analysis_id:
                return {"ok": False, "error": "analiz baslatilamadi"}
            completed = False
            for _ in range(6):
                time.sleep(2)
                try:
                    an = _vt_request("/analyses/" + analysis_id, key)
                except urllib.error.HTTPError:
                    continue
                if (an.get("data") or {}).get("attributes", {}).get("status") == "completed":
                    completed = True
                    break
            if not completed:
                return {"ok": False, "error": "tarama surüyor - birazdan tekrar dene"}
            try:
                data = _vt_request("/urls/" + url_id, key)
            except urllib.error.HTTPError as e3:
                return {"ok": False, "error": "rapor alinamadi (%d)" % e3.code}
        except urllib.error.URLError as e:
            return {"ok": False, "error": "VirusTotal'a ulasilamadi: %s" % (e.reason or e)}
        except (socket.timeout, TimeoutError):
            return {"ok": False, "error": "zaman asimi"}
    finally:
        VT_GATE.release()

    attrs = (data.get("data") or {}).get("attributes", {})
    stats = attrs.get("last_analysis_stats", {}) or {}
    last_ts = attrs.get("last_analysis_date")
    last_str = None
    if last_ts:
        try:
            last_str = datetime.fromtimestamp(last_ts, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        except (OSError, OverflowError, ValueError):
            last_str = None

    return {
        "ok": True,
        "malicious": stats.get("malicious", 0), "suspicious": stats.get("suspicious", 0),
        "harmless": stats.get("harmless", 0), "undetected": stats.get("undetected", 0),
        "reputation": attrs.get("reputation"), "categories": attrs.get("categories", {}) or {},
        "last_analysis_date": last_str, "final_url": attrs.get("url"),
    }


def run_ssh_probe(host, port=22, timeout_ms=3000):
    # Tam kimlik dogrulamali SSH oturumu acmiyoruz (paramiko/crypto gerekir,
    # diger araclarin hicbirinde kalici/karmasik bagimlilik yok) - bunun
    # yerine Telnet aracindaki gibi: baglan + sunucunun ilk banner satirini
    # oku (orn. "SSH-2.0-OpenSSH_9.6"), erisilebilirlik + surum bilgisi verir.
    if not host:
        return {"ok": False, "error": "gecersiz hedef"}
    start = time.time()
    try:
        sock = socket.create_connection((host, port), timeout=timeout_ms / 1000)
        sock.settimeout(timeout_ms / 1000)
        banner = b""
        try:
            while b"\n" not in banner and len(banner) < 256:
                chunk = sock.recv(256)
                if not chunk:
                    break
                banner += chunk
        except (socket.timeout, TimeoutError):
            pass
        ms = round((time.time() - start) * 1000)
        sock.close()
        text = banner.decode("utf-8", errors="replace").strip()
        return {"ok": True, "ms": ms, "banner": text, "is_ssh": text.startswith("SSH-")}
    except (socket.timeout, TimeoutError):
        return {"ok": False, "error": "zaman asimi"}
    except OSError as e:
        return {"ok": False, "error": str(e)}


def run_wol(mac, broadcast="255.255.255.255", port=9):
    mac_clean = re.sub(r"[^0-9A-Fa-f]", "", mac or "")
    if len(mac_clean) != 12:
        return {"ok": False, "error": "gecersiz MAC adresi"}
    try:
        mac_bytes = bytes.fromhex(mac_clean)
    except ValueError:
        return {"ok": False, "error": "gecersiz MAC adresi"}
    packet = b"\xff" * 6 + mac_bytes * 16
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(packet, (broadcast or "255.255.255.255", port))
        sock.close()
    except OSError as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "mac": ":".join(mac_clean[i:i + 2] for i in range(0, 12, 2)).upper()}


# -- SNMP (v1/v2c GET) - pysnmp gibi agir bagimliliklara girmeden, sadece
# birkac standart sistem OID'sini okumak icin minimal el yapimi BER
# kodlayici/cozucu. GetRequest-PDU (0xA0) gonderir, GetResponse (0xA2) okur.
def _snmp_ber_len(n):
    if n < 0x80:
        return bytes([n])
    b = []
    while n:
        b.insert(0, n & 0xFF)
        n >>= 8
    return bytes([0x80 | len(b)]) + bytes(b)


def _snmp_tlv(tag, value):
    return bytes([tag]) + _snmp_ber_len(len(value)) + value


def _snmp_int(n):
    if n == 0:
        body = b"\x00"
    else:
        nbytes = (n.bit_length() + 7) // 8 or 1
        body = n.to_bytes(nbytes, "big", signed=False)
        if body[0] & 0x80:
            body = b"\x00" + body
    return _snmp_tlv(0x02, body)


def _snmp_oid(oid_str):
    parts = [int(x) for x in oid_str.strip(".").split(".")]
    body = bytes([parts[0] * 40 + parts[1]])
    for p in parts[2:]:
        if p < 128:
            body += bytes([p])
        else:
            chunks = []
            while p:
                chunks.insert(0, p & 0x7F)
                p >>= 7
            for i in range(len(chunks) - 1):
                chunks[i] |= 0x80
            body += bytes(chunks)
    return _snmp_tlv(0x06, body)


def _snmp_build_get(community, oids, request_id=1, version=1):
    varbinds = b"".join(_snmp_tlv(0x30, _snmp_oid(o) + _snmp_tlv(0x05, b"")) for o in oids)
    pdu_body = _snmp_int(request_id) + _snmp_int(0) + _snmp_int(0) + _snmp_tlv(0x30, varbinds)
    pdu = _snmp_tlv(0xA0, pdu_body)
    message = _snmp_int(version) + _snmp_tlv(0x04, community.encode("utf-8")) + pdu
    return _snmp_tlv(0x30, message)


def _snmp_parse_tlv(data, pos):
    tag = data[pos]
    ln = data[pos + 1]
    pos += 2
    if ln & 0x80:
        nbytes = ln & 0x7F
        ln = int.from_bytes(data[pos:pos + nbytes], "big")
        pos += nbytes
    value = data[pos:pos + ln]
    return tag, value, pos + ln


def _snmp_decode_value(tag, value):
    if tag == 0x02:  # INTEGER
        return int.from_bytes(value, "big", signed=True) if value else 0
    if tag in (0x04, 0x40):  # OCTET STRING / IpAddress
        if tag == 0x40 and len(value) == 4:
            return ".".join(str(b) for b in value)
        try:
            return value.decode("utf-8")
        except UnicodeDecodeError:
            return value.decode("latin-1", errors="replace")
    if tag == 0x43:  # TimeTicks (1/100 s)
        n = int.from_bytes(value, "big", signed=False)
        secs = n // 100
        d, rem = divmod(secs, 86400)
        h, rem = divmod(rem, 3600)
        m, s = divmod(rem, 60)
        parts = ([f"{d}g"] if d else []) + [f"{h:02d}:{m:02d}:{s:02d}"]
        return " ".join(parts)
    if tag in (0x41, 0x42, 0x46):  # Counter32 / Gauge32 / Counter64
        return int.from_bytes(value, "big", signed=False)
    if tag == 0x05:  # NULL
        return None
    return value.hex()


def run_snmp(host, community="public", timeout_ms=2000, port=161):
    oids = {
        "sysDescr": "1.3.6.1.2.1.1.1.0",
        "sysUpTime": "1.3.6.1.2.1.1.3.0",
        "sysName": "1.3.6.1.2.1.1.5.0",
        "sysContact": "1.3.6.1.2.1.1.4.0",
        "sysLocation": "1.3.6.1.2.1.1.6.0",
    }
    if not host:
        return {"ok": False, "error": "gecersiz hedef"}
    request = _snmp_build_get(community or "public", list(oids.values()))
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout_ms / 1000)
        sock.sendto(request, (host, port))
        data, _ = sock.recvfrom(4096)
        sock.close()
    except socket.timeout:
        return {"ok": False, "error": "zaman asimi - cihaz SNMP'ye yanit vermiyor (community adi yanlis olabilir)"}
    except OSError as e:
        return {"ok": False, "error": str(e)}

    try:
        _, msg, _ = _snmp_parse_tlv(data, 0)
        pos = 0
        _, _, pos = _snmp_parse_tlv(msg, pos)  # version
        _, _, pos = _snmp_parse_tlv(msg, pos)  # community
        pdu_tag, pdu_body, _ = _snmp_parse_tlv(msg, pos)
        if pdu_tag != 0xA2:
            return {"ok": False, "error": "beklenmeyen SNMP yaniti"}
        p = 0
        _, _, p = _snmp_parse_tlv(pdu_body, p)  # request-id
        _, err_status_raw, p = _snmp_parse_tlv(pdu_body, p)
        err_status = _snmp_decode_value(0x02, err_status_raw)
        _, _, p = _snmp_parse_tlv(pdu_body, p)  # error-index
        vbl_tag, vbl_body, p = _snmp_parse_tlv(pdu_body, p)
        if err_status:
            return {"ok": False, "error": "SNMP hatasi (kod %s) - community adi veya OID destegi olmayabilir" % err_status}
        values = []
        vp = 0
        while vp < len(vbl_body):
            vb_tag, vb_body, vp = _snmp_parse_tlv(vbl_body, vp)
            ip = 0
            _, _, ip = _snmp_parse_tlv(vb_body, ip)  # oid (atlanir, sira ile eslesir)
            val_tag, val_raw, ip = _snmp_parse_tlv(vb_body, ip)
            values.append(_snmp_decode_value(val_tag, val_raw))
        result = {"ok": True}
        for key, val in zip(oids.keys(), values):
            result[key] = val
        return result
    except (IndexError, ValueError) as e:
        return {"ok": False, "error": "SNMP yaniti cozumlenemedi: %s" % e}


# -- HTTP sunucu ------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "NetworkConsole/4.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        peer = self.client_address[0]
        if not source_allowed(peer):
            log("RED", peer, "izinli ag disi")
            return self._json({"ok": False, "error": "bu agdan erisim yok"}, 403)

        u = urlparse(self.path)
        q = parse_qs(u.query)
        path = u.path.rstrip("/") or "/"

        def arg(name, default=""):
            return unquote((q.get(name) or [default])[0])

        def num(name, default, lo, hi):
            try:
                return max(lo, min(int(arg(name, str(default))), hi))
            except ValueError:
                return default

        if TOKEN and path.startswith("/api/"):
            given = arg("k") or self.headers.get("X-Agent-Token", "")
            if given != TOKEN:
                return self._json({"ok": False, "error": "anahtar gecersiz"}, 401)

        if path in PROBE_PATHS and not ALLOW_REMOTE_PROBE and not is_loopback(peer):
            log("RED", peer, path, "uzak olcum kapali")
            return self._json({
                "ok": False,
                "error": "uzak olcum kapali - kendi bilgisayarinda ping-agent.py calistir (127.0.0.1:8787)"
            }, 403)

        if path == "/api/health":
            return self._json({
                "agent": "ping-konsolu", "version": 5,
                "app_version": APP_VERSION,
                "host": socket.gethostname(),
                "os": platform.system() + " " + platform.release(),
                "dns_servers": detect_dns_servers(),
            })

        if path == "/api/ping":
            host = arg("host")
            r = run_ping(host, num("timeout", 2000, 200, 10000))
            log(peer, "ping", host, r.get("ms", r.get("error")))
            return self._json(r)

        if path == "/api/tcp":
            host = arg("host")
            try:
                port = int(arg("port", "0"))
            except ValueError:
                port = 0
            r = run_tcp(host, port, num("timeout", 2000, 200, 10000))
            log(peer, "tcp", "%s:%s" % (host, port), r.get("state"))
            return self._json(r)

        if path == "/api/resolve":
            return self._json(run_resolve(arg("host")))

        if path == "/api/traceroute":
            host = arg("host")
            r = run_traceroute(host, num("maxhops", 30, 1, 64), num("timeout", 1000, 200, 5000))
            log(peer, "traceroute", host, r.get("error", "ok"))
            return self._json(r)

        if path == "/api/dns":
            host = arg("host")
            qtype = arg("type", "A").upper()
            explicit_server = arg("server")
            timeout_ms = num("timeout", 3000, 500, 8000)
            # Kullanici bir sunucu belirtmediyse "auto": sistemin ilk tespit
            # ettigi DNS sunucusu yanit vermiyorsa (orn. bagli olmayan bir
            # VPN/hotspot adaptorunun eski adresi) sessizce takilip kalmak
            # yerine sirayla bir kac tanesini daha dener.
            servers = [explicit_server] if explicit_server else (detect_dns_servers() or [""])
            # Otomatik modda birden fazla aday denenecegi icin sunucu basina
            # sureyi kisaltiyoruz (yoksa 8-10 olu adres * tam sure = cok uzun
            # surer); tek/acik sunucu secildiyse kullanicinin verdigi tam
            # sureyi kullaniriz.
            per_try = timeout_ms if explicit_server else min(timeout_ms, 1500)
            r = {"ok": False, "error": "gecersiz hedef"}
            tried = None
            for srv in servers[:8]:
                tried = srv
                r = run_dns(host, qtype, srv, per_try)
                if r.get("ok"):
                    break
            log(peer, "dns", qtype, host, "@" + (tried or "?"), r.get("status", r.get("error")))
            return self._json(r)

        if path == "/api/cert":
            host = arg("host")
            port = num("port", 443, 1, 65535)
            r = run_cert(host, port, num("timeout", 3000, 500, 10000))
            log(peer, "cert", host, port, r.get("days_left", r.get("error")))
            return self._json(r)

        if path == "/api/http":
            url = arg("url")
            method = arg("method", "GET")
            r = run_http(url, method, num("timeout", 5000, 500, 15000), num("redirects", 10, 0, 20))
            log(peer, "http", method, url, r.get("final_status", r.get("error")))
            return self._json(r)

        if path == "/api/vtcheck":
            url = arg("url")
            client_key = self.headers.get("X-VT-Key", "").strip()
            r = run_vtcheck(url, client_key)
            log(peer, "vtcheck", url, r.get("malicious", r.get("error")))
            return self._json(r)

        if path == "/api/shutdown":
            # UI, kendi bekledigi minimum surumden eski bir ajan surecini
            # (orn. bir onceki kurulumdan kalip arka planda calisan) tespit
            # edince buraya cagirir - taze bir surec baslatabilmek icin
            # yanit dondurdukten hemen sonra kendini kapatir.
            log(peer, "shutdown istendi")
            threading.Timer(0.2, lambda: os._exit(0)).start()
            return self._json({"ok": True})

        if path == "/api/ssh":
            host = arg("host")
            r = run_ssh_probe(host, num("port", 22, 1, 65535), num("timeout", 3000, 500, 10000))
            log(peer, "ssh", host, r.get("banner", r.get("error")))
            return self._json(r)

        if path == "/api/snmp":
            host = arg("host")
            community = arg("community", "public")
            r = run_snmp(host, community, num("timeout", 2000, 500, 8000), num("port", 161, 1, 65535))
            log(peer, "snmp", host, r.get("sysName", r.get("error")))
            return self._json(r)

        if path == "/api/wol":
            mac = arg("mac")
            broadcast = arg("broadcast", "255.255.255.255")
            r = run_wol(mac, broadcast, num("port", 9, 1, 65535))
            log(peer, "wol", mac, r.get("ok"))
            return self._json(r)

        if path.startswith("/api/"):
            return self._json({"ok": False, "error": "not found"}, 404)

        # v2 (Flutter) hicbir sayfa istemez, sadece /api/* JSON cagirir - eski
        # pywebview/HTML kabugunun SPA fallback + PWA manifest/ikon uclari bu
        # dalda kullanilmiyordu, kaldirildi. Taninmayan bir yol/tarayici
        # ziyareti icin kisa bir durum metni yeterli.
        msg = b"Network Console agent is running. This endpoint serves /api/* only."
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(msg)))
        self.end_headers()
        self.wfile.write(msg)


def local_ips():
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except Exception:
        pass
    return sorted(i for i in ips if not i.startswith("127."))


def _tray_icon_image(app_dir):
    for name in ("network-console-icon.ico", "network-console-icon.png"):
        p = os.path.join(app_dir, name)
        if os.path.isfile(p):
            try:
                return Image.open(p)
            except (OSError, ValueError):
                continue
    return Image.new("RGB", (64, 64), "#1E8E5A")


def run_with_tray(srv, port, app_dir):
    """Sunucuyu arka planda calistirir, gorev cubugu bildirim alaninda simge gosterir.
    Simge baslatilamazsa (orn. masaustu oturumu yok) sunucu yine de calismaya devam eder."""
    server_thread = threading.Thread(target=srv.serve_forever, daemon=True)
    server_thread.start()

    def do_open(icon, item):
        """'Network Console' penceresi aciksa one getirir; degilse app kabugunu
        baslatir. Ikisi de yoksa (kaynaktan calisirken ya da Windows disinda)
        sayfayi tarayicida acar."""
        if WIN:
            try:
                import ctypes
                user32 = ctypes.windll.user32
                hwnd = user32.FindWindowW(None, "Network Console")
                if hwnd:
                    user32.ShowWindow(hwnd, 9)  # SW_RESTORE (simge durumundaysa geri getir)
                    user32.SetForegroundWindow(hwnd)
                    return
            except Exception:
                pass
            # "NetworkConsole.exe" eski pywebview kabugu, "network_console_app.exe"
            # yeni Flutter uygulamasi - hangisi bu klasordeyse onu baslat.
            for name in ("NetworkConsole.exe", "network_console_app.exe"):
                exe = os.path.join(app_dir, name)
                if os.path.isfile(exe):
                    try:
                        subprocess.Popen([exe])
                        return
                    except OSError:
                        continue
        webbrowser.open("http://127.0.0.1:%d/?platform=app" % port)

    def do_quit(icon, item):
        icon.stop()
        srv.shutdown()
        os._exit(0)  # tum surecin (arka plan thread'leri dahil) kesin kapanmasini garantiler

    menu = pystray.Menu(
        pystray.MenuItem("Network Console Agent — port %d" % port, None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Sayfayi ac", do_open, default=True),
        pystray.MenuItem("Kapat", do_quit),
    )
    icon = pystray.Icon("network-console-agent", _tray_icon_image(app_dir),
                         "Network Console Agent calisiyor", menu)
    try:
        icon.run()
    except Exception as e:
        print("  Simge baslatilamadi (%s), ajan simgesiz calismaya devam ediyor." % e)
        try:
            while server_thread.is_alive():
                server_thread.join(1)
        except KeyboardInterrupt:
            srv.shutdown()


def main():
    global ALLOW_NETS, TOKEN, ACCESS_LOG, ALLOW_REMOTE_PROBE, APP_DIR

    # Pencere gostermeyen (--windowed) derlenmis exe'de sys.stdout/stderr None
    # olur; print() bu durumda cokerdi. Yerine bir log dosyasina yaz.
    if getattr(sys, "frozen", False) and sys.stdout is None:
        log_path = os.path.join(os.path.dirname(sys.executable), "network-console-agent.log")
        try:
            log_file = open(log_path, "a", buffering=1, encoding="utf-8")
        except OSError:
            import io
            log_file = io.StringIO()
        sys.stdout = log_file
        sys.stderr = log_file

    here = (os.path.dirname(sys.executable) if getattr(sys, "frozen", False)
            else os.path.dirname(os.path.abspath(__file__)))
    APP_DIR = here
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--bind", default=None)
    ap.add_argument("--lan", action="store_true")
    ap.add_argument("--allow", default=None)
    ap.add_argument("--token", default=None)
    ap.add_argument("--access-log", action="store_true")
    ap.add_argument("--allow-remote-probe", action="store_true")
    ap.add_argument("--vt-key", default=None, help="VirusTotal API anahtari (yoksa vt-key.txt dosyasindan okunur)")
    ap.add_argument("--no-tray", action="store_true", help="gorev cubugu simgesini gosterme")
    a = ap.parse_args()

    TOKEN = a.token
    ACCESS_LOG = a.access_log
    if a.vt_key:
        global _vt_key_cache
        _vt_key_cache = a.vt_key.strip()
    ALLOW_REMOTE_PROBE = a.allow_remote_probe
    bind = a.bind or ("0.0.0.0" if a.lan else "127.0.0.1")

    nets = a.allow.split(",") if a.allow else (PRIVATE if bind != "127.0.0.1" else [])
    for n in nets:
        n = n.strip()
        if not n:
            continue
        try:
            ALLOW_NETS.append(ipaddress.ip_network(n, strict=False))
        except ValueError:
            print("  UYARI: gecersiz ag atlandi: %s" % n)

    srv = ThreadingHTTPServer((bind, a.port), Handler)
    srv.daemon_threads = True

    print("")
    print("  Network Console ajani calisiyor")
    print("  Makine   : %s  (%s %s)" % (socket.gethostname(), platform.system(), platform.release()))
    print("  Dinlenen : %s:%d" % (bind, a.port))
    if bind == "127.0.0.1":
        print("  Adres    : http://localhost:%d" % a.port)
        print("  Not      : sadece bu bilgisayar. Ag icin --lan ile baslat.")
    else:
        for ip in local_ips():
            print("  Adres    : http://%s:%d%s" % (ip, a.port, ("?k=" + TOKEN) if TOKEN else ""))
        print("  Izinli   : %s" % (", ".join(str(n) for n in ALLOW_NETS) or "herkes"))
        print("  Anahtar  : %s" % (TOKEN if TOKEN else "yok"))
        if ALLOW_REMOTE_PROBE:
            print("  Uzak olcum : ACIK - tum LAN olcumleri bu makineden cikar.")
        else:
            print("  Uzak olcum : KAPALI - sayfa LAN'a acik ama olcumler sadece bu")
            print("               makineden (127.0.0.1) yapilabilir. Diger kullanicilar")
            print("               kendi bilgisayarlarinda ayni scripti calistirmali:")
            print("               python ping-agent.py")
    print("  VirusTotal : %s" % ("ayarli" if load_vt_key() else "ayarli degil (vt-key.txt ekleyin ya da --vt-key kullanin)"))

    use_tray = WIN and TRAY_AVAILABLE and not a.no_tray
    if use_tray:
        print("  Gorev cubugu simgesinden kapatabilirsiniz.")
        print("")
        run_with_tray(srv, a.port, here)
        return

    print("  Durdurmak icin Ctrl+C")
    print("")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n  Kapatiliyor.")
        srv.shutdown()


if __name__ == "__main__":
    main()
