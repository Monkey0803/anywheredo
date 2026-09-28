# 发布流程（维护者）

## 一次性准备：固定的签名证书

**为什么必须用固定证书**：macOS 的 TCC（辅助功能授权）按代码签名的
designated requirement 认人。

| 签名方式 | designated requirement | 升级后的后果 |
| --- | --- | --- |
| ad-hoc（`codesign -s -`） | `cdhash H"…"` | 代码一变 cdhash 就变 → **每次升级用户都要重新授权** |
| 固定证书 | `identifier "dev.anywheredo.app" and certificate root = H"…"` | 跨版本稳定 → 授权一次长期有效 |

生成（只需一次）：

```bash
./scripts/make_signing_cert.sh            # 产出到 ~/Desktop/anywheredo-signing/
```

产出三个文件，**必须备份**（丢了就要换证书，而换证书 = 让所有用户重新授权一次）：

| 文件 | 用途 |
| --- | --- |
| `anywheredo-signing.p12` | 证书 + 私钥，导入用；同时存进 CI secret |
| `anywheredo-signing.txt` | p12 密码与证书 SHA-1 |
| `anywheredo-signing.cert.pem` | 只有公钥，可以公开 |

导入到独立钥匙串（不动登录钥匙串，也不改钥匙串搜索列表）：

```bash
./scripts/import_signing_cert.sh ~/Desktop/anywheredo-signing/anywheredo-signing.p12 '<p12密码>'
```

存进 CI（发布工作流用）：

```bash
base64 -i ~/Desktop/anywheredo-signing/anywheredo-signing.p12 | tr -d '\n' \
  | gh secret set SIGNING_P12_BASE64 --repo Monkey0803/anywheredo
gh secret set SIGNING_P12_PASSWORD --body '<p12密码>' --repo Monkey0803/anywheredo
```

## 打一个版本

一条命令（构建 → 签名 → 校验 → 打包 → 建 Release → 更新 tap）：

```bash
# 1. 改版本号：唯一来源是 Sources/AnywhereDoCore/Version.swift 的 marketing
#    （构建时会注入 App 的 Info.plist，CI 会断言三处一致）

# 2. 先干跑一遍，它会构建、签名、校验、打包，但不动 git、不发 Release
SIGNING_IDENTITY="AnywhereDo Signing" \
SIGNING_KEYCHAIN="$HOME/Library/Keychains/anywheredo-signing.keychain-db" \
./scripts/release.sh --dry-run

# 3. 确认无误后正式发版
SIGNING_IDENTITY="AnywhereDo Signing" \
SIGNING_KEYCHAIN="$HOME/Library/Keychains/anywheredo-signing.keychain-db" \
./scripts/release.sh
```

脚本会替你拦住这些情况：工作区不干净、不在 main、与远端不一致、tag 已存在、
包内版本号与 `Version.swift` 不一致、缺架构、**签名 requirement 含 cdhash**、缺本地化资源。

正式发版时它会：

1. 建 tag 与 GitHub Release，上传 `AnywhereDo-<版本>-universal.zip`
2. clone tap 仓库，把 `Casks/anywheredo.rb` 的 `version` 与 `sha256` 改成新值并推送

### 发版后的自动校验

`.github/workflows/release-verify.yml` 会在每次 Release 发布后（以及每周一）把附件**真的下载下来**重验：

- 包内版本号 == Release 标签
- `lipo` 同时含 `x86_64` 与 `arm64`
- `codesign --verify` 通过，且 designated requirement **不含 cdhash**
- 本地化资源 bundle 存在
- 附件的 sha256 与 tap cask 里写的一致（防止「发了新版但 tap 还指着旧包」）

> v1.0.0 是 ad-hoc 签名、也没有本地化资源，所以这个检查对它是**预期失败**的；
> 从第一个证书签名的版本开始才应该全绿。

### 手工做法（脚本出问题时的退路）

```bash
UNIVERSAL=1 ./scripts/build_app.sh
codesign -d -r- build/AnywhereDo.app      # 必须不含 cdhash
ditto -c -k --keepParent build/AnywhereDo.app /tmp/AnywhereDo-<版本>-universal.zip
shasum -a 256 /tmp/AnywhereDo-<版本>-universal.zip
gh release create v<版本> /tmp/AnywhereDo-<版本>-universal.zip --title "AnywhereDo <版本>" --notes-file …
# 然后手动改 tap 的 version / sha256 并推送
```

## 发布前检查清单

- [ ] `swift test` 全绿（CI 也会跑）
- [ ] `codesign -d -r- build/AnywhereDo.app` 输出**不含** `cdhash` ← 这条最关键
- [ ] `lipo -info` 确认 `x86_64 arm64`
- [ ] release notes 里的 SHA-256 与实际附件一致
- [ ] tap 的 `version` / `sha256` 已更新，且 `brew fetch --cask anywheredo` 能校验通过
- [ ] README 的版本相关描述没有过时

## 用户侧的一次性影响

v1.0.0 是 ad-hoc 签名，所以**升级到第一个证书签名的版本（v1.1.0）时，用户需要重新授权
辅助功能一次**：

1. 系统设置 → 隐私与安全性 → 辅助功能 → 把 AnywhereDo 移除（`−`）后重新添加（`+`）
2. 或直接删掉旧条目后重新勾选

从 v1.1.0 往后，同一张证书签名 → requirement 不变 → **不再需要重新授权**。
这也是"换证书"必须慎重的原因：换一次，所有用户就要重来一次。
