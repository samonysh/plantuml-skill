# PlantUML Skill —— 基于 SkillHub TRACE 评测的下一轮优化方案

> 参考评测：<https://skillhub.cn/skills/plantuml-skill>
> 评测综合评分：**4.5 / 5（优秀）**
> 目标版本：**v1.7.0**
> 方案生成时间：2026-07-07

---

## 一、评测结果摘要

SkillHub 的 TRACE 体系从 **T**rust / **R**eliability / **A**daptability / **C**onvention / **E**ffectiveness 五个维度对本 Skill 进行了评估。当前得分与关键短板汇总如下：

| 维度 | 当前评分 | 主要肯定项 | 主要短板 |
|---|---|---|---|
| **T · 可信任度** | 4.5 | 双实验室交叉验证、无 P0/P1 级安全风险、支持中文渲染 | ① 上手门槛：必须先安装 Docker / Java；② 主要文档为英文；③ 默认公网渲染服务器在境外，联网时较慢 |
| **R · 可靠性** | 4.3 | A4 适配自动修正、CJK 字体支持、多后端回退 | 渲染失败时错误提示不够清晰，普通用户难以自行排障 |
| **A · 适用性** | 4.8 | 触发词直观、场景表 & 拒答/隐私风险提示到位 | —（本轮持续维护，无重大缺口） |
| **C · 规范性** | 4.1 | 文档结构清晰、按步骤引导、风险提示明确 | ① 缺少 **端到端案例演示**（真实场景 → prompt → 输出）；② 缺少 **FAQ / Troubleshooting** 章节 |
| **E · 有效性** | 4.9 | 文档详尽、脚本完善、A4 / 比例自动修正、专业输出 | —（继续保持） |

**核心结论**：Effectiveness 与 Adaptability 已接近满分，重点应放在 **C（规范性）** 与 **R（可靠性）**，以及 **T（可信任度）** 中"上手门槛 / 中文文档 / 默认公网慢"三项体感痛点上。

---

## 二、优化目标（v1.7 目标分）

| 维度 | 当前 | 目标 | Δ |
|---|---|---|---|
| T · Trust | 4.5 | **4.8** | +0.3 |
| R · Reliability | 4.3 | **4.7** | +0.4 |
| A · Adaptability | 4.8 | **4.9** | +0.1 |
| C · Convention | 4.1 | **4.7** | +0.6 |
| E · Effectiveness | 4.9 | **4.9** | 保持 |
| **综合** | **4.5** | **≥ 4.8** | **+0.3** |

---

## 三、按维度拆解的优化方案

### 3.1 T · Trust — 降低上手门槛 & 补齐中文文档

| 编号 | 优化点 | 具体动作 |
|---|---|---|
| T-1 | **一键安装脚本** | 新增 `scripts/bootstrap.sh` / `scripts/bootstrap.ps1`：自动探测环境（Docker → Java → 无），给出交互式引导：若无 Docker，提示是否 `docker pull plantuml/plantuml:latest`；若无 Java，指引下载 `plantuml.jar`。执行完毕后落一份 `~/.plantuml-skill/env.json` 缓存探测结果。 |
| T-2 | **中文文档双向对齐** | 将 `SKILL.md` 中的 Persona / Trigger / Refusal / 隐私章节镜像成 `SKILL.zh-CN.md`；`RELEASE.md`、`OPTIMIZATION_PLAN.md`、`FAQ.md` 均提供 `.zh-CN.md` 版本；README 头部新增语言切换徽章。 |
| T-3 | **就近渲染建议** | 首次运行渲染脚本时，若最终走到 Kroki 公网并延迟 > 3s，输出一条**橙色提示**："建议使用 Docker 本地渲染或自托管 Kroki（附一条 `docker run -d -p 8000:8000 yuzutech/kroki` 命令示例）"。 |
| T-4 | **安全基线声明** | 在 README 新增"安全基线"小节，明示：默认零外发、日志无用户数据、Docker 镜像固定 tag（不使用 `latest` 生产建议）、SBOM 生成方式（`docker sbom plantuml/plantuml:1.2024.x`）。 |

### 3.2 R · Reliability — 让错误"说人话"

| 编号 | 优化点 | 具体动作 |
|---|---|---|
| R-1 | **人类可读的错误码体系** | 引入 `PU-Exxxx` 错误码规范，例如：`PU-E001 缺少渲染后端`、`PU-E002 CJK 字体未安装`、`PU-E003 语法错误`、`PU-E004 尺寸超 A4`、`PU-E005 Kroki 网络失败`。每条错误一行摘要 + 一条修复建议 + 一条文档锚点链接。 |
| R-2 | **`--diagnose` 诊断子命令** | 新增 `generate-plantuml.sh --diagnose`：一次性打印 Docker/Java/字体/PlantUML 版本/网络出口，并针对每项给出"通过 ✓ / 失败 ✗ + 修复指令"。PowerShell 版本对齐 `-Diagnose` 开关。 |
| R-3 | **重试与降级可见化** | 当 Docker → JAR → Kroki 触发降级时，在 stderr 打印一次性说明块："Docker 未检测到，回退到本地 JAR"，避免用户误以为脚本卡死；同时把最终使用的后端写入 `output_dir/.render-meta.json`。 |
| R-4 | **PlantUML 语法错误定位** | 解析 PlantUML stderr 里的 `line N` 提示，将出错行**回填并高亮**到脚本输出中（前后各 2 行上下文），减少"错在哪一行"这类排障成本。 |
| R-5 | **回归用例矩阵** | 在 `tests/` 下新增 `smoke/` 目录：每类图各一份最小 `.puml` + 期望 `.svg` 尺寸区间；CI 上在 3 个后端（Docker、JAR、Kroki mock）分别跑一次。 |

