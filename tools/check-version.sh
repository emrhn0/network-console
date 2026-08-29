#!/usr/bin/env bash
# Surum numarasi uc ayri dosyada yaziyor. Biri unutulursa kullanici
# arayuzde yanlis surum gorur ya da kurulum yanlis etiketlenir. Bu betik
# ucunun de birbiriyle -ve verilirse etiketle- ayni oldugunu dogrular.
#
# Kullanim:  bash tools/check-version.sh [beklenen-surum]

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

agent=$(sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' ping-agent.py)
setup=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' setup.py)
plist=$(sed -n 's/.*<key>CFBundleShortVersionString<\/key><string>\(.*\)<\/string>.*/\1/p' macos/install.sh)

echo "  ping-agent.py APP_VERSION : ${agent:-YOK}"
echo "  setup.py      VERSION     : ${setup:-YOK}"
echo "  install.sh    plist       : ${plist:-YOK}"

fail=0
for v in "$agent" "$setup" "$plist"; do
  [ -n "$v" ] || { echo "HATA: surum satirlarindan biri bulunamadi."; exit 1; }
done

if [ "$agent" != "$setup" ] || [ "$agent" != "$plist" ]; then
  echo "HATA: surumler birbirini tutmuyor."
  fail=1
fi

if [ $# -ge 1 ] && [ -n "$1" ]; then
  if [ "$agent" != "$1" ]; then
    echo "HATA: etiket '$1' ile dosyalardaki '$agent' ayni degil."
    fail=1
  else
    echo "  etiket ile eslesiyor: $1"
  fi
fi

[ $fail -eq 0 ] || exit 1
echo "  surumler tutarli."
