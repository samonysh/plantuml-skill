# PlantUML Skill for OpenCode

[English](README.md) · **简体中文**

自然语言 → PlantUML 图表 → SVG/PNG/PDF。这是一个 [OpenCode](https://github.com/voidzero-dev/opencode) skill，可以根据中英文自然语言描述生成 [uml-diagrams.org](https://www.uml-diagrams.org) 同款风格（严格遵循 OMG UML 2.x，黑白单色）的 UML 图表。

[![ClawHub](https://img.shields.io/badge/ClawHub-plantuml--skill-0a66c2?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzYuNDggMiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0tMSAxNy45M2MtMy45NS0uNDktNy0zLjg1LTctNy45MyAwLS40MS4wMy0uODEuMS0xLjIxTDkuOSAxNy4zYzEuMTUuMTggMi4wNy0uNTMgMi4wNy0xLjY4di0yLjM0bDMuOTggNC4wMmMtLjY0LjQxLTEuNDIuNjgtMi4yNS43OHYzLjA4eiIvPjwvc3ZnPg==)](https://clawhub.ai/samonysh/plantuml-skill)
[![Downloads](https://img.shields.io/badge/downloads-139-green)](https://clawhub.ai/samonysh/plantuml-skill)
[![Version](https://img.shields.io/badge/version-v1.1.1-blue)](https://clawhub.ai/samonysh/plantuml-skill)
[![License](https://img.shields.io/badge/license-MIT--0-lightgrey)](LICENSE)

## 特性

- **6+ 种图表类型**：时序图（Sequence）、类图（Class）、活动图（Activity）、用例图（Use Case）、组件图（Component）、状态图（State）等
- **自然语言驱动**：你只需描述需求 —— skill 会自动挑选合适的图表类型
- **uml-diagrams.org 参考风格**：纯黑白、虚线生命线、白色激活条、文本 stereotype —— 与 https://www.uml-diagrams.org 上的每一张图视觉一致
- **两套等价 preamble**：经典 `skinparam`（向后兼容性最强）与现代 CSS `<style>` 块（推荐用于 PlantUML ≥ 1.2019.9）
- **跨平台渲染脚本**：Bash（Linux/macOS/Git-Bash/WSL）与 PowerShell（Windows 原生）双入口
- **多渲染后端按严格优先级回退**：PlantUML 公网服务器 → Docker → 本地 JAR
- **文本 stereotype**：使用 `«interface»` / `«abstract»` 文本，不用带字母的彩色圆圈图标
- **零配色**：纯黑白输出，适合学术论文、RFC、技术文档等场景
- **CJK 字体支持**：通过 `--cjk` 标志支持中文、日文、韩文字符渲染
- **宽高比自动修正**：检测并自动修复过宽或过高的图表

## 环境要求

至少满足以下一项：

| 渲染方式 | 依赖 |
|---|---|
| Docker | `docker pull plantuml/plantuml:latest` |
| Java | JRE 8+ 与 `plantuml.jar` |
| 互联网 | （公网服务器回退 —— 可靠性有限） |

推荐使用 Docker，也是脚本默认尝试的方案之一。

**CJK（中日韩）字符渲染**需要宿主机安装 CJK 字体（使用 `--cjk` 参数时）：
```bash
# Debian/Ubuntu
sudo apt install fonts-wqy-zenhei
# Fedora
sudo dnf install wqy-zenhei-fonts
# Arch
sudo pacman -S wqy-zenhei
```

## 安装

### 通过 ClawHub 安装（推荐）

```bash
openclaw skills install plantuml-skill
```

### 手动安装

```bash
git clone https://github.com/samonysh/plantuml-skill.git
cp -r plantuml-skill/.opencode/skills/plantuml ~/.config/opencode/skills/
```

或者作为项目内 skill 链接进来：

```bash
ln -s $(pwd)/plantuml-skill/.opencode/skills/plantuml .opencode/skills/plantuml
```

## 快速上手

安装好之后，在 OpenCode 里直接用自然语言触发：

```
> 画一张 OAuth2 登录流程时序图，参与方包括用户、客户端和授权服务器
> 帮我生成一张电商订单领域模型的类图
> 绘制一个带泳道的退款审批流程活动图
```

skill 会自动：
1. 解析你的需求，挑选最合适的图表类型
2. 生成带 uml-diagrams.org 风格 preamble 的 PlantUML 源码
3. 渲染为 SVG（同时支持 PNG / PDF）
4. 把结果内联展示给你

### 手动渲染

你也可以直接渲染 `.puml` 源文件。skill 同时提供 Bash 和 PowerShell 两个入口脚本，**可在 Linux、macOS、Windows 上原生运行**：

**Linux / macOS / Git Bash / WSL：**

```bash
bash scripts/generate-plantuml.sh input.puml output_dir --format svg
```

**Windows PowerShell：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-plantuml.ps1 input.puml output_dir -Format svg
```

参数：`--format svg|png|pdf|txt`（默认 `svg`）— PowerShell 版本用 `-Format`，效果完全等价。

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--format svg\|png\|pdf\|txt` | 输出格式 | `svg` |
| `--cjk` | 启用 CJK 字体支持 | 关闭（自动检测） |
| `--no-fix` | 禁用宽高比自动修正 | 关闭（自动修正） |
| `--max-aspect N` | 宽高比阈值上限 | `2.5` |

## 支持的图表类型

| 类型 | 适用场景 | 触发示例 |
|---|---|---|
| **时序图（Sequence）** | API 调用、请求响应、握手协议 | "A 给 B 发 X，然后 B 回 Y" |
| **类图（Class）** | 领域模型、实体关系 | "Customer 有多个 Order，Order 包含多个 Item" |
| **活动图（Activity）** | 工作流、流水线、审批链 | "如果支付成功就发货，否则拒绝" |
| **用例图（Use Case）** | 系统角色、权限职责 | "管理员能管用户，编辑能发文" |
| **组件图（Component）** | 微服务、系统架构 | "API Gateway 把请求路由到用户服务和订单服务" |
| **状态图（State）** | 生命周期、状态机 | "工单从 New → Assigned → Resolved" |
| 部署图（Deployment） | 基础设施、云拓扑 | （按描述自动识别） |
| 甘特图（Gantt） | 时间线、项目计划 | （按描述自动识别） |
| 思维导图（Mind Map） | 层级结构、头脑风暴 | （按描述自动识别） |

## 风格规约

所有生成的图表都遵循 **uml-diagrams.org 参考风格** —— 严格遵循 OMG UML 2.x、用 Visio UML 2.x stencils 渲染的黑白外观（与 https://www.uml-diagrams.org 上的图视觉一致）：

```
' uml-diagrams.org reference style — strict OMG UML 2.x, monochrome
skinparam style strictuml
skinparam monochrome true
skinparam backgroundColor #FFFFFF
skinparam defaultFontName Helvetica
skinparam shadowing false
skinparam classAttributeIconSize 0
skinparam roundCorner 0
skinparam SequenceLifeLineBorderColor #000000
skinparam SequenceActivationBackgroundColor #FFFFFF
```

关键规则（对应到 uml-diagrams.org 的具体图示）：
- **不使用 stereotype 圆圈图标** —— `«interface»` / `«abstract»` 以文本形式呈现，而不是 Ⓒ/Ⓘ/Ⓐ 圆圈
- **抽象类名用斜体** —— 与 UML 2.5 §9 及 uml-diagrams.org 一致
- **无任何颜色** —— 只有 `#000000` 与 `#FFFFFF`
- **无 3D 阴影**
- **无属性可见性圆点**（●/◐/○）—— 使用 `+`/`-`/`#`/`~` 文本标记
- **虚线生命线** —— 与 uml-diagrams.org 时序图样式一致
- **白色填充 + 黑色细边的激活条** —— 与 execution specification 的官方定义一致
- **统一细发丝线条**（约 0.75pt 的边框与箭头）
- **标准 UML 几何形状** —— 棒人 actor、虚线依赖、虚线生命线

### 备选方案 —— CSS `<style>` preamble

自 PlantUML 1.2019.9 起，官方推荐使用 CSS 风格的 `<style>` 块替代 `skinparam`（参见 [plantuml.com/style-evolution](https://plantuml.com/style-evolution)）。本 skill 同时提供一套**视觉完全等价**、基于 `<style>` 的 preamble，适合运行在较新版本 PlantUML 上的用户。详见 [`SKILL.md`](.opencode/skills/plantuml/SKILL.md) 中的 "Alternative — CSS-style Preamble" 章节，以及参考示例 [`examples/07_sequence_oauth2_css_style.puml`](examples/07_sequence_oauth2_css_style.puml)。

## 示例

### 时序图 —— OAuth2 授权码模式

![OAuth2 Sequence](examples/01_sequence_oauth2.svg)

### 类图 —— 订单领域模型

![Order Domain](examples/02_class_order_domain.svg)

### 活动图 —— 退款审批流程

![Refund Workflow](examples/03_activity_refund.svg)

### 用例图 —— CMS 内容管理系统

![CMS Use Case](examples/04_usecase_cms.svg)

### 组件图 —— 电商微服务架构

![Microservices](examples/05_component_microservices.svg)

### 状态图 —— 工单生命周期

![Ticket States](examples/06_state_ticket.svg)

### 时序图 —— OAuth2 流程（CSS preamble 备选）

与示例 #1 业务相同，但改用 [plantuml.com/style-evolution](https://plantuml.com/style-evolution) 推荐的现代 **CSS `<style>` 块** 替代 `skinparam`。两套 preamble 视觉完全一致 —— 在 PlantUML ≥ 1.2019.9 上，建议优先采用 CSS 变体（`skinparam` 正在被官方逐步淘汰）。

![OAuth2 Sequence — CSS variant](examples/07_sequence_oauth2_css_style.svg)

所有示例源文件都在 [`examples/`](examples/) 目录下，全部采用 **uml-diagrams.org 参考风格** 的 preamble（其中 #07 使用 CSS 备选变体）。可以单独重新渲染某一个：

```bash
bash scripts/generate-plantuml.sh examples/01_sequence_oauth2.puml examples --format svg
```

也可以一次性重渲全部示例：

```bash
# Bash
for f in examples/*.puml; do bash scripts/generate-plantuml.sh "$f" examples --format svg; done
```

```powershell
# PowerShell
Get-ChildItem examples\*.puml | ForEach-Object {
    powershell -ExecutionPolicy Bypass -File scripts\generate-plantuml.ps1 $_.FullName examples -Format svg
}
```

## 项目结构

```
plantuml-skill/
├── .opencode/
│   └── skills/
│       └── plantuml/
│           ├── SKILL.md                    # Skill 定义与详细说明
│           ├── scripts/
│           │   ├── generate-plantuml.sh    # 渲染脚本 — Linux/macOS/Git-Bash/WSL
│           │   └── generate-plantuml.ps1   # 渲染脚本 — Windows PowerShell
│           └── references/                 # （可扩展的参考资料目录）
├── examples/
│   ├── 01_sequence_oauth2.puml / .svg
│   ├── 02_class_order_domain.puml / .svg
│   ├── 03_activity_refund.puml / .svg
│   ├── 04_usecase_cms.puml / .svg
│   ├── 05_component_microservices.puml / .svg
│   ├── 06_state_ticket.puml / .svg
│   └── 07_sequence_oauth2_css_style.puml / .svg   # CSS preamble 备选示例
├── .gitignore
├── README.md           # 英文 README
└── README.zh-CN.md     # 中文 README（本文件）
```

## 渲染脚本

skill 内置两套等价入口，覆盖所有主流操作系统：

- `scripts/generate-plantuml.sh` — Bash（Linux、macOS、Git Bash、MSYS2、WSL、Cygwin）
- `scripts/generate-plantuml.ps1` — PowerShell（Windows 原生）

两者都按 **严格优先级顺序** 尝试三种后端 —— 公网服务器作为首选，Docker 和本地 JAR 仅在公网不可达时回退：

1. **PlantUML 公网服务器**（`https://www.plantuml.com/plantuml`）—— **首选默认方案**，需要联网
2. **Docker**（`plantuml/plantuml:latest`）—— 公网失败时自动回退
3. **本地 JAR**（`plantuml.jar`）—— 最终离线兜底方案（需 Java）

```bash
# SVG（默认）— Bash
bash generate-plantuml.sh diagram.puml ./output

# SVG + CJK 字体支持
bash generate-plantuml.sh diagram.puml ./output --cjk

# PNG + 自定义宽高比阈值
bash generate-plantuml.sh diagram.puml ./output --format png --max-aspect 3.0

# ASCII 文本图 — Bash（txt 格式跳过图片渲染）
bash generate-plantuml.sh diagram.puml ./output --format txt

# 禁用宽高比自动修正
bash generate-plantuml.sh diagram.puml ./output --no-fix
```

```powershell
# SVG（默认）— PowerShell
powershell -ExecutionPolicy Bypass -File generate-plantuml.ps1 diagram.puml .\output

# PNG — PowerShell
powershell -ExecutionPolicy Bypass -File generate-plantuml.ps1 diagram.puml .\output -Format png
```

### CJK 字体支持

渲染包含中文、日文或韩文字符的图表时，`--cjk` 参数会：
- 将 `Helvetica` 替换为 `WenQuanYi Micro Hei`（一种 CJK 兼容字体）
- 将宿主机字体目录挂载到 Docker 容器中
- 刷新容器的字体缓存后再进行渲染

未使用 `--cjk` 时，脚本会自动检测 CJK 字符并显示警告。

### 宽高比自动修正

渲染 SVG 或 PNG 输出后，脚本会检查图像尺寸。若宽高比（宽度/高度 或 高度/宽度）超过 `--max-aspect`（默认 2.5:1），脚本会：

1. 对 `.puml` 文件应用布局修正指令（`left to right direction`、`top to bottom direction`、`scale`、间距调整）
2. 重新渲染图表
3. 再次检查（最多进行 2 次修正尝试）

这样可以避免图表在某个方向上过度拉伸。

## License

MIT
