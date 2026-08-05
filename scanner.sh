#!/usr/bin/env bash

SCANNER="docker run --rm realitlscanner"

ADDR="$1"
THREADS="${2:-100}"
TIMEOUT="${3:-2}"

if [ -z "$ADDR" ]; then
    echo "Usage: $0 <ip/cidr> [threads] [timeout]"
    exit 1
fi

clear

printf "╭──────────────────────────────────────────────────────────────────────────────╮\n"
printf "│                          RealiTLScanner                                     │\n"
printf "├──────────────────────────────────────────────────────────────────────────────┤\n"
printf "│ Target    : %-61s │\n" "$ADDR"
printf "│ Threads   : %-61s │\n" "$THREADS"
printf "│ Timeout   : %-61ss │\n" "$TIMEOUT"
printf "╰──────────────────────────────────────────────────────────────────────────────╯\n\n"

echo "[$(date +%H:%M:%S)] Starting scan..."
echo

$SCANNER -addr "$ADDR" -thread "$THREADS" -timeout "$TIMEOUT" | while read -r line
do

    if [[ $line == *"Cannot open Country.mmdb"* ]]; then
        continue
    fi

    if [[ $line == *"Started all scanning threads"* ]]; then
        continue
    fi

    if [[ $line == *"Scanning completed"* ]]; then
        echo
        echo "──────────────────────────────────────────────────────────────────────────────"
        echo
        echo "✓ Scan completed."
        exit
    fi

    if [[ $line == *"Connected to target"* ]]; then

        ip=$(echo "$line" | sed -n 's/.*ip=\([^ ]*\).*/\1/p')
        domain=$(echo "$line" | sed -n 's/.*cert-domain=\([^ ]*\).*/\1/p' | tr -d '"')
        tls=$(echo "$line" | sed -n 's/.*tls="\([^"]*\)".*/\1/p')
        alpn=$(echo "$line" | sed -n 's/.*alpn=\([^ ]*\).*/\1/p')
        curve=$(echo "$line" | sed -n 's/.*curve=\([^ ]*\).*/\1/p')
        issuer=$(echo "$line" | sed -n 's/.*cert-issuer="\([^"]*\)".*/\1/p')
        geo=$(echo "$line" | sed -n 's/.*geo=\([^ ]*\).*/\1/p')

        if [[ "$curve" == *MLKEM* ]]; then
            curve="$curve (Post-Quantum)"
        fi

        echo "✓ $ip"
        echo "  Domain : $domain"
        echo "  TLS    : $tls"
        echo "  ALPN   : $alpn"
        echo "  Curve  : $curve"
        echo "  Issuer : $issuer"
        echo "  Geo    : $geo"
        echo
    fi

done
