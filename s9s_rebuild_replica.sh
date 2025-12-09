#!/usr/bin/env bash
set -euo pipefail

S9S=`whereis s9s |awk '{print $2}'`

# Detect log file path based on OS family
if command -v apt-get >/dev/null 2>&1; then
    LOGFILE="/var/log/syslog"
else
    LOGFILE="/var/log/messages"
fi

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [rebuild-replica] $@" | tee -a "$LOGFILE"
}

log "=== Starting replica rebuild script ==="

# Find all cluster_id values that have a node in "Shut down (read-only)" state
mapfile -t CLUSTER_IDS < <(
  "$S9S" node --list --long \
  | awk '/Shut down \(read-only\)/ {print $3}' \
  | sort -u
)

if [ "${#CLUSTER_IDS[@]}" -eq 0 ]; then
  log "No clusters found with replicas in 'Shut down (read-only)' state."
  exit 0
fi

for cluster_id in "${CLUSTER_IDS[@]}"; do
  log "==> Processing cluster_id: $cluster_id"

  # Find the new primary (read-write)
  new_primary=$(
    "$S9S" node --list --long --cluster-id="$cluster_id" \
    | awk '/Up and running \(read-write\)/ {print $5":"$6; exit}'
  )

  # Find the old primary (shut down read-only)
  old_primary=$(
    "$S9S" node --list --long --cluster-id="$cluster_id" \
    | awk '/Shut down \(read-only\)/ {print $5":"$6; exit}'
  )

  if [ -z "$new_primary" ] || [ -z "$old_primary" ]; then
    log "[SKIP] Unable to detect new_primary or old_primary for cluster $cluster_id"
    log "       new_primary: '$new_primary'"
    log "       old_primary : '$old_primary'"
    continue
  fi

  log "  new_primary (master): $new_primary"
  log "  old_primary (slave) : $old_primary"
  log "  Running stage replication..."

  "$S9S" replication --stage \
    --cluster-id="$cluster_id" \
    --job-tags="stage" \
    --master="$new_primary" \
    --slave="$old_primary" \
    --wait

  log "  [OK] Replica rebuild completed for cluster_id=$cluster_id"
done

log "=== Replica rebuild script completed ==="
