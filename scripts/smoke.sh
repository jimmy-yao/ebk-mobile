#!/usr/bin/env bash
# ezBookkeeping API 冒烟 / 契约基线
#
# 用法:
#   cp .env.example .env      # 填 EBK_USER / EBK_PASS
#   ./scripts/smoke.sh        # 只读检查（默认）
#   ./scripts/smoke.sh --crud  # 额外跑写通路：账户 建→改→删、明细 记→读→改→转账→删
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
req POST /api/authorize.json "{\"loginName\":\"$EBK_USER\",\"password\":\"$EBK_PASS\"}"
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
# list.json 的 count 是 required（models.TransactionListByMaxTimeRequest），不带就 400
check "3e. 交易明细 GET /api/v1/transactions/list.json"            "/api/v1/transactions/list.json?count=10&with_count=true"
# by_month.json 的 year/month 是 required
NOW_YEAR="$(date +%Y)"; NOW_MONTH="$(date +%-m)"
check "3f. 按月明细 GET /api/v1/transactions/list/by_month.json"   "/api/v1/transactions/list/by_month.json?year=$NOW_YEAR&month=$NOW_MONTH"
check "3g. 统计 GET /api/v1/transactions/statistics.json"          "/api/v1/transactions/statistics.json"
check "3h. 趋势 GET /api/v1/transactions/statistics/trends.json"   "/api/v1/transactions/statistics/trends.json"
check "3i. 资产趋势 GET /api/v1/transactions/statistics/asset_trends.json" "/api/v1/transactions/statistics/asset_trends.json"
check "3j. 汇率 GET /api/v1/exchange_rates/latest.json"            "/api/v1/exchange_rates/latest.json"
check "3k. 数据统计 GET /api/v1/data/statistics.json"              "/api/v1/data/statistics.json"
check "3l. 版本 GET /api/v1/systems/version.json"                  "/api/v1/systems/version.json"

# ---------- 4. Q4: 明细列表的分页/时间参数（实测探测） ----------
# 基线必须带 count（required, 1..50）；逐个试其它参数看服务端是否接受
probe_param() { # probe_param <path> <param=value>
  req GET "$1&$2"
  local msg; msg="$(jget "d.get('errorMessage','')")"
  if ok_json; then printf '      %-32s -> 接受 (HTTP %s)\n' "$2" "$HTTP_CODE"; return 0; fi
  printf '      %-32s -> 拒绝 (HTTP %s %s)\n' "$2" "$HTTP_CODE" "$msg"; return 1
}
echo "   Q4 明细列表参数探测（list.json 基线 count=10；1=接受）:"
LIST_BASE="/api/v1/transactions/list.json?count=10&with_count=true"
probe_param "$LIST_BASE" "page=1"                 >/dev/null && PAGE_OK=1 || PAGE_OK=0
probe_param "$LIST_BASE" "count=20"               >/dev/null && CNT_OK=1  || CNT_OK=0
probe_param "$LIST_BASE" "max_time=1759286400"    >/dev/null && MAXT_OK=1 || MAXT_OK=0
probe_param "$LIST_BASE" "min_time=1756608000"    >/dev/null && MINT_OK=1 || MINT_OK=0
probe_param "$LIST_BASE" "keyword=test"           >/dev/null && KW_OK=1   || KW_OK=0
probe_param "$LIST_BASE" "type=3"                 >/dev/null && TYPE_OK=1 || TYPE_OK=0
probe_param "$LIST_BASE" "with_pictures=true"     >/dev/null && PIC_OK=1  || PIC_OK=0
probe_param "/api/v1/transactions/list/by_month.json?year=$NOW_YEAR&month=$NOW_MONTH" \
            "trim_account=true"                   >/dev/null && TRIM_OK=1 || TRIM_OK=0
Q4_DETAIL="list.json: page=$PAGE_OK count=$CNT_OK max_time=$MAXT_OK min_time=$MINT_OK keyword=$KW_OK type=$TYPE_OK with_pictures=$PIC_OK | by_month: trim_account=$TRIM_OK"
if [ "$PAGE_OK$CNT_OK" = "11" ]; then
  record "4. Q4 明细列表参数探测" 0 "$Q4_DETAIL"
