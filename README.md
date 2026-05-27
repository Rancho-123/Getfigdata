# Getfigdata

从图表图片中提取数值数据的 macOS 桌面工具。加载一张含有曲线/折线的图表截图，校准坐标轴，即可自动追踪曲线并导出为 CSV 或 JSON。

macOS desktop tool for extracting numerical data from chart images. Load a screenshot containing a curve or line chart, calibrate the axes, and it will automatically trace the curve and export it as CSV or JSON.

## 功能 Features

- **加载图片** — 支持拖放或打开任意常见图片格式（PNG、JPEG 等）
- **坐标校准** — 点击图片中的坐标轴参考点，设定 X/Y 轴的数值范围，建立像素到数据的映射
- **曲线提取** — 通过颜色追踪或手动标记提取曲线上的数据点，支持 Metal GPU 加速
- **多曲线支持** — 可提取同一张图中不同颜色的多条曲线
- **数据导出** — 导出为 CSV 或 JSON 格式

- **Load Image** — Supports drag-and-drop or opening of any common image format (PNG, JPEG, etc.)

- **Coordinate Calibration** — Click on coordinate axis reference points in the image to set the numerical range for X/Y axes, establishing a mapping from pixels to data

- **Curve Extraction** — Extract data points on the curve through color tracking or manual marking, supports Metal GPU acceleration

- **Multi-curve Support** — Can extract multiple curves of different colors from the same image

- **Data Export** — Export as CSV or JSON format

## 工作流程 Work process

1. **加载图片** → 拖入或选择一张图表截图
2. **校准** → 点击 X1/X2/Y1/Y2 四个参考点，输入对应的数值
3. **提取** → 自动追踪曲线，或手动点击标记数据点
4. **导出** → 将提取的数据导出为 CSV 或 JSON 文件  
### 
1. **Load Image** → Drag in or select a chart screenshot
2. **Calibration** → Click on the four reference points (X1/X2/Y1/Y2), and input the corresponding values
3. **Extraction** → Automatically track the curve, or manually click on data points
4. **Export** → Export the extracted data as a CSV or JSON file

## 系统要求 System Requirements

- macOS 13.0+
- Apple Silicon or Intel（通用二进制/Universal Binary）

## 构建 Build

在 Xcode 中打开 `Getfigdata.xcodeproj`，选择 `Product > Build` 即可。需要 Xcode 15+。

Open `Getfigdata.xcodeproj` in Xcode and select `Product > Build`. Requires Xcode 15+.

### 命令行构建 Command Line Build

```bash
bash scripts/build_mac_app_store.sh
```

## 技术栈 Technology Stack

- SwiftUI + AppKit
- Metal（GPU 加速曲线提取/ GPU Acceleration Curve Extraction）
- CoreGraphics
- StoreKit

## 许可 License

保留所有权利。 

All rights reserved.
 
