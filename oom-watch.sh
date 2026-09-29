#!/usr/bin/env bash
# oom-watch - watch Linux OOM killer events and summarize memory pressure
# Works on Linux (reads dmesg/journalctl) and on macOS (use "scan -f FILE").
set -u

PROG="oom-watch"
VERSION="1.0.0"

FIXTURE='Jun  4 09:12:01 host kernel: Out of memory: Killed process 1234 (python3) total-vm:2048000kB, anon-rss:1536000kB, file-rss:0kB, shmem-rss:0kB, UID:1000 pgtables:3400kB oom_score_adj:0
Jun  4 09:12:02 host kernel: oom_reaper: reaped process 1234 (python3), now anon-rss:0kB, file-rss:0kB, shmem-rss:0kB
Jun  4 10:40:11 host kernel: Out of memory: Killed process 2048 (java) total-vm:8192000kB, anon-rss:6144000kB, file-rss:10240kB, shmem-rss:0kB, UID:1000 pgtables:12000kB oom_score_adj:0
Jun  4 11:55:43 host kernel: Out of memory: Killed process 777 (node) total-vm:4096000kB, anon-rss:3072000kB, file-rss:51200kB, shmem-rss:0kB, UID:0 pgtables:8000kB oom_score_adj:0'

usage() {
  cat <<EOF
$PROG $VERSION - watch Linux OOM killer events and summarize memory pressure

Usage:
  $PROG scan [-f FILE] [-n N]   Show OOM killer events from the kernel log (or FILE)
  $PROG top  [-n N]             Show top processes by resident memory (RSS)
  $PROG selftest                Run built-in tests against a fixture log
  $PROG -h | --help             Show this help

Options:
  -f FILE   Read kernel log lines from FILE instead of journalctl/dmesg
  -n N      Limit output to N rows (default 20)

Exit codes: 0 ok, 1 usage error, 2 selftest failure.
EOF
}

# Extract OOM kill events from a kernel log read on stdin.
extract_events() {
  awk '
    /Out of memory: Killed process/ {
      pid = ""; name = ""; rss = "-"
      if (match($0, /Killed process [0-9]+ \([^)]+\)/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/Killed process /, "", s)
        pid = s; sub(/ .*/, "", pid)
        name = s; sub(/^[0-9]+ \(/, "", name); sub(/\)$/, "", name)
      }
      if (match($0, /anon-rss:[0-9]+kB/)) {
        rss = substr($0, RSTART + 9, RLENGTH - 11)
      }
      printf "%s %s %s | pid=%-7s | %-24s | rss=%s kB\n", $1, $2, $3, pid, name, rss
      total++
    }
    END {
      if (total > 0) printf "-- %d OOM kill event(s) --\n", total > "/dev/stderr"
    }
  '
}

kernel_log() {
  if [ -n "${SRC_FILE:-}" ]; then
    cat "$SRC_FILE" 2>/dev/null
  elif command -v journalctl >/dev/null 2>&1; then
    journalctl -k 2>/dev/null
  elif command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null
  fi
}

PASS=0
FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $3 (got '$1', want '$2')"
  fi
}

assert_match() {
  if printf '%s\n' "$1" | grep -q -- "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $3 (pattern '$2' not found)"
  fi
}

cmd_selftest() {
  local events n
  events=$(printf '%s\n' "$FIXTURE" | extract_events)
  n=$(printf '%s\n' "$events" | grep -c 'pid=' || true)
  assert_eq "$n" "3" "event count from fixture"
  assert_match "$events" 'pid=1234.*python3'  "python3 event parsed"
  assert_match "$events" 'pid=2048.*java'     "java event parsed"
  assert_match "$events" 'pid=777.*node'      "node event parsed"
  assert_match "$events" 'rss=1536000 kB'     "rss extraction"
  assert_match "$events" 'rss=3072000 kB'     "second rss extraction"
  assert_match "$events" 'Jun 4 10:40:11'     "timestamp kept"

  local top_out
  top_out=$(cmd_top)
  assert_match "$top_out" 'RSS' "top output has header"
  assert_eq "$?" "0" "top runs on this host"

  echo "selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 2
}

cmd_top() {
  local limit="${LIMIT:-20}"
  printf '%8s  %s\n' 'RSS(kB)' 'COMMAND'
  ps -axo rss=,comm= 2>/dev/null | sort -rn | head -n "$limit" \
    | awk '{ rss=$1; $1=""; sub(/^ +/, ""); printf "%8s  %s\n", rss, $0 }'
}

SRC_FILE=""
LIMIT="20"

CMD="${1:-}"
[ -n "$CMD" ] || { usage; exit 1; }
shift || true

while getopts "f:n:h" opt 2>/dev/null; do
  case "$opt" in
    f) SRC_FILE="$OPTARG" ;;
    n) LIMIT="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
# Re-parse remaining args manually (POSIX getopts ends at first non-option).
RESET_OPTIND=1

case "$CMD" in
  scan)
    if [ -z "$SRC_FILE" ] && ! command -v journalctl >/dev/null 2>&1 && ! command -v dmesg >/dev/null 2>&1; then
      echo "No kernel log source available on this host; use: $PROG scan -f FILE" >&2
      exit 0
    fi
    kernel_log | extract_events | head -n "$LIMIT"
    ;;
  top)
    cmd_top
    ;;
  selftest)
    cmd_selftest
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
