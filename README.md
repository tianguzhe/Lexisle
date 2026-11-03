# 词屿 · Lexisle

**从一个词，抵达新世界。** [品牌图形与使用说明](Documentation/Brand/README.md)

面向中文用户的原生英语学习 App。完整内置 7,298 个词条和 14,596 条例句，提供插画图鉴、英美发音、每日学习、FSRS-6 间隔复习、收藏和学习统计。

支持 iOS/iPadOS 26+ 与原生 macOS 26+。界面使用 SwiftUI，用户数据使用 SwiftData，云端同步使用 CloudKit 私有数据库。所有文字内容首次断网也能访问；图片和录音从指定 CDN 按需下载。

## 打开和运行

需要 Xcode 27.2 或兼容的更新版本。项目没有 CocoaPods、全局 XcodeGen 或运行时 JavaScript 依赖；FSRS 已按固定提交放入 `Vendor/swift-fsrs`。

```sh
open WordAtlas.xcodeproj
```

在 Xcode 选择 `WordAtlas-iOS` 和一个兼容的 iPhone/iPad 模拟器，或选择 `WordAtlas-macOS` 与 My Mac。默认本地配置无需 CloudKit 账户配置。Mac 本地构建使用 ad-hoc 签名，iOS 本地配置用于模拟器。

品牌名称统一配置在 `Config/Brand.xcconfig`，安装后的名称为「词屿」，构建产物为 `Lexisle.app`。工程、scheme 和 Swift 模块继续使用 `WordAtlas` 技术标识；既有 Bundle ID、CloudKit container 和学习数据路径保持兼容。

添加或删除 Swift 文件后重新生成工程；已有源码不会被生成器改写：

```sh
python3 Scripts/generate_project.py
```

Swift 代码格式由 `.swift-format` 统一管理，第三方 `Vendor` 源码不参与格式化：

```sh
xcrun swift-format format --in-place --recursive --configuration .swift-format App Tests UITests
xcrun swift-format lint --strict --recursive --configuration .swift-format App Tests UITests
```

命令行构建与测试：

```sh
xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-macOS \
  -destination 'platform=macOS' -derivedDataPath build/mac build

xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-macOS \
  -destination 'platform=macOS' -derivedDataPath build/mac test

xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-iOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios build

# 用 simctl list devices available 中的设备 UUID 替换 SIMULATOR_UUID。
xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-iOS \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath build/ios test

# UI 测试使用独立的内存数据，不修改用户学习记录。
xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-UI-Tests \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath build/ui -resultBundlePath TestResults/UI.xcresult test
```

工程包含两套原生 App target、对应宿主单元测试 target、独立 iOS UI 测试 target，以及 `Debug`、`Release`、`CloudDebug`、`CloudRelease` 四个配置。共享 scheme 为 `WordAtlas-iOS`、`WordAtlas-macOS`、对应的 `-Cloud` scheme 和 `WordAtlas-UI-Tests`。UI 测试结果保留今日、搜索、详情与学习页面截图。

UI 测试请通过 Xcode 的 Product → Test 或上述 `WordAtlas-UI-Tests` scheme 启动。不要直接运行 `WordAtlasUITests-Runner.app` 或用 `simctl launch` 启动 runner：它依赖 Xcode 注入的 XCTest 框架路径与测试会话配置。首次测试曾遇到短暂的 runner 注册失败；通过正常 Xcode 测试流程重试后已完整通过。

## 打包 DMG 和未签名 IPA

```sh
bash Scripts/package.sh all
# 或：bash Scripts/package.sh dmg / bash Scripts/package.sh ipa
```

产物与 SHA-256 校验和位于 `dist/`。DMG 包含 Apple Silicon + Intel 通用 App 和拖拽安装界面；IPA 为未签名真机包，安装前需要自行签名。DMG 使用 ad-hoc 签名，未公证。

GitHub Actions 的 **Build DMG and unsigned IPA** 支持手动构建并下载附件；推送 `v1.2.3` 这类版本标签会构建两种包并发布 Release。不需要配置签名密钥。

[完整打包说明与 QuietLock 参考分析](Documentation/PACKAGING.md)

## 启用 iCloud

1. 将 `Config/Developer.example.xcconfig` 复制为 `Config/Developer.xcconfig`，填入开发者 Team、唯一 Bundle ID 前缀和自己的 iCloud Container ID；该文件被 Git 忽略。
2. 在 Apple Developer 后台注册 iOS App ID（前缀本身）及 Mac App ID（前缀加 `.mac`），为两者启用同一个 CloudKit container 与 Push Notifications。CloudDebug 使用开发推送环境，CloudRelease 使用生产推送环境。
3. 在 Xcode 的 Signing & Capabilities 核对团队与 container，选择相应 `-Cloud` scheme。Cloud 配置将 `WordAtlasCloudEnabled` 设置为 `YES`，并把同一 container ID 写入 Info.plist。
4. 用同一 Apple ID 登录的已签名设备验证同步。开发环境与生产环境数据库分离；发布前在 CloudKit Console 检查并部署 schema 到生产环境。

云端保存学习事件、收藏变更及学习设置；当前答题位置和缓存留在本机。无 iCloud 账户、离线或同步异常时继续本地学习。导入后的学习事件按稳定 ID 去重并确定性重放，避免两个离线设备的进度互相覆盖。

CloudKit 验收需要真实开发者配置；普通本地构建成功不代表云端已经通过端到端验证。请至少执行：两设备离线答题后联网合并、重复同步、跨设备取消收藏、设置同时变更、退出 iCloud、断网后恢复。

