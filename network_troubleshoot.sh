#!/bin/bash
set -o pipefail

# ========= CONFIG (Only this changes per project) =========
TARGET="$1"   # Target IP or Domain
PORTS=(80 443 22 3306 5432 8080 8443 6379 27017 5672)

# ========= COLORS =========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ========= REPORT SETUP =========
REPORT_FILE="/tmp/network_report_$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$REPORT_FILE") 2>&1

echo -e "${BOLD}=================================================${NC}"
echo -e "${BOLD}       NETWORK TROUBLESHOOT REPORT              ${NC}"
echo -e "${BOLD}=================================================${NC}"
date
echo "Hostname: $(hostname)"
echo "Report saved to: $REPORT_FILE"
echo

############################
# 0️⃣  INPUT CHECK
############################
if [ -z "$TARGET" ]; then
  echo -e "${RED}❌ ERROR: Please provide IP or Domain${NC}"
  echo "👉 Usage: sudo ./network_troubleshoot.sh <IP_or_DOMAIN>"
  exit 1
fi

echo -e "🎯 ${BOLD}TARGET: $TARGET${NC}"
echo

############################
# ROOT CHECK
############################
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}⚠️  Warning: Some checks need root (firewall, tcpdump, dmesg).${NC}"
  echo "👉 Best practice: sudo ./network_troubleshoot.sh $TARGET"
fi
echo

############################
# 🔧 AUTO-INSTALL MISSING TOOLS (Production Safe)
############################
echo -e "${CYAN}${BOLD}🔧 AUTO-INSTALL: Checking required tools...${NC}"

# Detect package manager
if command -v apt-get &>/dev/null; then
  PKG_MANAGER="apt-get"
  PKG_INSTALL="apt-get install -y -q"
  PKG_UPDATE="apt-get update -qq"
elif command -v yum &>/dev/null; then
  PKG_MANAGER="yum"
  PKG_INSTALL="yum install -y -q"
  PKG_UPDATE="yum makecache -q"
elif command -v dnf &>/dev/null; then
  PKG_MANAGER="dnf"
  PKG_INSTALL="dnf install -y -q"
  PKG_UPDATE="dnf makecache -q"
elif command -v zypper &>/dev/null; then
  PKG_MANAGER="zypper"
  PKG_INSTALL="zypper install -y --quiet"
  PKG_UPDATE="zypper refresh -q"
else
  PKG_MANAGER="unknown"
  echo -e "${YELLOW}⚠️  Unknown package manager. Manual install may be needed.${NC}"
fi

echo "📦 Package Manager: $PKG_MANAGER"

# Tool → package name mapping
declare -A TOOLS_DEB=(
  [traceroute]="traceroute"
  [tracepath]="iputils-tracepath"
  [nslookup]="dnsutils"
  [dig]="dnsutils"
  [curl]="curl"
  [wget]="wget"
  [ss]="iproute2"
  [ip]="iproute2"
  [ping]="iputils-ping"
  [netstat]="net-tools"
  [mtr]="mtr-tiny"
  [nmap]="nmap"
  [tcpdump]="tcpdump"
  [iperf3]="iperf3"
  [lsof]="lsof"
  [nc]="netcat-openbsd"
  [whois]="whois"
  [arp]="net-tools"
  [ethtool]="ethtool"
  [openssl]="openssl"
)

declare -A TOOLS_RPM=(
  [traceroute]="traceroute"
  [tracepath]="iputils"
  [nslookup]="bind-utils"
  [dig]="bind-utils"
  [curl]="curl"
  [wget]="wget"
  [ss]="iproute"
  [ip]="iproute"
  [ping]="iputils"
  [netstat]="net-tools"
  [mtr]="mtr"
  [nmap]="nmap"
  [tcpdump]="tcpdump"
  [iperf3]="iperf3"
  [lsof]="lsof"
  [nc]="nmap-ncat"
  [whois]="whois"
  [arp]="net-tools"
  [ethtool]="ethtool"
  [openssl]="openssl"
)

