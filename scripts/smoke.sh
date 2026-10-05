#!/usr/bin/env bash
# ezBookkeeping API 冒烟 / 契约基线
#
# 用法:
#   cp .env.example .env      # 填 EBK_USER / EBK_PASS
#   ./scripts/smoke.sh        # 只读检查（默认）
#   ./scripts/smoke.sh --crud  # 额外跑"建账户→改→删"的写操作
#
# 退出码: 0 = 全部通过; 1 = 有 FAIL; 2 = 前置条件不满足
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
[ -f "$ROOT_DIR/.env" ] && . "$ROOT_DIR/.env"

EBK_BASE_URL="${EBK_BASE_URL:-https://ezbook.hapi.dpdns.org}"
EBK_USER="${EBK_USER:-}"
EBK_PASS="${EBK_PASS:-}"
EBK_2FA_PASSCODE="${EBK_2FA_PASSCODE:-}"
RUN_CRUD=0
[ "${1:-}" = "--crud" ] && RUN_CRUD=1

WORKDIR="$(mktemp -d /tmp/ebk-smoke.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
TOKEN=""
PASS=0; FAIL=0; SKIP=0
declare -a REPORT=()

# ---------- helpers ----------
c_ok=$'\033[32m'; c_bad=$'\033[31m'; c_skip=$'\033[33m'; c_off=$'\033[0m'
[ -t 1 ] || { c_ok=""; c_bad=""; c_skip=""; c_off=""; }

record() { # record <name> <0|1|-1> <detail>
  local name="$1" rc="$2" detail="$3" plain color
  case "$rc" in
    0)  plain="PASS"; color="$c_ok";  PASS=$((PASS+1)) ;;
    -1) plain="SKIP"; color="$c_skip"; SKIP=$((SKIP+1)) ;;
    *)  plain="FAIL"; color="$c_bad"; FAIL=$((FAIL+1)) ;;
  esac
  printf '%-5s %-46s %s\n' "[${color}${plain}${c_off}]" "$name" "$detail"
  REPORT+=("$(printf '%-4s | %-46s | %s' "$plain" "$name" "$detail")")
}

# req <METHOD> <PATH_WITH_QUERY> [json_body] -> 全局 HTTP_CODE / BODY_FILE
req() {
  local method="$1" path="$2" body="${3:-}"
  local -a args=(-sS -X "$method" -o "$WORKDIR/body" -w '%{http_code}'
                 -H 'Accept: application/json'
                 -H 'Accept-Language: zh-CN'
                 -H 'X-Timezone-Name: Asia/Shanghai')
  [ -n "$TOKEN" ] && args+=(-H "Authorization: Bearer $TOKEN")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' --data "$body")
  HTTP_CODE=$(curl "${args[@]}" --connect-timeout 10 --max-time 30 "$EBK_BASE_URL$path" 2>"$WORKDIR/err")
  BODY_FILE="$WORKDIR/body"
  [ -z "$HTTP_CODE" ] && HTTP_CODE=000
}

jget() { # jget <py-expr over dict d>  (reads $BODY_FILE)
  python3 -c "
import json,sys
try:
    d=json.load(open('$BODY_FILE'))
except Exception as e:
    print(''); sys.exit(0)
v=$1
print('' if v is None else v)
" 2>/dev/null
}

ok_json() { # 断言 HTTP 2xx 且 success==true
  local code_ok=0 json_ok=0
  [[ "$HTTP_CODE" =~ ^2 ]] && code_ok=1
  [ "$(jget "d.get('success')")" = "True" ] && json_ok=1
  [ "$code_ok" = 1 ] && [ "$json_ok" = 1 ]
}

# ---------- 0. 连通性 ----------
echo "== ezBookkeeping API 冒烟 =="
echo "   目标: $EBK_BASE_URL"
req GET /healthz.json
if [ "$HTTP_CODE" != 200 ]; then
  record "0. 健康检查 /healthz.json" 1 "HTTP $HTTP_CODE — 服务不可达"
  exit 2
