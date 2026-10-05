# ezBookkeeping Flutter 客户端（ebk_mobile）

Android 优先的 ezBookkeeping 原生客户端。方案与路线见
`/root/ezbookkeeping-flutter-solution.md`（Phase 0/1 计划、Phase 划分、决策记录）。

## 目录结构

```
lib/
├── main.dart                # ProviderScope + TokenStore 预热
├── app/                     # MaterialApp、GoRouter（登录态 redirect）、主题
├── core/
│   ├── network/api_client.dart   # Dio + 信封解包 + 401 踢出
│   ├── storage/token_store.dart  # token → Keystore/Keychain，驱动路由
│   ├── error/app_exception.dart  # 服务端 {success:false,...} 映射
│   └── util/money.dart           # int64 最小单位 ↔ 展示金额
├── data/
│   ├── dto/                 # 手写 fromJson（零代码生成）
│   └── repositories/        # auth / account / transaction / version
└── features/                # auth、home、transactions、accounts、settings、shell

scripts/smoke.sh             # API 契约冒烟（服务端升级后先跑它）
.github/workflows/ci.yml     # analyze + test + build apk + 可选线上冒烟
```

## 契约要点（已从源码核实，smoke.sh 会实测复核）

| 事项 | 结论 |
| --- | --- |
| 成功/失败信封 | `{success:true, result}` / `{success:false, errorCode, errorMessage, path}` |
| API 鉴权 | `/api/v1/*` **只认** `Authorization: bearer` header |
| 图片鉴权 | `/avatar|/pictures|/icons` **只认 `?token=`**，且只接受 session token（API Token 不行） |
| 时区 | 必带 `X-Timezone-Offset`（分钟，东向为正，UTC+8 → 480） |
| 金额 | `int64` 最小单位（分）；账户 `balance` 是已格式化十进制字符串 |
| id | `int64` 序列化成**字符串** |
| 交易类型 | 1 调整余额 / 2 收入 / 3 支出 / 4 转账 |
| 按月明细 | `list/by_month.json` 必填 `year`、`month` |

## 本地开发（arm64 容器，不污染宿主机）

```bash
alias febk='docker run --rm -it -v "$PWD":/work -v ebk_pub_cache:/root/.pub-cache \
  -v ebk_gradle_cache:/root/.gradle -w /work \
  -e PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  ebk-flutter'

febk flutter analyze
febk flutter test
febk flutter build apk --release
```

镜像 `ebk-flutter` 由 `/root/ebk-apk/Dockerfile.flutter` 构建（Flutter 3.47.6 stable，arm64 原生）。

> **release 出包走 CI**：本机 arm64 的 `gen_snapshot` 只有 x64 版，qemu-user 跑真实 AOT 会崩
> （`flutter build apk --release` → `AOT snapshotter exited with code -11`），所以
> `analyze` / `test` / `build apk --debug` 在本机跑，**`--release` 交给 GitHub Actions**
> （`.github/workflows/ci.yml`，已实测通过，产物在 run 的 artifact 里）。详见方案文档 §7.1。

## 签名

- keystore：`/root/ebk-apk/ezbookkeeping.keystore`（alias `ebk`，有效期到 2054）
- 与 TWA APK **同一签名证书、不同包名**（`org.hapi.ezbookkeeping.mobile`），可共存
- CI 通过 Secrets `ANDROID_KEYSTORE_B64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS`
  解出 `android/key.properties` + keystore 后用 release 签名；本地无此文件时回退 debug 签名

## 服务端契约冒烟

```bash
cp .env.example .env    # 填 EBK_USER / EBK_PASS
./scripts/smoke.sh      # 只读检查；--crud 会建/改/删一个测试账户
```