INSTALLED_NOW=()
FAILED_INSTALL=()
ALREADY_PRESENT=()

install_if_missing() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    if [ "$EUID" -ne 0 ]; then
      echo -e "  ${YELLOW}⚠️  $cmd not found. Run as root to auto-install.${NC}"
      FAILED_INSTALL+=("$cmd")
      return
    fi
    local pkg=""
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
      pkg="${TOOLS_DEB[$cmd]:-$cmd}"
    else
      pkg="${TOOLS_RPM[$cmd]:-$cmd}"
    fi
    echo -e "  📥 Installing ${BOLD}$cmd${NC} (package: $pkg)..."
    if $PKG_INSTALL "$pkg" &>/dev/null 2>&1; then
      echo -e "  ${GREEN}✅ $cmd installed successfully${NC}"
      INSTALLED_NOW+=("$cmd")
    else
      echo -e "  ${RED}❌ Failed to install $cmd ($pkg)${NC}"
      FAILED_INSTALL+=("$cmd")
    fi
  else
    ALREADY_PRESENT+=("$cmd")
  fi
}

# Update package index once (only if root)
if [ "$EUID" -eq 0 ] && [ "$PKG_MANAGER" != "unknown" ]; then
  echo "🔄 Updating package index (silent)..."
  $PKG_UPDATE 2>/dev/null
fi

# Check and install all required tools
for tool in traceroute tracepath nslookup dig curl wget ss ip ping \
            netstat mtr nmap tcpdump lsof nc whois arp ethtool openssl; do
  install_if_missing "$tool"
done

echo
echo "✅ Already present  : ${ALREADY_PRESENT[*]:-none}"
echo "📥 Installed now    : ${INSTALLED_NOW[*]:-none}"
echo "⚠️  Could not install: ${FAILED_INSTALL[*]:-none}"
echo

############################
# 1️⃣  NETWORK INTERFACE STATUS
############################
echo -e "${CYAN}${BOLD}1️⃣  NETWORK INTERFACE STATUS${NC}"
ip -c a 2>/dev/null || ip a
echo
echo "--- Interface Statistics (TX/RX) ---"
ip -s link 2>/dev/null | head -60
echo

############################
# 2️⃣  ROUTING TABLE
############################
echo -e "${CYAN}${BOLD}2️⃣  ROUTING TABLE${NC}"
ip route show table all 2>/dev/null || ip route
echo
echo "--- IPv6 Routes ---"
ip -6 route 2>/dev/null || echo "No IPv6 routes"
echo

############################
# 3️⃣  DNS CONFIGURATION
############################
echo -e "${CYAN}${BOLD}3️⃣  DNS CONFIGURATION${NC}"
echo "--- /etc/resolv.conf ---"
cat /etc/resolv.conf
echo
echo "--- /etc/hosts ---"
cat /etc/hosts
echo
echo "--- systemd-resolved status ---"
systemctl status systemd-resolved 2>/dev/null | head -10 || echo "systemd-resolved not running"
resolvectl status 2>/dev/null | head -30 || true
echo

############################
# 4️⃣  DNS RESOLUTION TEST
############################
echo -e "${CYAN}${BOLD}4️⃣  DNS RESOLUTION TEST${NC}"
echo "-- getent --"
getent hosts "$TARGET" 2>/dev/null || echo "getent: no result"

echo "-- dig A record --"
if command -v dig &>/dev/null; then
  dig "$TARGET" A +short 2>/dev/null
  echo "-- dig AAAA record --"
  dig "$TARGET" AAAA +short 2>/dev/null
  echo "-- dig timing & server --"
  dig "$TARGET" 2>/dev/null | grep -E "(Query time|SERVER|ANSWER SECTION)" | head -10
else
  echo "dig not available"
fi

echo "-- nslookup --"
if command -v nslookup &>/dev/null; then
  nslookup "$TARGET" 2>/dev/null
