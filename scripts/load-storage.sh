#!/usr/bin/env bash
set -euo pipefail

# Simple, dependency-free load generator for the /storage endpoint.
# Uses multiple background curl workers to generate sustained traffic.
#
# Config via env vars (override with: make load-storage DURATION=120 CONCURRENCY=50):
# - DURATION: duration in seconds (default 60)
# - CONCURRENCY: number of parallel workers (default 20)
# - TIMEOUT: per-request timeout seconds (default 2)
# - SLEEP: sleep between requests in each worker, seconds (default 0)
# - HEADERS: optional additional curl -H headers (e.g. "-H 'Authorization: Bearer ...'")

URL="https://main-api.internal:8443/storage"
DURATION="${DURATION:-60}"
CONCURRENCY="${CONCURRENCY:-20}"
TIMEOUT="${TIMEOUT:-2}"
SLEEP="${SLEEP:-0}"
HEADERS=${HEADERS:-}
SUCCESS_RATE="${SUCCESS_RATE:-0.5}"

# Normalize DURATION if given like 60s
if [[ "$DURATION" =~ ^([0-9]+)s$ ]]; then
  DURATION="${BASH_REMATCH[1]}"
fi

echo "Load testing: $URL"
echo "  Duration:     ${DURATION}s"
echo "  Concurrency:  ${CONCURRENCY} workers"
echo "  Req timeout:  ${TIMEOUT}s"
echo "  Success rate: ${SUCCESS_RATE} (approx)"
[[ -n "$SLEEP" && "$SLEEP" != "0" ]] && echo "  Sleep/req:    ${SLEEP}s"
[[ -n "$HEADERS" ]] && echo "  Extra headers: ${HEADERS}"
echo ""
echo "Tip: watch HPA with: kubectl get hpa -n backend -w"
echo ""

end_time=$(( $(date +%s) + DURATION ))

worker() {
  local url="$1" timeout="$2" sleep_s="$3" headers="$4"
  while (( $(date +%s) < end_time )); do
    # Decide success vs failure based on SUCCESS_RATE
    qs=""
    if awk -v r="$RANDOM" -v p="$SUCCESS_RATE" 'BEGIN { exit (r/32767.0 <= p)?0:1 }'; then
      # success: include a valid filename
      local n=$RANDOM
      qs="?filename=file${n}.txt"
    else
      # failure: missing or empty filename
      if (( RANDOM % 2 == 0 )); then
        qs=""  # missing filename
      else
        qs="?filename="
      fi
    fi
    # -k to skip TLS verification (mkcert dev cert)
    # -sS for quiet output with errors shown; -o to discard body
    if ! eval curl -k -sS --max-time "$timeout" $headers -o /dev/null "${url}${qs}"; then
      : # ignore errors; goal is to generate load
    fi
    if [[ -n "$sleep_s" && "$sleep_s" != "0" ]]; then
      sleep "$sleep_s"
    fi
  done
}

pids=()
for _ in $(seq 1 "$CONCURRENCY"); do
  worker "$URL" "$TIMEOUT" "$SLEEP" "$HEADERS" &
  pids+=("$!")
done

trap 'for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done' INT TERM

for p in "${pids[@]}"; do
  wait "$p" || true
done

echo "Done."
