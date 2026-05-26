# Getfigdata

从图表图片中提取数值数据的 macOS 桌面工具。加载一张含有曲线/折线的图表截图，校准坐标轴，即可自动追踪曲线并导出为 CSV 或 JSON。

## 功能

- **加载图片** — 支持拖放或打开任意常见图片格式（PNG、JPEG 等）
- **坐标校准** — 点击图片中的坐标轴参考点，设定 X/Y 轴的数值范围，建立像素到数据的映射
- **曲线提取** — 通过颜色追踪或手动标记提取曲线上的数据点，支持 Metal GPU 加速
- **多曲线支持** — 可提取同一张图中不同颜色的多条曲线
- **数据导出** — 导出为 CSV 或 JSON 格式

## 工作流程

1. **加载图片** → 拖入或选择一张图表截图
2. **校准** → 点击 X1/X2/Y1/Y2 四个参考点，输入对应的数值
3. **提取** → 自动追踪曲线，或手动点击标记数据点
4. **导出** → 将提取的数据导出为 CSV 或 JSON 文件

## 系统要求

- macOS 13.0+
- Apple Silicon 或 Intel（通用二进制）

## 构建

在 Xcode 中打开 `Getfigdata.xcodeproj`，选择 `Product > Build` 即可。需要 Xcode 15+。

### 命令行构建

```bash
bash scripts/build_mac_app_store.sh
```

## 技术栈

- SwiftUI + AppKit
- Metal（GPU 加速曲线提取）
- CoreGraphics
- StoreKit（应用内购）

## 许可

保留所有权利。