fi

echo "-- Reverse DNS (PTR) --"
if command -v dig &>/dev/null; then
  dig -x "$TARGET" +short 2>/dev/null || echo "No PTR record / not a plain IP"
fi
echo

############################
# 5️⃣  DEFAULT GATEWAY CHECK
############################
echo -e "${CYAN}${BOLD}5️⃣  DEFAULT GATEWAY CHECK${NC}"
GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
if [ -n "$GATEWAY" ]; then
  echo "Default Gateway: $GATEWAY"
  ping -c 3 -W 2 "$GATEWAY" && echo -e "${GREEN}✅ Gateway reachable${NC}" || echo -e "${RED}❌ Gateway unreachable${NC}"
  echo "--- Gateway ARP ---"
  arp -n "$GATEWAY" 2>/dev/null || ip neigh show "$GATEWAY" 2>/dev/null
else
  echo -e "${RED}❌ No default gateway found${NC}"
fi
echo

############################
# 6️⃣  INTERNET CONNECTIVITY
############################
echo -e "${CYAN}${BOLD}6️⃣  INTERNET CONNECTIVITY${NC}"
ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1 \
  && echo -e "${GREEN}✅ Internet reachable (8.8.8.8 - Google DNS)${NC}" \
  || echo -e "${RED}❌ Internet NOT reachable (8.8.8.8)${NC}"

ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1 \
  && echo -e "${GREEN}✅ Internet reachable (1.1.1.1 - Cloudflare)${NC}" \
  || echo -e "${RED}❌ 1.1.1.1 unreachable${NC}"

echo "--- HTTPS Test ---"
curl -IsS --max-time 5 https://google.com 2>/dev/null | head -2 \
  && echo -e "${GREEN}✅ HTTPS outbound OK${NC}" \
  || echo -e "${RED}❌ HTTPS outbound blocked or failed${NC}"

echo "--- HTTP Test ---"
curl -IsS --max-time 5 http://example.com 2>/dev/null | head -2 \
  && echo -e "${GREEN}✅ HTTP outbound OK${NC}" \
  || echo -e "${RED}❌ HTTP outbound failed${NC}"

echo "--- Public IP ---"
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
echo "Public IP: ${PUBLIC_IP:-Could not fetch}"
echo

############################
# 7️⃣  TARGET CONNECTIVITY
############################
echo -e "${CYAN}${BOLD}7️⃣  TARGET CONNECTIVITY (PING)${NC}"
ping -c 4 -W 2 "$TARGET" \
  && echo -e "${GREEN}✅ Ping successful${NC}" \
  || echo -e "${RED}❌ Ping failed (ICMP may be blocked)${NC}"
echo

############################
# 8️⃣  PORT CONNECTIVITY TEST
############################
echo -e "${CYAN}${BOLD}8️⃣  PORT CONNECTIVITY TEST${NC}"
printf "%-8s %-18s %s\n" "PORT" "STATUS" "SERVICE"
printf "%-8s %-18s %s\n" "----" "------" "-------"

declare -A PORT_NAMES=(
  [22]="SSH"
  [80]="HTTP"
  [443]="HTTPS"
  [3306]="MySQL"
  [5432]="PostgreSQL"
  [6379]="Redis"
  [8080]="HTTP-Alt"
  [8443]="HTTPS-Alt"
  [27017]="MongoDB"
  [5672]="RabbitMQ"
)

for port in "${PORTS[@]}"; do
  service="${PORT_NAMES[$port]:-unknown}"
  if timeout 3 bash -c ">/dev/tcp/$TARGET/$port" 2>/dev/null; then
    printf "%-8s ${GREEN}%-18s${NC} %s\n" "$port" "OPEN ✅" "$service"
  else
    printf "%-8s ${RED}%-18s${NC} %s\n" "$port" "CLOSED/FILTERED ❌" "$service"
  fi
done