### 3.3 A · Adaptability — 保持并小幅增强

| 编号 | 优化点 | 具体动作 |
|---|---|---|
| A-1 | **样式档位（预设）** | 保留严格 uml-diagrams.org 风格为默认，同时新增 3 档预设：`--style strict`（现状 / 默认）、`--style clean`（保留单色但允许 8px 圆角与更宽间距）、`--style handdrawn`（`skinparam handwritten true`，适合白板 / 教学场景）。 |
| A-2 | **场景 → 图型 决策树** | 在 `SKILL.md` 里新增一张 mermaid 决策树："用户描述包含'调用/请求' → Sequence；'状态迁移/生命周期' → State；……"，减少 LLM 选型抖动。 |
| A-3 | **中文触发词校验集** | 在 `tests/triggers/zh.jsonl` 收集 30 条真实中文口语化触发词（"帮我画一下"、"简单画个流程"、"顺手出张图"），用于回归 SKILL 对中文口语触发的鲁棒性。 |

### 3.4 C · Convention — 补齐 FAQ 与案例

这是本轮**最大的分值增长点**（4.1 → 4.7）。

| 编号 | 优化点 | 具体动作 |
|---|---|---|
| C-1 | **新增 FAQ.md / FAQ.zh-CN.md** | 至少覆盖 15 个高频问题，按主题分类：<br>• 安装类（Docker 权限、Windows PowerShell 执行策略、代理下拉镜像失败）<br>• 渲染类（CJK 字体缺失、公式 / 特殊字符转义、图太大 A4 装不下）<br>• 隐私类（`--use-public-server` 到底会发什么、如何切自托管）<br>• 样式类（怎么加一点点颜色而不破坏 strict UML、怎么关掉 A4 检查）<br>• 错误码类（`PU-E001..E999` 索引） |
| C-2 | **端到端案例演示（Case Studies）** | 在 `docs/case-studies/` 下沉淀 3 个真实场景：<br>① 复盘线上事故 → 用时序图重构故障链路；<br>② 微服务上线设计 → 组件图 + 部署图组合；<br>③ 需求评审 → 活动图 + 状态图组合。<br>每个 case 包含：**真实业务背景 → 用户 prompt → SKILL 选型思考 → 最终 `.puml` → SVG 截图 → 复盘。** |
| C-3 | **文档章节校对与统一** | 统一术语（"skill" / "Skill" / "技能"）；README 与 SKILL.md 的选项表口径对齐；补齐 `--dark-mode` 在中文 README 的默认值列。 |
| C-4 | **贡献 & 报障模板** | 新增 `.github/ISSUE_TEMPLATE/`：bug 报告模板（自动请求粘贴 `--diagnose` 输出）、样式请求模板、FAQ 建议模板。 |

### 3.5 E · Effectiveness — 保持满意度的同时做小步增量

| 编号 | 优化点 | 具体动作 |
|---|---|---|
| E-1 | **PDF 输出的 A4 校准** | 目前 A4 校验主要针对 SVG/PNG；对 `--format pdf` 增加同等尺寸检查（PlantUML 内部按 96 DPI 输出，需要按 72 DPI 换算）。 |
| E-2 | **Gantt / Mind Map 示例补齐** | README 目前示例覆盖 6 类；补上 Gantt（项目排期）、Mind Map（架构头脑风暴）两个示例（`.puml` + `.svg` + `.dark.svg`），让 9 类图全部有可视样本。 |
| E-3 | **性能基线** | 记录一次基准：单张典型时序图（20 个 message）在 Docker / JAR / Kroki 三种后端的 P50 / P95 渲染耗时，写入 `docs/BENCHMARK.md`，便于用户预估。 |

---

## 四、里程碑与交付节奏

建议按三个小版本递进交付，每个小版本可独立发布：

### v1.7.0 · "**开箱即用**"（预计 1 周内）

- **T-1 一键 bootstrap**、**T-3 就近渲染建议**
- **R-1 错误码体系（首批 10 条）**、**R-3 降级可见化**
- **C-1 FAQ.md 首版（≥ 10 个问答）**、**C-4 Issue 模板**
- **E-2 Gantt / Mind Map 示例补齐**

