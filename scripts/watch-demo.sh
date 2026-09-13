#!/usr/bin/env bash
#
# Read-only live monitor for the demo. Polls the deployed agent API and prints
# a running status line. Safe to run during a recording: it never signs or
# sends anything, so it cannot interfere with the agent's own defense.
#
# Usage:  ./scripts/watch-demo.sh
#
set -uo pipefail

API="${AGENT_API:-https://lamplighter-agent.onrender.com}"
USER_ADDR=0x867b93045Ad26db454bEc0ecb52759Bb0126Ac50

printf '\033[1;33m  LAMPLIGHTER — live agent monitor\033[0m\n'
printf '  %s\n\n' "$API"

last=""
while true; do
  line=$(curl -s -m 20 "$API/api/vault/$USER_ADDR" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print('waiting for agent...'); raise SystemExit
hf=d['healthFactor']; floor=d['policy']['minHealthFactorBps']/10000
state='AT RISK' if hf<floor else 'HEALTHY'
print(f\"HF {hf:6.3f}  {state:<8}  debt \${d['debtUSDC']:<7} reserve \${d['balanceUSDC']:<6} price \${d['priceFeedUsd']:,}\")
" 2>/dev/null)

  [ -z "$line" ] && line="agent unreachable"

  ts=$(date +%H:%M:%S)
  case "$line" in
    *"AT RISK"*)  printf '  \033[0;31m%s  %s\033[0m\n' "$ts" "$line" ;;
    *HEALTHY*)    printf '  \033[0;32m%s  %s\033[0m\n' "$ts" "$line" ;;
    *)            printf '  \033[0;90m%s  %s\033[0m\n' "$ts" "$line" ;;
  esac

  # Surface new agent decisions as they land in the activity ring buffer.
  ev=$(curl -s -m 20 "$API/api/activity" 2>/dev/null | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
ev = d if isinstance(d,list) else d.get('data',[])
if ev:
    e=ev[0]
    print((e.get('kind') or e.get('type') or '') + '|' + (e.get('message') or '')[:78] + '|' + (e.get('txHash') or ''))
" 2>/dev/null)

  if [ -n "$ev" ] && [ "$ev" != "$last" ]; then
    kind="${ev%%|*}"; rest="${ev#*|}"; msg="${rest%%|*}"; tx="${rest##*|}"
    case "$kind" in
      defense_executed) printf '    \033[1;33m>> DEFENSE EXECUTED\033[0m %s\n' "$msg"
                        [ -n "$tx" ] && printf '    \033[0;36m   %s\033[0m\n' "https://testnet.arcscan.app/tx/$tx" ;;
      warning)          printf '    \033[0;33m>> %s\033[0m\n' "$msg" ;;
      no_action)        printf '    \033[0;90m>> %s\033[0m\n' "$msg" ;;
    esac
    last="$ev"
  fi

  sleep 4
done
