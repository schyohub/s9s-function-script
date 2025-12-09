#!/usr/bin/env bash
set -euo pipefail

S9S="$(command -v s9s || true)"

# Arguments from ClusterControl:
# arg1 = "All servers in the replication" (space-separated hostnames)
# arg2 = "The failed master"              (old primary)
# arg3 = "Selected candidate"             (new primary after failover)
# arg4 = "Slaves of old master"           (space-separated hostnames)
ALL_SERVERS="${1:-}"
FAILED_MASTER="${2:-}"
NEW_PRIMARY="${3:-}"
SLAVES_OLD_MASTER="${4:-}"
PORT="3306"

# Detect log file path based on OS family
if command -v apt-get >/dev/null 2>&1; then
    LOGFILE="/var/log/syslog"
else
    LOGFILE="/var/log/messages"
fi

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [rebuild-replica] $*" | tee -a "$LOGFILE"
}

log "=== Starting post-failover replica rebuild script ==="
log "  All servers      : ${ALL_SERVERS}"
log "  Failed master    : ${FAILED_MASTER}"
log "  New primary      : ${NEW_PRIMARY}"
log "  Slaves of old master: ${SLAVES_OLD_MASTER}"

if [ -z "$FAILED_MASTER" ] || [ -z "$NEW_PRIMARY" ]; then
  log "[ERROR] FAILED_MASTER or NEW_PRIMARY is empty. Aborting."
  exit 1
fi

# Find cluster_id using NEW_PRIMARY (selected candidate)
cluster_id=$(
  "$S9S" node --list --long \
  | awk -v host="$NEW_PRIMARY" -v port="$PORT" '$5 == host && $6 == port { print $3 }'
)

if [ -z "$cluster_id" ]; then
  log "[ERROR] Unable to determine cluster_id for host '$NEW_PRIMARY'. Aborting."
  exit 1
fi

log "  Detected cluster_id: $cluster_id"

master="${NEW_PRIMARY}:${PORT}"
slave="${FAILED_MASTER}:${PORT}"

log "  Rebuild target:"
log "    master (new primary): $master"
log "    slave  (old master) : $slave"
log "  Running s9s replication --stage ..."

"$S9S" replication --stage \
  --cluster-id="$cluster_id" \
  --job-tags="post-failover-rebuild" \
  --master="$master" \
  --slave="$slave" \
  --wait

log "  [OK] Replica rebuild completed: $slave <- $master"
log "=== Post-failover replica rebuild script finished ==="