else
  record "4. Q4 明细列表参数探测" 1 "$Q4_DETAIL"
fi

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
  # 字段取自 models.AccountCreateRequest：
  #   category 必填(1..9)、type 必填(1/2)、icon 是 "字符串化的 int64"、
  #   color 必须 6 位且**不带 #**、currency 3 位
  req POST /api/v1/accounts/add.json \
    "{\"name\":\"$NAME\",\"category\":1,\"type\":1,\"icon\":\"1\",\"iconType\":0,\"color\":\"3B7DD8\",\"currency\":\"CNY\",\"balance\":\"0\",\"comment\":\"smoke 临时账户\"}"
  AID="$(jget "d.get('result',{}).get('id','')")"
  if [ -n "$AID" ]; then
    record "8a. 建账户 POST /accounts/add.json" 0 "id=$AID"
    req POST /api/v1/accounts/modify.json \
      "{\"id\":\"$AID\",\"name\":\"$NAME-mod\",\"category\":1,\"icon\":\"1\",\"iconType\":0,\"color\":\"3B7DD8\"}"
    ok_json && record "8b. 改账户 POST /accounts/modify.json" 0 "HTTP $HTTP_CODE" \
            || record "8b. 改账户 POST /accounts/modify.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"

    # ---- 8d. 编辑时**不能**带 balance（AccountModifyRequest 一见该键就拒）----
    req POST /api/v1/accounts/modify.json \
      "{\"id\":\"$AID\",\"name\":\"$NAME-mod\",\"category\":1,\"icon\":\"1\",\"iconType\":0,\"color\":\"3B7DD8\",\"balance\":\"0\"}"
    MSG="$(jget "d.get('errorMessage','')")"
    if ! ok_json && [ "$MSG" = "not supported to modify account balance" ]; then
      record "8d. 改账户带 balance 应被拒" 0 "errorCode=$(jget "d.get('errorCode','')") $MSG"
    else
      record "8d. 改账户带 balance 应被拒" 1 "HTTP $HTTP_CODE $MSG"
    fi

    # ---- 8e. 新建带初始余额但缺 balanceTime → 应被拒 ----
    req POST /api/v1/accounts/add.json \
      "{\"name\":\"SMOKE-BAL-$TS\",\"category\":1,\"type\":1,\"icon\":\"1\",\"iconType\":0,\"color\":\"3B7DD8\",\"currency\":\"CNY\",\"balance\":\"500\",\"comment\":\"smoke 余额\"}"
    MSG="$(jget "d.get('errorMessage','')")"
    if ! ok_json && [ "$MSG" = "account balance time is not set" ]; then
      record "8e. 初始余额缺 balanceTime 应被拒" 0 "$MSG"
    else
      record "8e. 初始余额缺 balanceTime 应被拒" 1 "HTTP $HTTP_CODE $MSG"
    fi

    # ---- 8f. 补上 balanceTime → 建成，balance=500，用完即删 ----
    req POST /api/v1/accounts/add.json \
      "{\"name\":\"SMOKE-BAL-$TS\",\"category\":1,\"type\":1,\"icon\":\"1\",\"iconType\":0,\"color\":\"3B7DD8\",\"currency\":\"CNY\",\"balance\":\"500\",\"balanceTime\":$(date +%s),\"comment\":\"smoke 余额\"}"
    BALID="$(jget "d.get('result',{}).get('id','')")"
    if [ -n "$BALID" ]; then
      req GET /api/v1/accounts/list.json
      GOTBAL="$(python3 -c "
import json, sys
for a in json.load(open('$BODY_FILE'))['result']:
    if a['id'] == '$BALID':
        print(a['balance']); sys.exit()