fi
SRV_VERSION="$(jget "d.get('result',{}).get('version','')")"
record "0. 健康检查 /healthz.json" 0 "version=$SRV_VERSION"

if [ -z "$EBK_USER" ] || [ -z "$EBK_PASS" ]; then
  echo
  echo "${c_skip}缺少 EBK_USER / EBK_PASS — 请复制 .env.example 为 .env 并填写${c_off}"
  exit 2
fi

# ---------- 1. 登录 ----------
req POST /api/authorize.json "{\"username\":\"$EBK_USER\",\"password\":\"$EBK_PASS\"}"
TOKEN="$(jget "d.get('result',{}).get('token','')")"
NEED_2FA="$(jget "d.get('result',{}).get('need2FA')")"
if [ "$NEED_2FA" = "True" ]; then
  # 第一步返回的 token 是 REQUIRE_2FA 类型，作为 header 传给 2fa 接口（JWTTwoFactorAuthorization 走 header）
  if [ -z "$EBK_2FA_PASSCODE" ]; then
    record "1. 登录 POST /api/authorize.json" -1 "账号开了 2FA，需设置 EBK_2FA_PASSCODE"
    echo "   ${c_skip}缺少 EBK_2FA_PASSCODE — 已跳过后续鉴权接口${c_off}"
    printf '%s\n' "${REPORT[@]}"; exit 2
  fi
  TOKEN="$(jget "d.get('result',{}).get('token','')")"
  req POST /api/2fa/authorize.json "{\"passcode\":\"$EBK_2FA_PASSCODE\"}"
  TOKEN="$(jget "d.get('result',{}).get('token','')")"
  if [ -n "$TOKEN" ]; then
    record "1b. 2FA POST /api/2fa/authorize.json" 0 "passcode 校验通过，拿到正式 token"
  else
    record "1b. 2FA POST /api/2fa/authorize.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
    printf '%s\n' "${REPORT[@]}"; exit 2
  fi
elif [ -n "$TOKEN" ]; then
  record "1. 登录 POST /api/authorize.json" 0 "拿到 session token（need2FA=False）"
else
  record "1. 登录 POST /api/authorize.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
  echo
  printf '%s\n' "${REPORT[@]}"
  exit 2
fi

# ---------- 2. Q1: header 鉴权是否可用 ----------
req GET /api/v1/accounts/list.json
ok_json && record "2. Q1 header鉴权 GET /api/v1/accounts/list.json" 0 "HTTP $HTTP_CODE success=true" \
        || record "2. Q1 header鉴权 GET /api/v1/accounts/list.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
ACCOUNT_COUNT="$(jget "len(d.get('result') or [])")"

# ---------- 3. 读接口矩阵 ----------
check() { # check <name> <path>
  req GET "$2"
  ok_json && record "$1" 0 "HTTP $HTTP_CODE" || record "$1" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
}
check "3a. 分类列表 GET /api/v1/transaction/categories/list.json" "/api/v1/transaction/categories/list.json"
check "3b. 标签列表 GET /api/v1/transaction/tags/list.json"        "/api/v1/transaction/tags/list.json"
check "3c. 标签组列表 GET /api/v1/transaction/tags/groups/list.json" "/api/v1/transaction/tags/groups/list.json"
check "3d. 交易计数 GET /api/v1/transactions/count.json"           "/api/v1/transactions/count.json"
check "3e. 交易明细 GET /api/v1/transactions/list.json"            "/api/v1/transactions/list.json"
check "3f. 按月明细 GET /api/v1/transactions/list/by_month.json"   "/api/v1/transactions/list/by_month.json"
check "3g. 统计 GET /api/v1/transactions/statistics.json"          "/api/v1/transactions/statistics.json"
check "3h. 趋势 GET /api/v1/transactions/statistics/trends.json"   "/api/v1/transactions/statistics/trends.json"
check "3i. 资产趋势 GET /api/v1/transactions/statistics/asset_trends.json" "/api/v1/transactions/statistics/asset_trends.json"
check "3j. 汇率 GET /api/v1/exchange_rates/latest.json"            "/api/v1/exchange_rates/latest.json"
check "3k. 数据统计 GET /api/v1/data/statistics.json"              "/api/v1/data/statistics.json"
check "3l. 版本 GET /api/v1/systems/version.json"                  "/api/v1/systems/version.json"

