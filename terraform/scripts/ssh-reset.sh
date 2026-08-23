#!/bin/bash

BASE_IP="192.168.1"
START=12
END=18

echo "---  Starting SSH Known Hosts Reset ---"

for i in $(seq $START $END); do
    TARGET_IP="$BASE_IP.$i"
    
    ssh-keygen -R "$TARGET_IP" &> /dev/null
    echo " Cleared old key for: $TARGET_IP"

    echo " Scanning for new key on $TARGET_IP..."
    
    NEW_KEY=$(ssh-keyscan -T 5 -H "$TARGET_IP" 2>/dev/null)

    if [ -n "$NEW_KEY" ]; then
        echo "$NEW_KEY" >> ~/.ssh/known_hosts
        echo " Successfully trusted $TARGET_IP"
    else
        echo "  Warning: Could not reach $TARGET_IP."
    fi
    echo "-----------------------------------"
done