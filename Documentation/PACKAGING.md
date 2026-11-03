# 打包与 GitHub Actions

本地和 CI 共用 `Scripts/package.sh`，无需 Apple Developer 证书或仓库密钥即可构建。默认使用本地 `Release` 配置，关闭 CloudKit。

## 本地使用

需要 macOS、Xcode 26 或更新版本，以及 Python。DMG 工具要求 Python 3.10+；脚本会优先寻找较新版本，也可通过 `PYTHON_BIN` 指定解释器。仅构建 IPA 时 Python 3.9+ 即可。

```sh
# 同时生成两种安装包
bash Scripts/package.sh all

# 分别生成
bash Scripts/package.sh dmg
bash Scripts/package.sh ipa

# 指定版本、构建号和输出目录
bash Scripts/package.sh all --version 1.2.3 --build-number 42 --output-dir dist

# 复用上次成功构建的 App/Archive，重新生成安装包
bash Scripts/package.sh all --skip-build

# 显式指定 Python（示例）
PYTHON_BIN=/opt/homebrew/bin/python3.14 bash Scripts/package.sh dmg
```

版本格式为 `X.Y.Z`，不带 `v` 前缀；构建号为正整数。不传时使用工程的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。版本值进入两平台的 Info.plist，关于页也显示实际构建版本。

默认产物：

```text
dist/
  Lexisle-1.0.0-macOS-universal.dmg
  Lexisle-1.0.0-macOS-universal.dmg.sha256
  Lexisle-1.0.0-iOS-unsigned.ipa
  Lexisle-1.0.0-iOS-unsigned.ipa.sha256
```

`dist/` 和中间产物均被 Git 忽略。构建日志在 `.build/package/logs/`，原始 Mac App 和 iOS archive 分别在 `.build/package/macos/`、`.build/package/ios/`。`--skip-build` 会核对指定版本；同时打包两个平台时，还要求缓存的版本号和构建号一致。

## 两种包的区别

| 项目 | macOS DMG | iOS IPA |
| --- | --- | --- |
| 目标 | 原生 macOS 26+ | iPhone/iPad，iOS 26+ |
| 架构 | arm64 + x86_64 Universal | iphoneos arm64 真机 |
| 签名 | ad-hoc 临时签名 | 不含应用签名、Mach-O 签名或描述文件 |
| 安装 | 拖到 Applications | 安装前需自行签名 |
| Apple 账号 | 构建不需要 | 构建不需要；正常设备安装需要适用的签名方式 |

DMG 不包含 Developer ID 签名，也未进行 Apple 公证。下载后 macOS 可能要求确认打开。未签名 IPA 不是可直接安装的 App Store/TestFlight 包，也不能安装到模拟器；重新签名时需使用自己的 Bundle ID、证书和描述文件。CloudKit 版本需另外使用项目的 Cloud 配置和对应开发者能力。

## 打包校验

- Mac 构建完成后做 ad-hoc 签名并保留沙盒与网络 entitlement，核验两个架构及 `MACOS` 平台。
- DMG 包含词屿 Retina 安装背景、固定图标位置和 Applications 链接；直接写入 `.DS_Store`，不依赖 Finder 或 AppleScript。
- DMG 创建后检查镜像完整性，再以只读方式挂载检查 App 签名、架构、链接与布局，所有退出路径都卸载镜像。
- IPA 从真机 archive 复制 App，清除链接器可能附带的 ad-hoc 签名、所有 `_CodeSignature` 目录及 provisioning profile，再创建 `Payload/Lexisle.app` ZIP。
- 最终 IPA 会检查实际压缩包内的 Info.plist、执行权限、Mach-O 架构、`IOS` 平台和签名状态；不会把 arm64 模拟器产物误认为真机包。
- 两个文件旁都生成 SHA-256 校验和。已有输出只会在新包校验成功后被替换。

可以独立校验已有产物：

```sh
python3 Scripts/packaging/artifact_utils.py verify-dmg dist/Lexisle-1.0.0-macOS-universal.dmg --app-name Lexisle
python3 Scripts/packaging/artifact_utils.py verify-ipa dist/Lexisle-1.0.0-iOS-unsigned.ipa --app-name Lexisle
(cd dist && shasum -a 256 -c *.sha256)
```

## GitHub Actions

工作流：`.github/workflows/package.yml`，显示名称为 **Build DMG and unsigned IPA**。

**手动构建**：进入仓库 Actions，选择此工作流，点击 Run workflow。`version` 可留空；构建号使用本次 `github.run_number`。两个 macOS runner 并行构建 DMG 与 IPA，DMG 任务先运行现有 macOS 单元测试。完成后在运行页面下载 `Lexisle-package-dmg`、`Lexisle-package-ipa`，日志和测试结果作为单独 artifact 保存，保留 14 天。手动运行不会发布 Release。

**标签发布**：推送形如 `v1.2.3` 的标签后，工作流将 `1.2.3` 写入 App 版本，同时构建两种包。两者均成功后才校验文件、确认标签仍指向构建时的提交，并发布 GitHub Release；重复运行会更新同一 Release 的附件。

```sh
git tag -a v1.2.3 -m "Lexisle 1.2.3"
git push origin v1.2.3
```

工作流使用 `macos-26` 自带的 Xcode；创建时确认其默认版本为 Xcode 26.6。官方 checkout/upload/download Actions 固定到已核验的提交。构建任务只有仓库读取权限，发布任务才拥有 `contents: write`；使用 GitHub 自动提供的 token，不需要配置 PAT、签名证书或 notarization secret。

## QuietLock 参考分析

参考仓库：[tianguzhe/QuietLock](https://github.com/tianguzhe/QuietLock)。

| 参考文件 | 方式 | Lexisle 的处理 |
| --- | --- | --- |
| `scripts/build.sh` | Universal Release 构建，再复制并临时签名 | 保留此流程，并核验平台、版本和实际架构 |
| `scripts/package-dmg.sh` | 独立 venv、固定 dmgbuild 版本、Retina 图像、镜像验证与 SHA-256 | 使用相同的无 GUI 打包思路，增加只读挂载后完整检查和可靠卸载 |
| `Tools/dmg-settings.py` | 直接生成 Finder 布局，不修改 App 的 FinderInfo | 沿用这一约束，避免破坏严格签名校验 |
| `scripts/release.sh` / `release.yml` | `v*` 标签触发 Mac DMG 发布 | 扩展为手动/标签触发、两平台矩阵构建、artifact 下载及双包 Release |

QuietLock 只有 Mac 打包流程。Lexisle 额外实现了 iOS 真机归档、签名移除和 IPA 内容校验；安装背景使用词屿自己的标识与配色。
