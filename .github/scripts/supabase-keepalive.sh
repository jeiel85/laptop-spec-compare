#!/usr/bin/env bash
# Supabase 무료 프로젝트 keep-alive.
# 1) Management API로 프로젝트 상태를 보고, 일시정지돼 있으면 복구를 요청한 뒤 다시 켜질 때까지 기다려요.
# 2) 켜져 있으면 keepalive_ping()으로 heartbeat 행을 갱신해요.
# 매일 핑을 보내도 Supabase가 활동으로 치지 않아 정지되는 일이 있어서(2026-10-30, 경고 2026-11-09) 복구 단계를 둬요.
#
# 필요한 환경 변수
#   SUPABASE_URL           https://<ref>.supabase.co
#   SUPABASE_KEY           공개용 키 (keepalive_ping 호출)
#   SUPABASE_ACCESS_TOKEN  Supabase 개인 액세스 토큰 (상태 조회·복구)
set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL 시크릿이 없어요}"
: "${SUPABASE_KEY:?SUPABASE_KEY 시크릿이 없어요}"
: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN 시크릿이 없어요. Supabase 대시보드 Account → Access Tokens에서 만들어 Actions 시크릿에 넣어 주세요}"

API="https://api.supabase.com/v1"
REF="$(printf '%s' "$SUPABASE_URL" | sed -E 's#^https?://([^.]+)\..*$#\1#')"
if [[ -z "$REF" || "$REF" == "$SUPABASE_URL" ]]; then
  echo "::error::SUPABASE_URL에서 프로젝트 ref를 읽지 못했어요"
  exit 1
fi

WAIT_LIMIT_SECONDS=1200   # 복구는 보통 몇 분 걸려요. 20분 넘게 안 켜지면 실패로 알려요
POLL_SECONDS=30

project_status() {
  curl -sSf "$API/projects/$REF" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" | jq -r '.status'
}

restore_requested=false
waited=0
while true; do
  status="$(project_status)"
  echo "프로젝트 상태: $status"
  case "$status" in
    ACTIVE_HEALTHY)
      break
      ;;
    INACTIVE)
      if [[ "$restore_requested" == false ]]; then
        echo "::warning::프로젝트가 일시정지돼 있어 복구를 요청해요"
        curl -sSf -X POST "$API/projects/$REF/restore" \
          -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -o /dev/null
        restore_requested=true
      fi
      ;;
    PAUSING|GOING_DOWN|RESTORING|COMING_UP|RESTARTING|UPGRADING|RESIZING|UNKNOWN|ACTIVE_UNHEALTHY)
      # 전환 중이에요. 정지가 끝나면 INACTIVE로 바뀌고 그때 복구를 요청해요
      ;;
    *)
      echo "::error::처리할 수 없는 프로젝트 상태예요: $status"
      exit 1
      ;;
  esac
  if (( waited >= WAIT_LIMIT_SECONDS )); then
    echo "::error::${WAIT_LIMIT_SECONDS}초 동안 프로젝트가 켜지지 않았어요 (마지막 상태: $status)"
    exit 1
  fi
  sleep "$POLL_SECONDS"
  waited=$(( waited + POLL_SECONDS ))
done

# 읽기만 해서는 일시정지를 막지 못했어요. 함수로 행 하나를 실제로 갱신해요
curl -sSf -X POST "$SUPABASE_URL/rest/v1/rpc/keepalive_ping" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'
echo
