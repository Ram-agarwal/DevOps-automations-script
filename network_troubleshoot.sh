#!/bin/bash

TARGET=$1

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
  echo "👉 Usage: ./network_troubleshoot.sh google.com OR 8.8.8.8"
  exit 1
fi

echo "🎯 TARGET: $TARGET"
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
getent hosts $TARGET || nslookup $TARGET
echo

############################
# 5️⃣ DEFAULT GATEWAY CHECK
############################
echo "5️⃣ DEFAULT GATEWAY CONNECTIVITY"
GATEWAY=$(ip route | awk '/default/ {print $3}')
ping -c 3 $GATEWAY
echo

############################
# 6️⃣ INTERNET CONNECTIVITY
############################
echo "6️⃣ INTERNET CONNECTIVITY TEST"
ping -c 3 8.8.8.8
echo

############################
# 7️⃣ TARGET CONNECTIVITY
############################
echo "7️⃣ TARGET CONNECTIVITY (PING)"
ping -c 4 $TARGET
echo

############################
# 8️⃣ PORT CONNECTIVITY TEST
############################
echo "8️⃣ PORT CONNECTIVITY TEST"
for port in 80 443 22 3306 5432; do
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
ss -tulnp
echo

############################
# 1️⃣1️⃣ FIREWALL STATUS
############################
echo "1️⃣1️⃣ FIREWALL STATUS"
iptables -L -n 2>/dev/null || ufw status
echo

############################
# 1️⃣2️⃣ NETWORK LOGS (journalctl)
############################
echo "1️⃣2️⃣ NETWORK RELATED LOGS (journalctl)"
journalctl -u NetworkManager --since "1 hour ago" 2>/dev/null
journalctl -p 3 --since "1 hour ago" | grep -i network
echo

############################
# 1️⃣3️⃣ KERNEL NETWORK ERRORS
############################
echo "1️⃣3️⃣ KERNEL NETWORK ERRORS"
dmesg | grep -i -E "network|eth|dns|timeout|unreachable|packet" | tail -20
echo

############################
# 1️⃣4️⃣ TRACEROUTE (PATH ISSUE)
############################
echo "1️⃣4️⃣ TRACEROUTE"
traceroute -m 10 $TARGET || tracepath $TARGET
echo

############################
# 1️⃣5️⃣ TCPDUMP (LIVE PACKET CHECK)
############################
echo "1️⃣5️⃣ TCPDUMP (10 packets sample)"
echo "ℹ Capturing traffic for $TARGET (Press Ctrl+C to stop)"
timeout 10 tcpdump -i any host $TARGET -nn 2>/dev/null
echo

echo "================================================="
echo " NETWORK TROUBLESHOOT COMPLETED"
echo "================================================="