echo
if command -v nmap &>/dev/null; then
  echo "--- Nmap Quick Scan (top 100 ports) ---"
  nmap -F --open -T4 "$TARGET" 2>/dev/null | tail -25
fi
echo

############################
# 9️⃣  ACTIVE CONNECTIONS
############################
echo -e "${CYAN}${BOLD}9️⃣  ACTIVE NETWORK CONNECTIONS${NC}"
ss -s
echo
echo "--- Established Connections ---"
ss -tnp state established 2>/dev/null | head -30 || ss -tnp | grep ESTAB | head -30
echo
echo "--- Connections to/from TARGET ---"
ss -tnp 2>/dev/null | grep "$TARGET" || echo "No active connections to $TARGET"
echo

############################
# 🔟  LISTENING PORTS
############################
echo -e "${CYAN}${BOLD}🔟  LISTENING PORTS${NC}"
ss -tulnp 2>/dev/null || echo -e "${YELLOW}⚠️  Run as root for process details${NC}"
echo
if command -v netstat &>/dev/null; then
  echo "--- netstat listening (backup) ---"
  netstat -tulnp 2>/dev/null | head -30
fi
echo

############################
# 1️⃣1️⃣  FIREWALL STATUS
############################
echo -e "${CYAN}${BOLD}1️⃣1️⃣  FIREWALL STATUS${NC}"
echo "--- iptables ---"
iptables -L -n -v 2>/dev/null | head -40 || echo "iptables not accessible (need root)"
echo
echo "--- nftables ---"
nft list ruleset 2>/dev/null | head -30 || echo "nftables not active"
echo
echo "--- ufw ---"
ufw status verbose 2>/dev/null || echo "ufw not active"
echo
echo "--- firewalld ---"
if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --state 2>/dev/null
  firewall-cmd --list-all 2>/dev/null | head -20
else
  echo "firewalld not installed"
fi
echo

############################
# 1️⃣2️⃣  NETWORK INTERFACE STATS
############################
echo -e "${CYAN}${BOLD}1️⃣2️⃣  NETWORK INTERFACE STATISTICS (TX/RX bytes)${NC}"
cat /proc/net/dev 2>/dev/null
echo
echo "--- ethtool (primary interface) ---"
MAIN_IF=$(ip route | awk '/default/{print $5; exit}')
if [ -n "$MAIN_IF" ] && command -v ethtool &>/dev/null; then
  ethtool "$MAIN_IF" 2>/dev/null | grep -E "(Speed|Duplex|Link|Auto)" | head -10
fi
echo

############################
# 1️⃣3️⃣  ARP TABLE
############################
echo -e "${CYAN}${BOLD}1️⃣3️⃣  ARP / NEIGHBOR TABLE${NC}"
ip neigh show 2>/dev/null || arp -n 2>/dev/null
echo

############################
# 1️⃣4️⃣  NETWORK LOGS
############################
echo -e "${CYAN}${BOLD}1️⃣4️⃣  NETWORK RELATED LOGS (last 1 hour)${NC}"
journalctl -u NetworkManager --since "1 hour ago" 2>/dev/null | tail -20 || echo "NetworkManager logs not available"
echo "--- Error/Warning logs ---"
journalctl -p 3 --since "1 hour ago" 2>/dev/null | grep -i "network\|connect\|timeout\|refused" | tail -20 || true
echo

############################
# 1️⃣5️⃣  KERNEL NETWORK ERRORS
############################
echo -e "${CYAN}${BOLD}1️⃣5️⃣  KERNEL NETWORK ERRORS${NC}"
dmesg 2>/dev/null | grep -i -E "network|eth|eno|ens|dns|timeout|unreachable|packet|dropped|error|reset" | tail -30 \
  || echo "dmesg requires root"
echo

############################
# 1️⃣6️⃣  TRACEROUTE / PATH
############################
echo -e "${CYAN}${BOLD}1️⃣6️⃣  TRACEROUTE / PATH ANALYSIS${NC}"
if command -v traceroute &>/dev/null; then
  echo "--- traceroute ---"
  traceroute -m 20 -w 2 "$TARGET" 2>/dev/null
