# 构建产物与应用搜索隔离

开发、测试和打包过程中生成的 `.app` 都是中间产物。它们放在项目的 `.build` 中；正式使用的 macOS App 从 `dist` 中的 DMG 拖入 `/Applications` 安装。

这延续了 [QuietLock 的构建脚本](https://github.com/tianguzhe/QuietLock/tree/main/scripts) 的做法，并增加了应用注册清理。仅把 `build` 改名为 `.build` 并不够：Xcode 构建时会调用 LaunchServices 注册 App，手动运行测试副本也可能重新注册，所以系统应用搜索中仍可能出现同名副本。

## 通用脚本

`Scripts/build_isolation.py` 使用 Python 3.9+ 标准库，可以复制到其他 macOS 项目使用，不依赖 Lexisle 的名称、Bundle ID 或工程结构。

在项目目录运行：

```sh
# 创建隔离目录，并配置当前用户的 Xcode 工程构建位置。
python3 Scripts/build_isolation.py prepare --root .

# 查看本项目关联的测试应用注册记录。
python3 Scripts/build_isolation.py status --root .

# 预览将要注销的注册记录，不改变系统注册状态。
python3 Scripts/build_isolation.py cleanup --root . --dry-run

# 注销本项目的测试副本注册记录。
python3 Scripts/build_isolation.py cleanup --root .
```

清理只处理当前 LaunchServices 数据库中属于这些测试路径的注册记录，不删除或搬动 `.app`、构建缓存或用户数据，不重置系统的整个应用注册数据库，也不会关闭整个磁盘的 Spotlight 索引。`/Applications` 和 `~/Applications` 中的正式安装不会被清理。

路径检查以实际目录为准，避免通过符号链接把清理范围扩展到项目之外。旧的项目内 `build`、`DerivedData`、`TestResults` 目录也属于检查范围。对于全局 `~/Library/Developer/Xcode/DerivedData`，只有其 `info.plist` 中的 `WorkspacePath` 确实指向当前项目时，才识别为该项目的历史构建目录。

如果历史缓存放在其他位置，可以通过可重复的 `--extra-build-dir` 明确指定。先用 `--dry-run` 检查范围，再执行清理：

```sh
python3 Scripts/build_isolation.py cleanup --root . \
  --extra-build-dir /path/to/old-project-build-cache --dry-run
```

该参数必须指向已经存在的具体缓存目录，不能是系统目录、应用目录、用户主目录或整个项目的上层目录。它也不会搬动旧缓存；后续构建应使用下面的隔离路径。

## 命令行构建与测试

用 `exec` 包裹 `xcodebuild` 或 `xcrun xcodebuild`，脚本会提供隔离的 DerivedData 路径，并在构建或测试结束后清理测试副本的注册记录。`--lane` 区分不同构建任务，避免它们共用同一个构建数据库。

```sh
python3 Scripts/build_isolation.py exec --root . --lane mac -- \
  xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-macOS \
  -destination 'platform=macOS' build

python3 Scripts/build_isolation.py exec --root . --lane mac -- \
  xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-macOS \
  -destination 'platform=macOS' test

python3 Scripts/build_isolation.py exec --root . --lane ios -- \
  xcodebuild -project WordAtlas.xcodeproj -scheme WordAtlas-iOS \
  -destination 'generic/platform=iOS Simulator' build
```

默认 DerivedData 位于 `.build/artifacts.noindex/xcode/<lane>`。通常无需再传 `-derivedDataPath`；如果显式指定，目标必须位于当前项目的 `.build/artifacts.noindex` 内。归档路径（`-archivePath`）、测试结果路径（`-resultBundlePath`）和显式构建输出路径也需要位于这一隔离目录中。构建失败时同样执行注册清理，并保留构建命令的失败状态。

对自定义脚本，`exec` 提供以下环境变量：

| 变量 | 用途 |
| --- | --- |
| `ISOLATED_BUILD_DIR` | 项目中的隔离工作目录；临时 App、归档、预览工具和编译缓存应放在这里。 |
| `ISOLATED_DERIVED_DATA` | 当前 `--lane` 对应的 DerivedData 路径。 |
| `ISOLATED_LOG_DIR` | 构建与测试日志目录；日志是否写入由自定义命令决定。 |

自定义命令需要实际使用这些变量；包裹一个仍将产物写到其他位置的脚本，不会自动重写它的文件路径。例如：

```sh
python3 Scripts/build_isolation.py exec --root . --lane swiftpm -- \
  bash -c 'swift build --scratch-path "$ISOLATED_BUILD_DIR/swiftpm"'
```

复制到其他项目后，将 `--root`、工程和 scheme 参数换成对应项目即可。截图中的 DevPocket 若也有重复项，需要对它的工程目录运行同一脚本；清理 Lexisle 不会顺带处理其他项目。

## Xcode 与预览

首次拉取项目后，先运行 `prepare`，再打开 Xcode：

```sh
python3 Scripts/build_isolation.py prepare --root .
open WordAtlas.xcodeproj
```

`prepare` 会为项目根目录中的 `.xcodeproj` 和 `.xcworkspace` 配置当前系统用户的工作区设置。对于本项目，文件位于：

```text
WordAtlas.xcodeproj/project.xcworkspace/xcuserdata/<用户名>.xcuserdatad/WorkspaceSettings.xcsettings
```

脚本只更新以下三个构建位置键，保留文件里的其他用户偏好，不修改全局 Xcode 设置：

| 设置 | 值 |
| --- | --- |
| `BuildLocationStyle` | `UniqueDerivedDataSubfolder` |
| `DerivedDataLocationStyle` | `WorkspaceRelativePath` |
| `DerivedDataCustomLocation` | `.build/artifacts.noindex/Xcode` |

这些设置属于本机 `xcuserdata`，不提交到 Git。运行工程生成器 `python3 Scripts/generate_project.py` 也会调用 `prepare`。Xcode GUI 会在上述目录后添加工程名，本项目实际构建位置为 `.build/artifacts.noindex/Xcode/WordAtlas/`。命令行 `exec --lane mac` 则使用独立的 `xcode/mac/` 子目录。

项目共享 scheme 在构建、测试和运行结束后执行相同的注册清理。测试副本运行期间，系统仍可能临时注册该路径。结束调试后清理；如果绕过 scheme 直接双击中间 `.app`，退出它后可以手动运行 `cleanup`。

`.build` 隐藏开发目录，`.noindex` 后缀用于排除构建子目录的 Spotlight 内容索引。`.metadata_never_index` 只作为补充标记，不把它当作对任意子目录都生效的保证。应用注册与文件内容索引是两套机制，因此这两部分都要处理。

强制结束构建进程、直接启动测试 App，或者其他启动器保留自己的缓存，都可能让旧条目暂时出现。先退出测试副本，再运行 `status` 与 `cleanup`。清理成功后，搜索界面可能需要重新打开或稍等才能刷新；不要为此删除正式 App 或重置整个系统注册数据库。

## 正式分发

| 路径 | 内容 |
| --- | --- |
| `.build/artifacts.noindex/xcode/<lane>/` | 命令行构建与测试的 DerivedData。 |
| `.build/artifacts.noindex/Xcode/WordAtlas/` | 本机 Xcode GUI 的 DerivedData；其他工程使用各自的工程名。 |
| `.build/artifacts.noindex/package/` | DMG / IPA 打包中间 App、归档、工具和日志。 |
| `dist/` | 正式 DMG、未签名 IPA 及 SHA-256 校验和。 |
| `/Applications/Lexisle.app` | 从 DMG 安装的正常使用版本。 |

打包命令仍为：

```sh
bash Scripts/package.sh all
# 仅 macOS：bash Scripts/package.sh dmg
```

构建目录中的 `.app` 只用于开发、验证和制作 DMG。安装时打开 `dist` 中的 DMG，把 App 拖进 `/Applications`，完成后推出磁盘映像。不要把中间 `.app` 复制进 `dist` 当作另一份安装包。

未签名 IPA 仍需适当签名后才能安装到真机。具体构建与校验步骤见 [打包说明](PACKAGING.md)。


## 验证记录

- 25 项 Python 脚本测试通过，覆盖工作区设置保留与重复执行、路径与符号链接边界、定向注册清理、构建路径注入、失败和中断后的清理。
- macOS 自动化测试通过；通用 macOS DMG 与未签名真机 IPA 已实际生成并完成产物校验。
- 本项目的 5 条历史开发注册记录已定向注销，正式安装与学习数据未修改。

复查脚本测试：

```sh
python3 -m unittest discover -s Scripts/tests -p 'test_build_isolation.py'
```
