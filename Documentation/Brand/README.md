# 词屿 · Lexisle

**从一个词，抵达新世界。**

Lexisle 组合了表示词汇的 Lex- 与岛屿 Isle。标识把翻开的书页化成两片不对称的岛岸，中间的弧形留白既是书脊，也是海湾；暖色圆点代表日出。

![品牌预览](brand-preview.png)

## 品牌资产

| 文件 | 用途 |
| --- | --- |
| `lexisle-logo.svg` | 完整彩色 Logo，可无损缩放 |
| `lexisle-symbol.svg` | 透明背景的单色符号 |
| `lexisle-logo.png` | 1024 px 彩色展示图，带透明外角 |
| `brand-preview.png` | 名称、Logo、小尺寸与配色预览 |
| `../../App/Resources/Assets.xcassets/BrandMark.imageset/BrandMark.pdf` | 应用内矢量标识 |
| `../../App/Resources/Assets.xcassets/AppIcon.appiconset` | iOS 三种外观及 macOS 全尺寸图标 |

主色松绿 `#244F42`，纸白 `#F5F1DF`，暖日 `#DCB16E`。应用图标背景使用轻微的松绿渐变，深色和系统着色版保留相同轮廓。iOS 图标为无透明通道的方形母版，由系统裁切外形；macOS 图标带适当留边与圆角。

## 修改与生成

名称和标语统一配置在 `Config/Brand.xcconfig`，应用界面通过 `AppBrand` 读取。系统显示名称与运行时文字共用这些配置。

图形的矢量母版保存在 `Scripts/generate_icon.swift`。修改路径后运行：

```sh
xcrun swift -module-cache-path .build/IconModuleCache Scripts/generate_icon.swift "$PWD"
python3 Scripts/generate_project.py
```

同一组路径同时生成 PNG、PDF、SVG，避免桌面图标与应用内标识发生偏差。源码工程和模块继续使用 `WordAtlas` 这一技术标识，构建产物为 `Lexisle.app`；数据及媒体来源仍按原许可署名 Word Atlas contributors。