## 结构与数据

- `App/Support`：统一启动配置、应用数据初始化、通知令牌生命周期。
- `App/Core`：词库与媒体索引模型、并发加载、FSRS-6 调度、学习会话生成。
- `App/Persistence`：版本化 SwiftData 模型、会话事务、云端日志、验证投影与日历统计。
- `App/Media`：下载协调、磁盘缓存、图片解码缓存、录音与系统语音。
- `App/UI`：今日、图鉴、收藏、词条详情、学习和统计设置页面。
- `App/Resources`：完整词库、媒体索引、少量品牌插画、应用图标和许可说明。
- `Tests`：学习、持久化、事件合并及媒体行为测试。

完整的职责边界、事务顺序、并发约定和数据兼容规则见 [架构说明](Documentation/ARCHITECTURE.md)。

词条 ID 与原项目保持一致，媒体文件名不能从展示单词自行推导。第二条例句录音仅有 1,011 条，通过媒体索引标记判断是否存在。

媒体基地址固定为 `https://0xlei.tech/words/atlas/`，路径为：

| 资源 | 路径 |
| --- | --- |
| 缩略图 | `thumb/{id}.webp` |
| 详情图 | `img/{id}.webp` |
| 英音 / 美音 | `audio/uk/{id}.mp3` / `audio/us/{id}.mp3` |
| 例句一 / 例句二 | `audio/ex/{id}.mp3` / `audio/ex2/{id}.mp3` |

媒体缓存在本机缓存目录，默认上限 512 MB，按最近使用情况清理，不上传 iCloud。播放网络录音失败时使用可用的设备英语语音；设备也无法朗读时，听力题退回文字题。

词库更新与图标再生成：

```sh
python3 Scripts/import_resources.py /path/to/word-atlas
xcrun swift Scripts/generate_icon.swift "$PWD"
python3 Scripts/generate_project.py
```

FSRS 源码固定于 `4fbaf20184d62f82a9f44f343337c61a2c5483e9`，显式使用 FSRS-6 的 21 项参数，目标记忆率 90%，学习步骤 1/10 分钟、重学步骤 10 分钟，关闭随机间隔扰动。

## 界面与设备验收

首页聚焦每日学习与精选 6 个主题，点击「全部主题」打开完整的 19 主题网格。主题卡片随可用宽度调整列数，图鉴筛选自动换行；词条详情在宽屏采用图文并排，学习页缩小小屏插画并固定底部继续按钮。页面标题、边距和卡片间距使用共享布局规则。

![新版首页、主题和学习页面](Documentation/Screenshots/ui-overview.png)

已完成的核心实现验证：

| 检查 | 结果 | 本地结果文件 |
| --- | --- | --- |
| macOS 单元测试 | 19 项通过，0 失败 | `.build/FinalMacTests.xcresult` |
| iPhone Duo 主流程 UI 测试 | 1 项通过，0 失败 | `.build/UITests-Retry.xcresult` |
| 新版排版与主题导航回归 | 1 项通过，0 失败 | `.build/UI-Polish-Verified.xcresult` |
| Clean Code 单元回归 | 32 项通过，0 失败 | `.build/CleanCode-Final-Mac.xcresult` |
| Clean Code 完整交互回归 | 1 项通过，0 失败 | `.build/CleanCode-UI.xcresult` |
| Swift 格式检查 | strict lint 通过 | `.swift-format` |
| FSRS 依赖构建 | iOS Simulator、macOS 均通过 | 固定提交的本地 Swift Package |

UI 测试覆盖图鉴搜索、词条详情、收藏与取消收藏、开始学习、5 个新词介绍、首次作答反馈，以及退出后显示继续学习入口。真实测试截图已导出到 `Documentation/Screenshots`，包括首页、图鉴、详情、学习和答题反馈。该轮测试记录对应核心实现验收，不代替后续界面修改的针对性检查。

新版排版回归另覆盖搜索提交收起键盘、完整主题面板、选中历史主题后清除旧搜索并显示对应词库。`polished-*.png` 来自通过的独立 Duo 测试，`ui-overview.png` 为其中三个页面的并排预览。

Clean Code 回归增加旧会话解码、并发词库加载、异常同步批次拒绝后重新打开、夏令时统计、缓存清理与有界下载重试。iOS/macOS 最终构建通过；重构前后 V1 模型字段及 67 个内置资源文件已对照核验。

重点检查 320、390、600、768、1024、1440 pt 可用宽度，iPad 横竖屏和分屏、Mac 连续缩放，以及大字号、VoiceOver、减少动态效果、深浅色模式。答题中改变窗口布局应保留会话。

开发环境当前安装的 iOS 27.1 模拟器运行时仅声明支持 iPhone Duo。iPad target 可以构建，但独立 iPad 模拟器截图和交互验收需要另行安装兼容 iPad 的运行时或使用真机。折叠形态遵循系统提供的窗口尺寸和安全区；不会假定不存在的铰链或姿态接口。

## 授权

内容署名：**Word Atlas contributors — CC BY 4.0**。来源：[Word Atlas](https://github.com/designfuchen/word-atlas)；授权：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。此版本保留词条文本，转换了少量品牌图片格式，重写了原生界面、持久化和平台集成。

原项目代码与界面设计采用 MIT，Swift FSRS 采用 MIT。完整说明见 [NOTICE.md](NOTICE.md) 与 App 内「关于」。词库文字、插画和录音由 AI 生成并经过自动校验，尚未逐条人工审校，可能包含错误；本产品并非官方 IELTS 词表。
