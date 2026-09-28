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

```bash
# 1. 改版本号（唯一来源：Resources/Info.plist 的 CFBundleShortVersionString）
#    构建时会写进 App，`--version` 与包内 Info.plist 都从它取

# 2. 构建通用二进制并用证书签名
SIGNING_IDENTITY="AnywhereDo Signing" \
SIGNING_KEYCHAIN="$HOME/Library/Keychains/anywheredo-signing.keychain-db" \
UNIVERSAL=1 ./scripts/build_app.sh

# 3. 检查输出的 designated requirement：必须**不含 cdhash**
codesign -d -r- build/AnywhereDo.app

# 4. 打包
ditto -c -k --keepParent build/AnywhereDo.app /tmp/AnywhereDo-<版本>-universal.zip
shasum -a 256 /tmp/AnywhereDo-<版本>-universal.zip

# 5. 建 release（notes 里写清安装方式与 SHA-256）
gh release create v<版本> /tmp/AnywhereDo-<版本>-universal.zip --title "AnywhereDo <版本>" --notes-file …

# 6. 更新 tap 仓库的 cask：version + sha256
#    （这一步会由 .github/workflows/release.yml 自动化）
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
