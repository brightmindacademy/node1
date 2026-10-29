#!/bin/bash
clear

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# FIXED HOST CONNECTIVITY CHANNELS
BOT_API_URL="http://13.140.128"
NODE_AGENT_PORT=8080 # The port this local node uses to listen for bot signals
DB_FILE="vps_node_local.db"

if [ "$(id -u)" -eq 0 ]; then SUDO_CMD=""; else SUDO_CMD="sudo"; fi

# Capture the node's true local external IP address
LOCAL_IP=$(curl -s https://ipify.org)

# Core package installation loop
if ! command -v docker >/dev/null 2>&1 || ! command -v sqlite3 >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo -e "${YELLOW}📥 Configuring virtualization hooks and requirements...${NC}"
    $SUDO_CMD apt-get update -y > /dev/null 2>&1
    $SUDO_CMD apt-get install -y docker.io sqlite3 curl python3 python3-pip -y > /dev/null 2>&1
fi

# Establish node layout databases
sqlite3 "$DB_FILE" "CREATE TABLE IF NOT EXISTS instances (user_name TEXT PRIMARY KEY, discord_id TEXT, admin_name TEXT);"

echo -e "${RED}=== NODE HARDWARE REGISTER SYSTEM ===${NC}"
read -p "Select Node/Company Number (Numeric ID): " NODE_NUM
read -p "Enter Target Client Discord Snowflake ID: " DISCORD_ID
read -p "Allocate RAM Parameter Size (e.g. 4g, 16g): " RAM_INPUT

# Calculate sequence variables natively
CURRENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM instances;")
NEXT_NUM=$((CURRENT_COUNT + 1))
ADMIN_NAME="VPS-${NEXT_NUM}"
USER_NAME="node-${NODE_NUM}-${NEXT_NUM}"

sqlite3 "$DB_FILE" "INSERT INTO instances (user_name, discord_id, admin_name) VALUES ('$USER_NAME', '$DISCORD_ID', '$ADMIN_NAME');"

# Tell the master bot that a new node layout has spun up on the internet
curl -s -X POST "$BOT_API_URL" -H "Content-Type: application/json" \
  -d "{\"event\":\"new_node\",\"node_id\":$NODE_NUM,\"company_name\":\"Node-$NODE_NUM\",\"node_ip\":\"${LOCAL_IP}:${NODE_AGENT_PORT}\"}" > /dev/null

$SUDO_CMD mkdir -p "/hosting/data/${USER_NAME}" > /dev/null 2>&1

# Build container bypassing environment parameters limits
$SUDO_CMD docker run -d \
  --name "$USER_NAME" \
  --restart unless-stopped \
  -v "/hosting/data/${USER_NAME}:/workspace" \
  ubuntu:22.04 /bin/bash -c "while true; do sleep 3600; done" > /dev/null 2>&1

# Trigger telemetry loop update instantly
REAL_USAGE=$(du -sh "/hosting/data/$USER_NAME" 2>/dev/null | awk '{print $1}')
curl -s -X POST "$BOT_API_URL" -H "Content-Type: application/json" \
  -d "{\"vps_user_label\":\"$USER_NAME\",\"vps_admin_label\":\"$ADMIN_NAME\",\"discord_snowflake_id\":\"$DISCORD_ID\",\"status\":\"Running\",\"storage_used\":\"$REAL_USAGE\"}" > /dev/null

# Create a local helper script to handle remote power controls from the bot
cat << 'EOF' > node_agent.py
import os
from aiohttp import web

async def power_control(request):
    data = await request.json()
    action = data.get("action")
    container = data.get("container_name")
    
    # Restrict characters to prevent terminal command escape bugs
    clean_container = "".join([c for c in container if c.isalnum() or c in "-_"])
    
    if action == "start":
        os.system(f"sudo docker start {clean_container}")
    elif action == "stop":
        os.system(f"sudo docker stop {clean_container}")
    elif action == "restart":
        os.system(f"sudo docker restart {clean_container}")
        
    return web.json_response({"status": "executed"})

app = web.Application()
app.router.add_post('/api/node/power', power_control)
web.run_app(app, port=8080)
EOF

# Kill any conflicting old agent loops and boot up the new runtime script listener
pkill -f node_agent.py > /dev/null 2>&1
python3 node_agent.py > /dev/null 2>&1 &

echo -e "${GREEN}✅ Container configured successfully! Remote power agent module listening on port ${NODE_AGENT_PORT}.${NC}"