# ---------- 4. Q4: 明细列表的分页/时间参数（实测探测） ----------
probe_param() { # probe_param <param=value>
  req GET "/api/v1/transactions/list.json?$1"
  local msg; msg="$(jget "d.get('errorMessage','')")"
  if ok_json; then printf '      %-28s -> 接受 (HTTP %s)\n' "$1" "$HTTP_CODE"; return 0; fi
  printf '      %-28s -> 拒绝 (HTTP %s %s)\n' "$1" "$HTTP_CODE" "$msg"; return 1
}
echo "   Q4 明细列表参数探测（用于定 DTO 的 query 字段）:"
probe_param "page=1"        >/dev/null && PAGE_OK=1 || PAGE_OK=0
probe_param "page_size=5"   >/dev/null && PSIZE_OK=1 || PSIZE_OK=0
probe_param "start_time=1756608000" >/dev/null && STIME_OK=1 || STIME_OK=0
probe_param "end_time=1759286400"   >/dev/null && ETIME_OK=1 || ETIME_OK=0
probe_param "time_range=month"      >/dev/null && TRANGE_OK=1 || TRANGE_OK=0
Q4_DETAIL="page=$PAGE_OK page_size=$PSIZE_OK start_time=$STIME_OK end_time=$ETIME_OK time_range=$TRANGE_OK"
[ "$PAGE_OK$PSIZE_OK$STIME_OK$ETIME_OK" = "0000" ] \
  && record "4. Q4 明细列表参数探测" -1 "$Q4_DETAIL（全被拒，需查 models 绑定字段）" \
  || record "4. Q4 明细列表参数探测" 0 "$Q4_DETAIL（1=接受）"

# ---------- 5. Q2: 鉴权失败的错误形态 ----------
SAVE_TOKEN="$TOKEN"; TOKEN="invalid-token-for-smoke"
req GET /api/v1/accounts/list.json
CODE2="$HTTP_CODE"; BODY2="$(cat "$BODY_FILE")"
TOKEN="$SAVE_TOKEN"
ERRCODE="$(jget "d.get('errorCode','')")"
ERRMSG="$(jget "d.get('errorMessage','')")"
[ "$CODE2" = 401 ] && record "5. Q2 未授权错误形态" 0 "HTTP 401 errorCode=$ERRCODE msg=$ERRMSG" \
                   || record "5. Q2 未授权错误形态" 1 "HTTP $CODE2 body=$BODY2"

