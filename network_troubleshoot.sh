#!/bin/bash
set -o pipefail

# ========= CONFIG (Only this changes per project) =========
TARGET="$1"   # Target IP or Domain
PORTS=(80 443 22 3306 5432)

# ========= REPORT SETUP =========
REPORT_FILE="/tmp/network_report_$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$REPORT_FILE") 2>&1

echo "================================================="
echo " NETWORK TROUBLESHOOT REPORT"
echo "================================================="
date
echo

############################
# 0️⃣ INPUT CHECK
############################
if [ -z "$TARGET" ]; then
  echo "❌ ERROR: Please provide IP or Domain"
  echo "👉 Usage: sudo ./network_troubleshoot.sh <IP_or_DOMAIN>"
  exit 1
fi

echo "🎯 TARGET: $TARGET"
echo

############################
# ROOT CHECK (Prod Safety)
############################
if [ "$EUID" -ne 0 ]; then
  echo "⚠️ Warning: Some checks need root (firewall, tcpdump, dmesg)."
  echo "👉 Best practice: sudo ./network_troubleshoot.sh $TARGET"
fi
echo

############################
# OS INFO
############################
echo "🖥 OS INFO"
lsb_release -a 2>/dev/null || cat /etc/os-release
echo

############################
# 1️⃣ NETWORK INTERFACE STATUS
############################
echo "1️⃣ NETWORK INTERFACE STATUS"
ip a
echo

############################
# 2️⃣ ROUTING TABLE
############################
echo "2️⃣ ROUTING TABLE"
ip route
echo

############################
# 3️⃣ DNS CONFIGURATION
############################
echo "3️⃣ DNS CONFIGURATION"
cat /etc/resolv.conf
echo

############################
# 4️⃣ DNS RESOLUTION TEST
############################
echo "4️⃣ DNS RESOLUTION TEST"
if getent hosts "$TARGET" >/dev/null 2>&1; then
  getent hosts "$TARGET"
elif command -v nslookup >/dev/null 2>&1; then
  nslookup "$TARGET"
else
  echo "❌ DNS tools not available"
fi


############################
# 5️⃣ DEFAULT GATEWAY CHECK
############################
GATEWAY=$(ip route | awk '/default/ {print $3}')
if [ -n "$GATEWAY" ]; then
  ping -c 3 -W 2 "$GATEWAY"
else
  echo "❌ No default gateway found"
fi

############################
# 6️⃣ INTERNET CONNECTIVITY
############################
echo "6️⃣ INTERNET CONNECTIVITY"
ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1 \
  && echo "✅ Internet reachable (8.8.8.8)" \
  || echo "❌ No internet connectivity"
curl -Is https://google.com | head -1 || echo "❌ HTTPS outbound blocked"
echo

############################
# 7️⃣ TARGET CONNECTIVITY
############################
echo "7️⃣ TARGET CONNECTIVITY (PING)"
ping -c 4 -W 2 "$TARGET"
echo

############################
# 8️⃣ PORT CONNECTIVITY TEST
############################
echo "8️⃣ PORT CONNECTIVITY TEST"
for port in "${PORTS[@]}"; do
  timeout 3 bash -c "</dev/tcp/$TARGET/$port" \
    && echo "✅ Port $port OPEN" \
    || echo "❌ Port $port CLOSED"
done
echo

############################
# 9️⃣ ACTIVE CONNECTIONS
############################
echo "9️⃣ ACTIVE NETWORK CONNECTIONS"
ss -s
echo

############################
# 🔟 LISTENING PORTS
############################
echo "🔟 LISTENING PORTS"
ss -tulnp 2>/dev/null || echo "⚠️ Run as root to see listening process details"
echo

############################
# 1️⃣1️⃣ FIREWALL STATUS
############################
echo "1️⃣1️⃣ FIREWALL STATUS"
iptables -L -n 2>/dev/null || nft list ruleset 2>/dev/null || ufw status 2>/dev/null || echo "⚠️ Firewall status not accessible"
echo

############################
# 1️⃣2️⃣ NETWORK LOGS
############################
echo "1️⃣2️⃣ NETWORK RELATED LOGS (last 1 hour)"
journalctl -u NetworkManager --since "1 hour ago" 2>/dev/null | tail -20
journalctl -p 3 --since "1 hour ago" | grep -i network | tail -20
echo

############################
# 1️⃣3️⃣ KERNEL NETWORK ERRORS
############################
echo "1️⃣3️⃣ KERNEL NETWORK ERRORS"
dmesg | grep -i -E "network|eth|dns|timeout|unreachable|packet" | tail -20
echo

############################
# 1️⃣4️⃣ TRACEROUTE
############################

echo "1️⃣4️⃣ TRACEROUTE / TRACEPATH"

if command -v traceroute &> /dev/null; then
  traceroute -m 20 -w 2 "$TARGET"
elif command -v tracepath &> /dev/null; then
  tracepath -n -m 20 "$TARGET"
else
  echo "⚠️ traceroute/tracepath not installed. Skipping path analysis."
fi

echo


echo "================================================="
echo " NETWORK TROUBLESHOOT COMPLETED"
echo "📄 Report saved at: $REPORT_FILE"
echo "================================================="

