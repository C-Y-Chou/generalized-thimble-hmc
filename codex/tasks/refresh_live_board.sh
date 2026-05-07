#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/cychou/TLTM
CODEX=$ROOT/codex
REGISTRY=$CODEX/runbooks/task_registry.tsv
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")
USER_NAME=${1:-cychou}

DETAILS=$(mktemp)
trap 'rm -f "$DETAILS"' EXIT
printf "timestamp	jobid	queue	state	name
" > "$DETAILS"

if command -v qstat >/dev/null 2>&1; then
  mapfile -t IDS < <(
    qstat -u "$USER_NAME" 2>/dev/null       | awk 'NR>5 {print $1}'       | sed '/^$/d'
  )

  for jid in "${IDS[@]}"; do
    qf=$(qstat -f "$jid" 2>/dev/null || true)
    [ -z "$qf" ] && continue
    name=$(awk -F' = ' '/^[[:space:]]*Job_Name =/{print $2; exit}' <<< "$qf")
    queue=$(awk -F' = ' '/^[[:space:]]*queue =/{print $2; exit}' <<< "$qf")
    state=$(awk -F' = ' '/^[[:space:]]*job_state =/{print $2; exit}' <<< "$qf")
    printf "%s	%s	%s	%s	%s
" "$NOW" "$jid" "${queue:-NA}" "${state:-NA}" "${name:-NA}" >> "$DETAILS"
  done
fi

mkdir -p "$CODEX/state"
cp "$DETAILS" "$CODEX/state/job_tracker.tsv"

write_tracker() {
  local slug=$1
  local name_regex=$2
  local w="$CODEX/workspaces/$slug"
  [ -d "$w" ] || return 0

  printf "timestamp	jobid	queue	state	name
" > "$w/state/job_tracker.tsv"
  awk -F'	' -v pat="$name_regex" 'NR>1 && $5 ~ pat {print}' "$DETAILS" >> "$w/state/job_tracker.tsv"
  echo "updated: $NOW" > "$w/context/LAST_REFRESH.txt"
}

write_tracker "stage3_4" "^(s34_|merge_s34)"
write_tracker "stage3_3_rg_redo" "^(s33_|merge_s33)"
write_tracker "ngport_rg_single_replica_t03_nstep_grid" "^(ngport_|sngport_|merge_ngport)"

TOTAL=$(awk 'END{print NR-1}' "$DETAILS")
RUNNING=$(awk -F'	' 'NR>1 && $4=="R"{c++} END{print c+0}' "$DETAILS")
QUEUED=$(awk -F'	' 'NR>1 && $4=="Q"{c++} END{print c+0}' "$DETAILS")
HELD=$(awk -F'	' 'NR>1 && $4=="H"{c++} END{print c+0}' "$DETAILS")
BLOCKED=$(awk -F'	' 'NR>1 && $4=="B"{c++} END{print c+0}' "$DETAILS")

cat > "$CODEX/state/run_manifest_latest.env" <<EOM
REFRESH_DATE=$NOW
REFRESH_USER=$USER_NAME
TOTAL_JOBS=$TOTAL
RUNNING_JOBS=$RUNNING
QUEUED_JOBS=$QUEUED
HELD_JOBS=$HELD
BLOCKED_ARRAY_PARENTS=$BLOCKED
LIVE_BOARD_PATH=/home/cychou/TLTM/codex/runbooks/LIVE_BOARD.md
TASK_REGISTRY_PATH=/home/cychou/TLTM/codex/runbooks/task_registry.tsv
EOM

status_of() {
  local slug=$1
  if [ -f "$REGISTRY" ]; then
    awk -F'	' -v s="$slug" '$1==s {print $3; found=1} END{if(!found) print "unregistered"}' "$REGISTRY"
  else
    echo "unregistered"
  fi
}

emit_task_section() {
  local slug=$1
  local title=$2
  local w="$CODEX/workspaces/$slug"
  local tracker="$w/state/job_tracker.tsv"

  echo "### $title"
  echo "- slug: \`$slug\`"
  echo "- registry status: \`$(status_of "$slug")\`"
  echo "- workspace: \`$w\`"

  if [ ! -f "$tracker" ]; then
    echo "- jobs: tracker missing"
    echo
    return
  fi

  local cnt
  cnt=$(awk 'END{print NR-1}' "$tracker")
  echo "- tracked jobs: \`$cnt\`"
  if [ "$cnt" -eq 0 ]; then
    echo "- job list: none"
    echo
    return
  fi

  echo "- job list:"
  awk -F'	' 'NR>1 {printf "  - %s | %s | state=%s | %s\n", $2, $3, $4, $5}' "$tracker"
  echo
}

cat > "$CODEX/runbooks/LIVE_BOARD.md" <<EOM
# TLTM Codex Live Board

Updated: $NOW
Refreshed by: \`/home/cychou/TLTM/codex/tasks/refresh_live_board.sh\`

## Queue Summary (user: $USER_NAME)
- total jobs: \`$TOTAL\`
- running (R): \`$RUNNING\`
- queued (Q): \`$QUEUED\`
- held (H): \`$HELD\`
- blocked array parent (B): \`$BLOCKED\`

## Task Snapshots
EOM

{
  emit_task_section "stage3_4" "Stage3_4"
  emit_task_section "stage3_3_rg_redo" "Stage3_3 RG Redo"
  emit_task_section "ngport_rg_single_replica_t03_nstep_grid" "ngport RG Single-Replica Grid"
} >> "$CODEX/runbooks/LIVE_BOARD.md"

echo "updated: $NOW" > "$CODEX/context/LAST_REFRESH.txt"

echo "[refresh_live_board] updated at $NOW"
echo "[refresh_live_board] board: $CODEX/runbooks/LIVE_BOARD.md"