# ---------- 6. Q3: 图片鉴权只认 query token ----------
# 已知: /avatar|/pictures|/icons 用 JWTAuthorizationByQueryString (TOKEN_SOURCE_TYPE_ARGUMENT)
img_probe() { # img_probe <name> <path>
  local path="$1"
  # 6a: 不带任何 token
  local save="$TOKEN"; TOKEN=""
  local -a a=(-sS -o "$WORKDIR/img1" -w '%{http_code}' --connect-timeout 10 --max-time 20)
  local c1; c1=$(curl "${a[@]}" "$EBK_BASE_URL$path")
  # 6b: 只带 header（预期失败 → 证明 header 不通）
  local -a b=(-sS -o "$WORKDIR/img2" -w '%{http_code}' -H "Authorization: Bearer $save" --connect-timeout 10 --max-time 20)
  local c2; c2=$(curl "${b[@]}" "$EBK_BASE_URL$path")
  # 6c: 带 query token（预期通过鉴权 → 不再是 "token is empty"）
  local sep='?'; [[ "$path" == *\?* ]] && sep='&'
  local -a d=(-sS -o "$WORKDIR/img3" -w '%{http_code}' --connect-timeout 10 --max-time 20)
  local c3; c3=$(curl "${d[@]}" "$EBK_BASE_URL$path${sep}token=$save")
  TOKEN="$save"
  local m1 m3; m1=$(head -c 200 "$WORKDIR/img1"); m3=$(head -c 200 "$WORKDIR/img3")
  echo "      $path"
  echo "        无token=$c1 | header=$c2 | ?token=$c3"
  echo "        无token响应: $(echo "$m1" | tr -d '\n' | cut -c1-80)"
  echo "        ?token响应:  $(echo "$m3" | tr -d '\n' | cut -c1-80)"
  if [ "$c2" != 200 ] && { [ "$c3" = 200 ] || [ "$c3" = 404 ] || [ "$c3" = 400 ]; }; then
    return 0
  fi
  return 1
}
echo "   Q3 图片鉴权通路（header vs ?token）:"
if img_probe "/avatar/__smoke_nonexistent__.png"; then
  record "6. Q3 图片鉴权只认 query token" 0 "header 不通、?token 通 → 图片必须拼 token 参数"
else
  record "6. Q3 图片鉴权只认 query token" 1 "结果与预期不符，见上方探测输出"
fi
# 图片 token 是否为 API Token 类型可用（源码 allowedAPIToken=false，此处仅记录 session token 结果）
record "6b. 图片仅接受 session token（源码 allowedAPIToken=false）" -1 "源码结论，非运行时断言"

# ---------- 7. 导出 ----------
req GET "/api/v1/data/export.csv"
if [[ "$HTTP_CODE" =~ ^2 ]] && [ -s "$BODY_FILE" ]; then
  record "7. 导出 GET /api/v1/data/export.csv" 0 "HTTP $HTTP_CODE, $(wc -c <"$BODY_FILE") bytes"
else
  record "7. 导出 GET /api/v1/data/export.csv" 1 "HTTP $HTTP_CODE"
fi

# ---------- 8. 可选写操作 ----------
if [ "$RUN_CRUD" = 1 ]; then
  TS=$(date +%s)
  NAME="SMOKE-$TS"
  req POST /api/v1/accounts/add.json \
    "{\"name\":\"$NAME\",\"type\":1,\"currency\":\"CNY\",\"icon\":\"wallet\",\"color\":\"#3B7DD8\",\"sort\":9999}"
  AID="$(jget "d.get('result',{}).get('id','')")"
  if [ -n "$AID" ]; then
    record "8a. 建账户 POST /accounts/add.json" 0 "id=$AID"
    req POST /api/v1/accounts/modify.json "{\"id\":\"$AID\",\"name\":\"$NAME-mod\",\"type\":1,\"currency\":\"CNY\",\"icon\":\"wallet\",\"color\":\"#3B7DD8\",\"sort\":9999}"
    ok_json && record "8b. 改账户 POST /accounts/modify.json" 0 "HTTP $HTTP_CODE" \
            || record "8b. 改账户 POST /accounts/modify.json" 1 "HTTP $HTTP_CODE"
    req POST /api/v1/accounts/delete.json "{\"id\":\"$AID\"}"
    ok_json && record "8c. 删账户 POST /accounts/delete.json" 0 "HTTP $HTTP_CODE（数据已还原）" \
            || record "8c. 删账户 POST /accounts/delete.json" 1 "HTTP $HTTP_CODE"
  else
    record "8a. 建账户 POST /accounts/add.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
  fi
else
  record "8. 写操作（加 --crud 才跑）" -1 "未执行"
fi

# ---------- 汇总 ----------
echo
echo "===== 契约基线汇总 ====="
printf '%s\n' "${REPORT[@]}"
echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP  |  服务器版本: $SRV_VERSION  |  账户数: ${ACCOUNT_COUNT:-?}"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
