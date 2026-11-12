#!/usr/bin/env bash
# System health report: CPU, memory, disk, load and top processes.
# Exit codes: 0 healthy, 1 warning, 2 critical.
set -euo pipefail

CPU_WARN=90
MEM_WARN=85
DISK_WARN=80
CRIT=95
JSON=false

usage() {
  echo "Usage: $0 [--json] [--cpu N] [--mem N] [--disk N] [--critical N]"
  echo "  --cpu, --mem, --disk  warning thresholds in percent (default 90, 85, 80)"
  echo "  --critical            critical threshold for all checks (default 95)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=true ;;
    --cpu) CPU_WARN="$2"; shift ;;
    --mem) MEM_WARN="$2"; shift ;;
    --disk) DISK_WARN="$2"; shift ;;
    --critical) CRIT="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done

for n in "$CPU_WARN" "$MEM_WARN" "$DISK_WARN" "$CRIT"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -gt 100 ]; then
    echo "Threshold must be a number between 0 and 100: $n" >&2
    exit 2
  fi
done

# CPU: compare two samples of /proc/stat taken one second apart
read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
idle=$(( (i2 + w2) - (i1 + w1) ))
total=$(( (u2 + n2 + s2 + i2 + w2 + q2 + sq2 + st2) - (u1 + n1 + s1 + i1 + w1 + q1 + sq1 + st1) ))
cpu=$(( total > 0 ? (100 * (total - idle)) / total : 0 ))

# Memory: MemAvailable is what the kernel can give to new processes
mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
mem=$(( 100 * (mem_total - mem_avail) / mem_total ))

# Disks: real filesystems only, skip tmpfs, overlay and read-only mounts
ro_mounts=$(awk '$4 ~ /^ro(,|$)/ {print $2}' /proc/mounts)
disks=$(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null \
  | awk -v ro="$ro_mounts" 'BEGIN {split(ro, r, "\n"); for (i in r) skip[r[i]] = 1}
    NR > 1 && !($6 in skip) {gsub("%", "", $5); print $6, $5}')
disk_max=$(echo "$disks" | awk 'BEGIN {m = 0} $2 > m {m = $2} END {print m}')

read -r load1 load5 load15 _ < /proc/loadavg

top=$(ps -eo comm=,%mem= --sort=-%mem | head -n 5)

status=0
problems=""
check() {
  local name=$1 value=$2 warn=$3
  if [ "$value" -ge "$CRIT" ]; then
    status=2
    problems="$problems $name ${value}%"
  elif [ "$value" -ge "$warn" ]; then
    [ "$status" -lt 1 ] && status=1
    problems="$problems $name ${value}%"
  fi
}
check cpu "$cpu" "$CPU_WARN"
check memory "$mem" "$MEM_WARN"
check disk "$disk_max" "$DISK_WARN"

case $status in
  0) label=HEALTHY; msg="System operating normally." ;;
  1) label=WARNING; msg="Above warning threshold:$problems" ;;
  2) label=CRITICAL; msg="Above threshold:$problems (critical at ${CRIT}%)" ;;
esac

if [ "$JSON" = true ]; then
  disks_json=$(echo "$disks" | awk '{printf "%s{\"mount\":\"%s\",\"used_percent\":%s}", (NR > 1 ? "," : ""), $1, $2}')
  top_json=$(echo "$top" | awk '{printf "%s{\"name\":\"%s\",\"mem_percent\":%s}", (NR > 1 ? "," : ""), $1, $2}')
  printf '{"timestamp":"%s","host":"%s","status":"%s",' "$(date -Iseconds)" "$(hostname)" "$label"
  printf '"cpu_percent":%s,"mem_percent":%s,' "$cpu" "$mem"
  printf '"load_average":[%s,%s,%s],' "$load1" "$load5" "$load15"
  printf '"disks":[%s],"top_memory":[%s]}\n' "$disks_json" "$top_json"
else
  echo "System Health Report ($(date '+%Y-%m-%d %H:%M:%S'))"
  echo "--------------------"
  printf "%-16s %s%%\n" "CPU Usage:" "$cpu"
  printf "%-16s %s%%\n" "Memory Usage:" "$mem"
  printf "%-16s %s, %s, %s\n" "Load Average:" "$load1" "$load5" "$load15"
  echo
  echo "Disk Usage:"
  echo "$disks" | awk '{printf "  %-20s %s%%\n", $1, $2}'
  echo
  echo "Top 5 Memory Processes:"
  echo "$top" | awk '{printf "%d. %-16s %s%%\n", NR, $1, $2}'
  echo
  echo "[$label] $msg"
fi

exit $status