elif command -v tracepath &>/dev/null; then
  echo "--- tracepath ---"
  tracepath -n -m 20 "$TARGET" 2>/dev/null
else
  echo "⚠️  traceroute/tracepath not available"
fi

if command -v mtr &>/dev/null; then
  echo "--- mtr report (10 cycles) ---"
  mtr --report --report-cycles 10 --no-dns "$TARGET" 2>/dev/null
fi
echo

############################
# 1️⃣7️⃣  SSL/TLS CERTIFICATE CHECK
############################
echo -e "${CYAN}${BOLD}1️⃣7️⃣  SSL/TLS CERTIFICATE CHECK${NC}"
if command -v openssl &>/dev/null; then
  echo | timeout 5 openssl s_client -connect "$TARGET:443" -servername "$TARGET" 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates 2>/dev/null \
    || echo "No SSL on port 443 or target is not a domain"
else
  echo "openssl not installed"
fi
echo

############################
# 1️⃣8️⃣  WHOIS / IP INFO
############################
echo -e "${CYAN}${BOLD}1️⃣8️⃣  WHOIS / IP INFO${NC}"
if command -v whois &>/dev/null; then
  whois "$TARGET" 2>/dev/null | grep -E "^(NetName|Organization|OrgName|Country|CIDR|inetnum|descr|abuse)" | head -15
else
  echo "whois not available"
fi
echo

############################
# 1️⃣9️⃣  OPEN NETWORK SOCKETS
############################
echo -e "${CYAN}${BOLD}1️⃣9️⃣  OPEN NETWORK SOCKETS (lsof)${NC}"
if command -v lsof &>/dev/null && [ "$EUID" -eq 0 ]; then
  lsof -i -n -P 2>/dev/null | grep -v "^COMMAND" | head -30
else
  echo "lsof requires root or not installed"
fi
echo

############################
# 2️⃣0️⃣  SUMMARY
############################
echo -e "${BOLD}=================================================${NC}"
echo -e "${BOLD}            📋 TROUBLESHOOT SUMMARY             ${NC}"
echo -e "${BOLD}=================================================${NC}"

GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
[ -n "$GATEWAY" ] && ping -c 1 -W 1 "$GATEWAY" &>/dev/null \
  && echo -e "${GREEN}✅ Gateway ($GATEWAY)     : Reachable${NC}" \
  || echo -e "${RED}❌ Gateway ($GATEWAY)     : Unreachable${NC}"

ping -c 1 -W 2 8.8.8.8 &>/dev/null \
  && echo -e "${GREEN}✅ Internet               : Reachable${NC}" \
  || echo -e "${RED}❌ Internet               : NOT reachable${NC}"

getent hosts "$TARGET" &>/dev/null \
  && echo -e "${GREEN}✅ DNS Resolution         : OK${NC}" \
  || echo -e "${RED}❌ DNS Resolution         : FAILED${NC}"

ping -c 1 -W 2 "$TARGET" &>/dev/null \
  && echo -e "${GREEN}✅ Target Ping            : Reachable${NC}" \
  || echo -e "${YELLOW}⚠️  Target Ping            : No response (ICMP may be blocked)${NC}"

echo "--- Key Port Summary ---"
for port in 22 80 443; do
  if timeout 2 bash -c ">/dev/tcp/$TARGET/$port" 2>/dev/null; then
    echo -e "${GREEN}✅ Port $port                  : OPEN${NC}"
  else
    echo -e "${RED}❌ Port $port                  : CLOSED/FILTERED${NC}"
  fi
done

echo
echo -e "${BOLD}=================================================${NC}"
echo -e "${BOLD} ✅ NETWORK TROUBLESHOOT COMPLETED${NC}"
echo -e "${BOLD} 📄 Full report saved: $REPORT_FILE${NC}"
echo -e "${BOLD}=================================================${NC}"

