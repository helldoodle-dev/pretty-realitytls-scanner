#!/usr/bin/env bash

SCANNER="docker run --rm realitlscanner"

GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"
BOLD="\e[1m"

clear

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔════════════════════════════════════════════════════╗
║                RealiTLScanner v1.0                ║
╚════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"

read -rp "🌍 Target IP/CIDR: " ADDR

if [[ -z "$ADDR" ]]; then
    echo -e "${RED}Target required.${RESET}"
    exit 1
fi

read -rp "⚡ Threads [100]: " THREADS
THREADS=${THREADS:-100}

read -rp "⏱ Timeout [2]: " TIMEOUT
TIMEOUT=${TIMEOUT:-2}

clear

echo -e "${GREEN}${BOLD}"
printf "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗\n"
printf "║ %-148s ║\n" "RealiTLScanner"
printf "╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣\n"
printf "║ Target : %-137s ║\n" "$ADDR"
printf "║ Threads: %-137s ║\n" "$THREADS"
printf "║ Timeout: %-137ss ║\n" "$TIMEOUT"
printf "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝\n"
echo -e "${RESET}"

printf "\n"

printf "┌─────────────────┬────────────────────────────┬──────────────┬────────┬──────────────────────────────┬──────────────────────────────┬────────────┐\n"
printf "│ %-15s │ %-26s │ %-12s │ %-6s │ %-28s │ %-28s │ %-10s │\n" \
"IP" "DOMAIN" "TLS" "ALPN" "CURVE" "ISSUER" "GEO"
printf "├─────────────────┼────────────────────────────┼──────────────┼────────┼──────────────────────────────┼──────────────────────────────┼────────────┤\n"

$SCANNER -addr "$ADDR" -thread "$THREADS" -timeout "$TIMEOUT" | while read -r line
do

    [[ $line == *"Cannot open Country.mmdb"* ]] && continue
    [[ $line == *"Started all scanning threads"* ]] && continue

    if [[ $line == *"Scanning completed"* ]]; then
        printf "└─────────────────┴────────────────────────────┴──────────────┴────────┴──────────────────────────────┴──────────────────────────────┴────────────┘\n"
        echo
        echo -e "${GREEN}✔ Scan completed.${RESET}"
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

        [[ "$curve" == *MLKEM* ]] && curve="$curve PQ"

        printf "│ %-15s │ %-26.26s │ %-12.12s │ %-6.6s │ %-28.28s │ %-28.28s │ %-10.10s │\n" \
            "$ip" "$domain" "$tls" "$alpn" "$curve" "$issuer" "$geo"
    fi

done