print('NOTFOUND')
")"
      req POST /api/v1/accounts/delete.json "{\"id\":\"$BALID\"}"
      if [ "$GOTBAL" = "500" ] && ok_json; then
        record "8f. 初始余额+balanceTime" 0 "balance=$GOTBAL（最小单位），用完已删"
      else
        record "8f. 初始余额+balanceTime" 1 "balance=$GOTBAL delete=$(jget "d.get('errorMessage','')")"
      fi
    else
      record "8f. 初始余额+balanceTime" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
    fi

    # ---- 8g. hide.json：隐藏后 visible_only=true 的列表里看不到 ----
    req POST /api/v1/accounts/hide.json "{\"id\":\"$AID\",\"hidden\":true}"
    HIDE_OK=0; ok_json && HIDE_OK=1
    req GET "/api/v1/accounts/list.json?visible_only=true"
    HIDDEN_GONE="$(python3 -c "
import json, sys
ids = [a['id'] for a in json.load(open('$BODY_FILE'))['result']]
print('yes' if '$AID' not in ids else 'no')
")"
    req POST /api/v1/accounts/hide.json "{\"id\":\"$AID\",\"hidden\":false}"
    UNHIDE_OK=0; ok_json && UNHIDE_OK=1
    if [ "$HIDE_OK" = 1 ] && [ "$HIDDEN_GONE" = "yes" ] && [ "$UNHIDE_OK" = 1 ]; then
      record "8g. 隐藏/取消隐藏 accounts/hide.json" 0 "visible_only=true 时不可见，已恢复"
    else
      record "8g. 隐藏/取消隐藏 accounts/hide.json" 1 "hide=$HIDE_OK hidden_gone=$HIDDEN_GONE unhide=$UNHIDE_OK"
    fi

    # ---------- 9. 明细写通路（payload 与 App 记账表单 TxDraft 逐字段一致） ----------
    # 实测契约：
    #   * categoryId 必须是**子分类**：一级分类 → 206005、空串 → 200000、type 不符 → 206002
    #   * 转账也必须选 type=3 的子分类（不能省）
    #   * 金额=正数最小单位（服务端做 -Amount 扣减，见 services/transactions.go 余额累计）
    #   * 非转账 destinationAmount 必须为 0；同币种转账 src/dst 金额相等
    req GET /api/v1/transaction/categories/list.json
    CATS_BODY="$BODY_FILE"
    pick_sub_cat() { # pick_sub_cat <type:1|2|3> -> 第一个可用子分类 id
      python3 -c "
import json, sys
d = json.load(open('$CATS_BODY'))['result']
for p in d.get('$1', []):
    if p.get('hidden'):
        continue
    for c in p.get('subCategories', []):
        if not c.get('hidden'):
            print(c['id']); sys.exit()
"
    }
    ECAT="$(pick_sub_cat 2)"
    TCAT="$(pick_sub_cat 3)"

    if [ -z "$ECAT" ] || [ -z "$TCAT" ]; then
      record "9. 明细写通路（记账表单契约）" 1 "拿不到支出/转账子分类，无法继续"
    else
      # 转账目标账户
      req POST /api/v1/accounts/add.json \
        "{\"name\":\"SMOKE2-$TS\",\"category\":1,\"type\":1,\"icon\":\"1\",\"iconType\":0,\"color\":\"1F9D55\",\"currency\":\"CNY\",\"balance\":\"0\",\"comment\":\"smoke 临时账户2\"}"
      AID2="$(jget "d.get('result',{}).get('id','')")"
      TX_NOW="$(date +%s)"
      acct_bal() { # acct_bal <account_id> -> 余额字符串
        req GET /api/v1/accounts/list.json
        python3 -c "
import json, sys
for a in json.load(open('$BODY_FILE'))['result']:
    if a['id'] == '$1':
        print(a['balance']); sys.exit()
print('NOTFOUND')
"
      }

      # 9a. 记一笔支出（字段顺序与 TxDraft 一致）
      req POST /api/v1/transactions/add.json \
        "{\"type\":3,\"categoryId\":\"$ECAT\",\"time\":$TX_NOW,\"utcOffset\":480,\"sourceAccountId\":\"$AID\",\"destinationAccountId\":\"0\",\"sourceAmount\":1234,\"destinationAmount\":0,\"hideAmount\":false,\"tagIds\":[],\"pictureIds\":[],\"comment\":\"smoke 测试\"}"
      TXID="$(jget "d.get('result',{}).get('id','')")"
      if [ -n "$TXID" ]; then
        record "9a. 记一笔支出 POST /transactions/add.json" 0 "id=$TXID 金额=1234分"
      else
        record "9a. 记一笔支出 POST /transactions/add.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
        TXID=""
      fi

      if [ -n "$TXID" ]; then
      # 9b. 读回逐字段比对
      req GET "/api/v1/transactions/get.json?id=$TXID"
      TX_TYPE="$(jget "d.get('result',{}).get('type','')")"
      TX_AMT="$(jget "d.get('result',{}).get('sourceAmount','')")"
      TX_CMT="$(jget "d.get('result',{}).get('comment','')")"
      if [ "$TX_TYPE" = "3" ] && [ "$TX_AMT" = "1234" ] && [ "$TX_CMT" = "smoke 测试" ]; then
        record "9b. GET /transactions/get.json 字段一致" 0 "type=3 amount=1234 comment 中文原样"
      else
        record "9b. GET /transactions/get.json 字段一致" 1 "type=$TX_TYPE amount=$TX_AMT comment=$TX_CMT"
      fi

      # 9c. 余额符号：支出传**正数**，服务端扣减。
      #     注意 accounts/list.json 的 balance 是 **最小单位整数字符串**
      #     （models/account.go: Balance: utils.Int64ToString(a.Balance)），不是元。
      BAL="$(acct_bal "$AID")"
      if [ "$BAL" = "-1234" ]; then
        record "9c. 余额符号（支出金额为正数）" 0 "balance=$BAL（最小单位）"
      else
        record "9c. 余额符号（支出金额为正数）" 1 "期望 -1234，实际 $BAL"
      fi

      # 9d. 改明细（金额 1234 → 999，备注改写）
      req POST /api/v1/transactions/modify.json \
        "{\"id\":\"$TXID\",\"type\":3,\"categoryId\":\"$ECAT\",\"time\":$TX_NOW,\"utcOffset\":480,\"sourceAccountId\":\"$AID\",\"destinationAccountId\":\"0\",\"sourceAmount\":999,\"destinationAmount\":0,\"hideAmount\":false,\"tagIds\":[],\"pictureIds\":[],\"comment\":\"已修改\"}"
      MOD_OK=0; ok_json && MOD_OK=1
      req GET "/api/v1/transactions/get.json?id=$TXID"
      TX_CMT2="$(jget "d.get('result',{}).get('comment','')")"
      TX_AMT2="$(jget "d.get('result',{}).get('sourceAmount','')")"
      BAL2="$(acct_bal "$AID")"
      if [ "$MOD_OK" = 1 ] && [ "$TX_CMT2" = "已修改" ] && [ "$TX_AMT2" = "999" ] && [ "$BAL2" = "-999" ]; then
        record "9d. 改明细 POST /transactions/modify.json" 0 "amount=999 comment 已改，余额重算 $BAL2"
      else
        record "9d. 改明细 POST /transactions/modify.json" 1 "modify_ok=$MOD_OK amount=$TX_AMT2 comment=$TX_CMT2 balance=$BAL2"
      fi

      # 9e. 转账 A → B（同币种，src/dst 金额相等）：A=-999-500，B=+500
      if [ -n "$AID2" ]; then
        req POST /api/v1/transactions/add.json \
          "{\"type\":4,\"categoryId\":\"$TCAT\",\"time\":$TX_NOW,\"utcOffset\":480,\"sourceAccountId\":\"$AID\",\"destinationAccountId\":\"$AID2\",\"sourceAmount\":500,\"destinationAmount\":500,\"hideAmount\":false,\"tagIds\":[],\"pictureIds\":[],\"comment\":\"smoke 转账\"}"
        TXID2="$(jget "d.get('result',{}).get('id','')")"
        TXID2_ERR="$(jget "d.get('errorMessage','')")"
        BAL_A="$(acct_bal "$AID")"; BAL_B="$(acct_bal "$AID2")"
        if [ -n "$TXID2" ] && [ "$BAL_A" = "-1499" ] && [ "$BAL_B" = "500" ]; then
          record "9e. 转账 POST /add.json type=4" 0 "A=$BAL_A B=$BAL_B"
        else
          # 断言失败也不清空 TXID2：9f 必须能把它删掉，绝不留脏数据
          record "9e. 转账 POST /add.json type=4" 1 "err=$TXID2_ERR A=$BAL_A B=$BAL_B"
        fi
      else
        TXID2=""
        record "9e. 转账 POST /add.json type=4" 1 "转账目标账户没建起来"
      fi

      # 9f. 删除明细 + 临时账户 → 数据还原
      for id in "$TXID" "$TXID2"; do
        [ -z "$id" ] && continue
        req POST /api/v1/transactions/delete.json "{\"id\":\"$id\"}"
        ok_json || printf '      删除明细 %s 失败: %s\n' "$id" "$(jget "d.get('errorMessage','')")"
      done
      else
        TXID2=""
      fi
      # 无论 9a 是否成功，转账目标账户都要删掉，保证数据还原
      [ -n "$AID2" ] && req POST /api/v1/accounts/delete.json "{\"id\":\"$AID2\"}"
      BAL_A="$(acct_bal "$AID")"
      if [ "$BAL_A" = "0" ]; then
        record "9f. 删明细后余额还原" 0 "balance=$BAL_A（+临时账户已删）"
      else
        record "9f. 删明细后余额还原" 1 "期望 0，实际 $BAL_A"
      fi
    fi

    # ---------- 10. 分类 & 标签写契约（自建自删，跑完数据还原） ----------
    # 源码契约（pkg/api/transaction_categories.go）：
    #   * 只有两级：parentId 指向二级 → 206004 cannot add to secondary ...
    #   * modify 请求**没有 type 字段**；层级不可改（一级挂到二级 → 206007
    #     not allow to change primary category to secondary category）
    #   * 删除一级会连子分类一起软删；被明细引用 → 206006
    cat_in_list() { # cat_in_list <category_id> -> yes/no
      req GET /api/v1/transaction/categories/list.json
      python3 -c "
import json, sys
d = json.load(open('$BODY_FILE'))['result']
ids = set()
for group in d.values():
    for p in group:
        ids.add(p['id'])
        for c in p.get('subCategories', []):
            ids.add(c['id'])
print('yes' if '$1' in ids else 'no')
"
    }

    # 10a. 新建一级分类
    req POST /api/v1/transaction/categories/add.json \
      "{\"name\":\"SMOKE-一级-$TS\",\"type\":2,\"parentId\":\"0\",\"icon\":\"200\",\"iconType\":0,\"color\":\"E8A33D\",\"comment\":\"smoke\"}"
    CAT1="$(jget "d.get('result',{}).get('id','')")"
    if [ -n "$CAT1" ]; then
      record "10a. 建一级分类 categories/add.json" 0 "id=$CAT1（icon/parentId 均为字符串）"
    else
      record "10a. 建一级分类 categories/add.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
      CAT1=""
    fi

    # 10b. 新建二级分类（parentId = 一级 id）
    if [ -n "$CAT1" ]; then
      req POST /api/v1/transaction/categories/add.json \
        "{\"name\":\"SMOKE-二级-$TS\",\"type\":2,\"parentId\":\"$CAT1\",\"icon\":\"210\",\"iconType\":0,\"color\":\"2F9E44\"}"
      CAT2="$(jget "d.get('result',{}).get('id','')")"
      if [ -n "$CAT2" ]; then
        record "10b. 建二级分类 parentId=一级" 0 "id=$CAT2"
      else
        record "10b. 建二级分类 parentId=一级" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
        CAT2=""
      fi
    else
      CAT2=""
      record "10b. 建二级分类 parentId=一级" -1 "10a 没建成"
    fi

    # 10c. 三级分类必须被拒
    if [ -n "$CAT2" ]; then
      req POST /api/v1/transaction/categories/add.json \
        "{\"name\":\"SMOKE-三级-$TS\",\"type\":2,\"parentId\":\"$CAT2\",\"icon\":\"300\",\"iconType\":0,\"color\":\"3B7DD8\"}"
      MSG="$(jget "d.get('errorMessage','')")"
      if ! ok_json && [ "$MSG" = "cannot add to secondary transaction category" ]; then
        record "10c. 三级分类应被拒" 0 "$MSG"
      else
        record "10c. 三级分类应被拒" 1 "HTTP $HTTP_CODE $MSG"
      fi
    else
      record "10c. 三级分类应被拒" -1 "10b 没建成"
    fi

    # 10d. 改层级：把一级挂到二级下面 → 应被拒
    if [ -n "$CAT1" ] && [ -n "$CAT2" ]; then
      req POST /api/v1/transaction/categories/modify.json \
        "{\"id\":\"$CAT1\",\"name\":\"SMOKE-一级-$TS\",\"parentId\":\"$CAT2\",\"icon\":\"200\",\"iconType\":0,\"color\":\"E8A33D\",\"comment\":\"\"}"
      MSG="$(jget "d.get('errorMessage','')")"
      if ! ok_json && [ "$MSG" = "not allow to change primary category to secondary category" ]; then
        record "10d. 一级改挂到二级应被拒" 0 "$MSG"
      else
        record "10d. 一级改挂到二级应被拒" 1 "HTTP $HTTP_CODE $MSG"
      fi
    else
      record "10d. 一级改挂到二级应被拒" -1 "前置未建成"
    fi

    # 10e. 正常改名（modify 请求体**不带 type**，类型不可改）
    if [ -n "$CAT1" ]; then
      req POST /api/v1/transaction/categories/modify.json \
        "{\"id\":\"$CAT1\",\"name\":\"SMOKE-改名-$TS\",\"parentId\":\"0\",\"icon\":\"200\",\"iconType\":0,\"color\":\"E8A33D\",\"comment\":\"smoke 改\"}"
      NEW_NAME="$(jget "d.get('result',{}).get('name','')")"
      if ok_json && [ "$NEW_NAME" = "SMOKE-改名-$TS" ]; then
        record "10e. 改名 categories/modify.json" 0 "name=$NEW_NAME"
      else
        record "10e. 改名 categories/modify.json" 1 "HTTP $HTTP_CODE name=$NEW_NAME $(jget "d.get('errorMessage','')")"
      fi
    else
      record "10e. 改名 categories/modify.json" -1 "10a 没建成"
    fi

    # 10f/10g. 被明细引用的分类删不掉；删掉明细后才删得掉，账户余额随之复原
    CAT3=""
    if [ -n "$CAT1" ]; then
      req POST /api/v1/transaction/categories/add.json \
        "{\"name\":\"SMOKE-被引用-$TS\",\"type\":2,\"parentId\":\"$CAT1\",\"icon\":\"310\",\"iconType\":0,\"color\":\"16A2AE\"}"
      CAT3="$(jget "d.get('result',{}).get('id','')")"
    fi
    TX3=""
    if [ -n "$CAT3" ]; then
      req POST /api/v1/transactions/add.json \
        "{\"type\":3,\"categoryId\":\"$CAT3\",\"time\":$(date +%s),\"utcOffset\":480,\"sourceAccountId\":\"$AID\",\"destinationAccountId\":\"0\",\"sourceAmount\":100,\"destinationAmount\":0,\"hideAmount\":false,\"tagIds\":[],\"pictureIds\":[],\"comment\":\"smoke 引用分类\"}"
      TX3="$(jget "d.get('result',{}).get('id','')")"

      req POST /api/v1/transaction/categories/delete.json "{\"id\":\"$CAT3\"}"
      MSG="$(jget "d.get('errorMessage','')")"
      if ! ok_json && [ "$MSG" = "transaction category is in use and cannot be deleted" ]; then
        record "10f. 被引用分类删除应被拒" 0 "$MSG"
      else
        record "10f. 被引用分类删除应被拒" 1 "HTTP $HTTP_CODE $MSG"
      fi

      [ -n "$TX3" ] && req POST /api/v1/transactions/delete.json "{\"id\":\"$TX3\"}"
      req POST /api/v1/transaction/categories/delete.json "{\"id\":\"$CAT3\"}"
      DEL_OK=0; ok_json && DEL_OK=1
      GONE="$(cat_in_list "$CAT3")"
      BAL_BACK="$(acct_bal "$AID")"
      if [ "$DEL_OK" = 1 ] && [ "$GONE" = "no" ] && [ "$BAL_BACK" = "0" ]; then
        record "10g. 删分类 + 余额复原" 0 "列表已查不到，balance=$BAL_BACK"
      else
        record "10g. 删分类 + 余额复原" 1 "del=$DEL_OK gone=$GONE balance=$BAL_BACK"
      fi
    else
      record "10f. 被引用分类删除应被拒" -1 "前置未建成"
      record "10g. 删分类 + 余额复原" -1 "前置未建成"
    fi

    # 10h. 删除一级 → 连子分类一起消失
    if [ -n "$CAT1" ] && [ -n "$CAT2" ]; then
      req POST /api/v1/transaction/categories/delete.json "{\"id\":\"$CAT1\"}"
      DEL_OK=0; ok_json && DEL_OK=1
      G1="$(cat_in_list "$CAT1")"
      G2="$(cat_in_list "$CAT2")"
      if [ "$DEL_OK" = 1 ] && [ "$G1" = "no" ] && [ "$G2" = "no" ]; then
        record "10h. 删一级连子分类一起删" 0 "一级/二级都已从列表消失"
      else
        record "10h. 删一级连子分类一起删" 1 "del=$DEL_OK one=$G1 two=$G2"
      fi
    else
      record "10h. 删一级连子分类一起删" -1 "前置未建成"
    fi

    # 10i. 标签 增 → 改名 → 隐藏 → 删
    req POST /api/v1/transaction/tags/add.json \
      "{\"groupId\":\"0\",\"name\":\"SMOKE-标签-$TS\"}"
    TAG="$(jget "d.get('result',{}).get('id','')")"
    if [ -n "$TAG" ]; then
      req POST /api/v1/transaction/tags/modify.json \
        "{\"id\":\"$TAG\",\"groupId\":\"0\",\"name\":\"SMOKE-标签2-$TS\"}"
      M_OK=0; ok_json && M_OK=1
      req POST /api/v1/transaction/tags/hide.json "{\"id\":\"$TAG\",\"hidden\":true}"
      H_OK=0; ok_json && H_OK=1
      req GET /api/v1/transaction/tags/list.json
      TAG_STATE="$(python3 -c "
