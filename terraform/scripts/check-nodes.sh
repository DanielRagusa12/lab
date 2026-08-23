#!/bin/bash

# Define nodes: "Name|IP"
NODES=(
    "VPN Gateway|192.168.1.14"
    "Cloudflared|192.168.1.15"
    "Playit Client|192.168.1.17"
    "Monitor Server|192.168.1.18"
    "Microservice|192.168.1.13"
    "Game Server|192.168.1.16"
)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "--- Starting Infrastructure Health Check ---"

for node in "${NODES[@]}"; do
    IFS="|" read -r NAME IP <<< "$node"
    
    echo -n "Checking $NAME ($IP)... "

    # 1. Test Ping
    if ping -c 1 -W 1 "$IP" > /dev/null 2>&1; then
        PING_RES="${GREEN}UP${NC}"
    else
        PING_RES="${RED}DOWN${NC}"
    fi

    # 2. Test SSH Port using Bash's built-in /dev/tcp
    # This is more portable than 'nc'
    if timeout 2 bash -c "true < /dev/tcp/$IP/22" > /dev/null 2>&1; then
        SSH_RES="${GREEN}OPEN${NC}"
    else
        SSH_RES="${RED}CLOSED${NC}"
    fi

    echo -e "[Ping: $PING_RES] [SSH: $SSH_RES]"
done

echo "--- Check Complete ---"