**目标增量**：Trust 4.5 → 4.7、Reliability 4.3 → 4.5、Convention 4.1 → 4.5。

### v1.7.1 · "**说人话**"（预计 2 周内）

- **T-2 中文文档双向对齐**、**T-4 安全基线声明**
- **R-2 `--diagnose` 子命令**、**R-4 语法错误行定位**
- **C-2 案例研究首篇上线**（微服务上线设计）

**目标增量**：Trust 4.7 → 4.8、Reliability 4.5 → 4.7、Convention 4.5 → 4.6。

### v1.7.2 · "**看得远**"（预计 4 周内）

- **A-1 样式档位**、**A-2 决策树**、**A-3 中文触发词回归集**
- **C-2 其余两篇案例**、**C-3 术语统一**
- **R-5 回归用例矩阵接入 CI**
- **E-1 PDF A4 校验**、**E-3 性能基线**

**目标增量**：Adaptability 4.8 → 4.9、Convention 4.6 → 4.7、综合达到 4.8。

---

## 五、验收标准（可量化）

| 项 | 判定标准 |
|---|---|
| Trust | `bootstrap.sh` 在纯净 Ubuntu 22.04 / Windows 11 上可从零走通；中文 README 覆盖英文 README 100% 章节 |
| Reliability | 10 条常见错误全部有 `PU-Exxxx` 码；`--diagnose` 在缺 Docker / 缺 Java / 缺字体 / 断网 4 种场景下均给出正确修复建议 |
| Adaptability | 30 条中文触发词回归集通过率 ≥ 95%；3 档样式预设产出图片肉眼可辨 |
| Convention | FAQ ≥ 15 问答；3 篇端到端案例上线；Issue 模板启用 |
| Effectiveness | 9 类图全部有 `.puml` + `.svg` + `.dark.svg`；`BENCHMARK.md` 有 3 后端 × 3 图型 = 9 组耗时数据 |

---

## 六、非目标（本轮明确不做）

- **不引入新的图表 DSL**（例如 D2、Mermaid 互转），避免破坏当前"自然语言 → PlantUML"的价值定位。
- **不放宽 uml-diagrams.org 严格单色默认**：只通过 `--style` 提供额外档位，`strict` 仍为默认。
- **不改变 MIT-0 许可证**，也不引入需要企业授权的字体 / 依赖。

---

## 七、风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 一键 bootstrap 在企业代理环境失败 | Trust 反而下降 | bootstrap 检测到 `HTTP_PROXY / HTTPS_PROXY` 时先透传；失败时给出手工镜像指令 |
| 错误码文案翻译不一致 | Convention 反而变糟 | 错误码定义使用**同一份 YAML（`error-codes.yml`）**，脚本读取时按 `LANG` 环境变量选择本地化 |
| CI 引入 Docker 后 pipeline 变慢 | 迭代变慢 | 用 `plantuml/plantuml:1.2024.x` 固定 tag 并缓存；smoke 用例控制在 30 秒内 |

---

## 八、附录

### A. 涉及新增 / 修改的文件清单

```
新增：
├── scripts/
│   ├── bootstrap.sh
│   └── bootstrap.ps1
├── docs/
│   ├── FAQ.md
│   ├── FAQ.zh-CN.md
│   ├── BENCHMARK.md
│   ├── error-codes.yml
│   └── case-studies/
│       ├── 01-postmortem-sequence.md
│       ├── 02-microservice-launch.md
│       └── 03-requirements-review.md
├── skills/plantuml/SKILL.zh-CN.md
├── tests/
│   ├── smoke/*.puml
│   └── triggers/zh.jsonl
└── .github/ISSUE_TEMPLATE/
    ├── bug_report.yml
    ├── style_request.yml
    └── faq_suggestion.yml

修改：
├── skills/plantuml/scripts/generate-plantuml.sh   # 错误码、--diagnose、降级提示
├── skills/plantuml/scripts/generate-plantuml.ps1  # 同上
├── skills/plantuml/SKILL.md                       # 场景决策树、样式档位
├── README.md / README.zh-CN.md                    # 语言切换、安全基线、Gantt/Mind Map 示例
└── RELEASE.md                                     # v1.7 系列 changelog
```

### B. 与本次评测报告的一一映射

| 报告原句 | 对应优化项 |
|---|---|
| "使用前需要安装 Docker" | T-1 |
| "主要文档是英文的" | T-2 |
| "画图服务器在外国，需要联网时会比较慢" | T-3 |
| "错误提示不够清楚，普通用户可能看不懂" | R-1、R-2、R-4 |
| "样式要求过于刻板，缺少灵活调整空间" | A-1 |
| "缺少实际案例演示" | C-2 |
| "遇到问题时缺少常见问题解答" | C-1 |

---

> 本方案是一个 **可执行的迭代蓝图**，每个优化项均已拆解为最小可交付单元（PR-sized）。建议将本文件作为 v1.7.x 里程碑的对齐锚点，在 PR 描述中回引对应编号（例如 "closes T-1 / R-3"）。