import json, sys
for t in json.load(open('$BODY_FILE'))['result']:
    if t['id'] == '$TAG':
        print(t.get('name', '') + '|' + ('true' if t.get('hidden') else 'false'))
        sys.exit()
print('NOTFOUND')
")"
      req POST /api/v1/transaction/tags/delete.json "{\"id\":\"$TAG\"}"
      D_OK=0; ok_json && D_OK=1
      if [ "$M_OK" = 1 ] && [ "$H_OK" = 1 ] && [ "$TAG_STATE" = "SMOKE-标签2-$TS|true" ] && [ "$D_OK" = 1 ]; then
        record "10i. 标签 增→改→隐藏→删" 0 "改名+hidden=true 生效，已删除"
      else
        record "10i. 标签 增→改→隐藏→删" 1 "modify=$M_OK hide=$H_OK state=$TAG_STATE delete=$D_OK"
      fi
    else
      record "10i. 标签 增→改→隐藏→删" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"
    fi
    req POST /api/v1/accounts/delete.json "{\"id\":\"$AID\"}"
    ok_json && record "8c. 删账户 POST /accounts/delete.json" 0 "HTTP $HTTP_CODE（数据已还原）" \
            || record "8c. 删账户 POST /accounts/delete.json" 1 "HTTP $HTTP_CODE $(jget "d.get('errorMessage','')")"

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
