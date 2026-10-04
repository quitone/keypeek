# Keypeek（键览）

> 一个跨平台的只读桌面小工具，帮你集中浏览和搜索多个应用的快捷键。

你是不是经常在 VSCode、Neovim、LazyVim 等工具之间切换，却记不住各自的快捷键？  
Keypeek 让你把各个应用的快捷键定义整理成简单的 YAML 文件，然后在一个界面里快速查看、搜索、过滤。  
它**只读**、**离线**、**不修改你的文件**，就像一个专属的快捷键速查手册。

> **当前状态：开发中，尚未发布。** 项目处于 Sprint 0 脚手架阶段，没有可执行文件下载（Releases 为空）。「界面说明」「设置」「搜索技巧」描述的是目标形态，实现落在 Sprint 3 之后；「💻 系统要求」「📝 编写你的快捷键 YAML」「🧱 依赖与维护状态」三节反映当前契约。

---

## ✨ 功能亮点

- **集中管理**：一个应用一个 YAML 文件，左侧列表点选切换。
- **快速搜索**：全局搜索所有字段和按键，支持搜 `leader`、`enter`、`ctrl` 等。
- **列过滤**：每列独立输入框，多个条件同时生效。
- **键帽显示**：按键自动拆分成小方块，如 `Ctrl` `k`，一目了然。
- **深色/浅色主题**：点击状态栏图标即时切换，自动保存。
- **完全离线**：不联网、不监听、不上传任何数据。
- **跨平台**：支持 Linux x64 和 Windows 10 x64。

---

## 💻 系统要求

- **Linux x64**：需要 X11 运行库，以及 pango / cairo 绘制库。多数桌面发行版已自带下列清单，它主要给无图形界面的 CI / docker 验证环境用。

  Debian/Ubuntu 运行时依赖（13 项，逐个安装即可）：

  ```bash
  sudo apt-get install -qq --no-install-recommends \
    libx11-6 libxinerama1 libxft2 libxext6 libxcursor1 libxrender1 libxfixes3 \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libpangoxft-1.0-0 libglib2.0-0 libfontconfig1
  ```

  额外两项 `libglu1-mesa`、`libgl1` 只在启用 `fltk` 的 `enable-glwindow` 特性时才需要（是否开启该特性由 S3 定案，当前不在上面的必需清单里）。

  清单来源：fltk-rs 上游 README 的「Runtime Dependencies / Linux」，核实日期 2026-10-04；本项目侧依据为 tech-plan §11.3（FLTK 静态编译、运行时需 X11 库）与风险项 R-07（README 须明确列出依赖）。
  本仓库尚未引入 `fltk`（S3 才进依赖树），所以上面是**文档级齐全**的清单：与真实产物的一致性未经 `ldd` 实测，记 not-run，待 S3 引入 fltk 后以构建产物复验、S5-9 收口。

- **Windows 10 x64**：直接运行，无需额外安装（上游记录 Windows 无运行时依赖；本机无 Windows 环境，该结论同样记 not-run）。

---

## 📥 下载与安装

1. 前往 Releases 页面，下载对应平台的可执行文件。**当前尚未发布任何版本**（Sprint 0 无产物），这一步待 S5-9 提供首个 release 后生效。
2. **Windows**：双击 `.exe` 即可运行。
3. **Linux**：赋予执行权限后运行：
   ```bash
   chmod +x keypeek
   ./keypeek
   ```
   如果提示缺少库，请按上文「💻 系统要求」一节列出的 13 项运行时依赖**逐个**安装——那份清单是完整集合，没有"等等"的省略项。

---

## 🚀 快速开始

### 1. 首次运行

第一次打开 Keypeek 时，它会自动创建配置目录：

- **Linux**：`~/.config/keypeek/`
- **Windows**：`%APPDATA%\keypeek\`

如果目录里还没有 YAML 文件，你会看到一个欢迎页面，提示你把文件放进去。

### 2. 放入你的快捷键 YAML 文件

每个 `.yaml` 文件代表一个应用，**文件名就是应用名**。例如：

- `VSCode.yaml`
- `LazyVim.yaml`
- `NeoVim.yaml`

> 注意：只识别 `.yaml` 扩展名，不识别 `.yml`。文件名大小写保留原样。

### 3. 查看更新

修改 YAML 文件后，**切换一下左侧的应用，或者重启 Keypeek**，就能看到最新内容。  
Keypeek 没有“刷新”按钮，这是为了保持简单和只读。

---

## 📝 编写你的快捷键 YAML

YAML 是一种简单的文本格式，用记事本就能编辑。下面是一个最小示例，结构与 PRD §4「数据模型」逐一对应（只有 `description` 等示例值取中文，方便直接照抄）：

```yaml
icon: "🟦"                   # 应用图标：emoji 或本地图片路径
key_names:                   # 可选：自定义列显示名
  keys: 按键
  description: 描述
  modes: 模式

list:                        # 必填：分组容器
  general:                   # 分组名，可以任意取
    - keys: j
      description: 向下
      modes: n
    - keys: g+s+a
      description: 添加包围
      modes: n, x
  neogen:
    - keys: c+n
      description: 生成注释
      modes: n
```

### 字段说明

| 字段 | 是否必需 | 说明 |
|---|---|---|
| `icon` | 否 | emoji 或本地图片路径，缺省用默认图标 |
| `key_names` | 否 | 字段名 → 显示名，未定义的显示原名 |
| `list` | 是 | 顶层分组容器，缺失或格式错误会导致文件不可用 |
| `list.分组名` | 是 | 分组名任意，值为条目数组 |
| 条目字段 | — | 至少包含 `keys`，常见还有 `description`、`modes`、`when`、`source` |

### 图标规则

- 支持 emoji，如 `"🟦"`。
- 支持本地图片：PNG / JPEG / WebP / GIF / SVG。
- 路径相对于 YAML 文件所在目录，使用 `/` 分隔。
- 不允许 `..` 逃逸，不允许 `http://` 等外部链接。
- 单张图片 ≤ 256 KB，尺寸 ≤ 256×256。
- SVG 仅支持本地、无脚本、无外部引用的安全子集。
- 加载失败会显示默认图标，不影响使用。

---

## 🖥️ 界面说明

```
┌────────────┬───────────────────────────────────────────────┐
│            │  分组: [全部 ▾]   搜索: [_____________] ✖      │
│ 🟦         ├───────────────────────────────────────────────┤
│ VSCode     │ 按键    │ 描述    │ 模式  │ 条件    │ 来源    │
│ 🟩         │         │[input]  │[input]│[input]  │[input]  │
│ LazyVim    │ ────────┼─────────┼───────┼─────────┼────────│
│ 🟨         │ [Ctrl+K]│打开命令 │       │         │ system  │
│ NeoVim     │         │面板     │       │         │         │
│ ...        │ [j]     │Down     │ n,x   │         │         │
│            │ ...                                            │
│ [«]        ├───────────────────────────────────────────────┤
│            │  共 N 条                                      │
└────────────┴───────────────────────────────────────────────┘
```

- **左侧栏**：列出所有应用，点击切换。可点击底部 `[«]` 折叠，只显示图标。
- **顶部分组下拉**：选择当前应用的分组，含“全部”。
- **全局搜索框**：输入关键词，匹配所有字段和按键。
- **表格**：每列下方有独立的过滤输入框，多个条件同时生效（AND）。
- **状态栏**：显示过滤后的条数，右侧有主题切换按钮 ☀/🌙。

---

## 🔍 搜索技巧

- **全局搜索**：大小写不敏感，匹配所有非按键字段，同时也匹配按键。
- **按键双重匹配**：搜 `leader` 能找到 `<leader>bb`；搜 `enter` 或 `cr` 都能找到 `<CR>`；搜 `ctrl` 或 `k` 都能找到 `<C-k>`。
- **列过滤**：在列头下方的输入框输入，只过滤该列，多个列过滤同时满足。
- **清除**：点击全局搜索框的 ✖ 清空全局搜索；列过滤各自清空。

---

## ⚙️ 设置

设置保存在配置目录下的 `settings.yaml` 中，可以手动编辑，也可以由界面自动保存。

```yaml
version: 1
theme: dark          # dark 或 light
font:
  family: ""         # 空 = 系统默认
  size: 14
window:
  width: 1000
  height: 700
sidebar:
  collapsed: false
```

- **主题切换**：点击状态栏右侧的 ☀/🌙 图标，即时生效并保存。
- **字体**：填写系统已安装的字体名称，若找不到会回退默认字体并提示。
- **窗口大小**：调整窗口后自动保存（有 500ms 防抖，不会频繁写盘）。

---

## ❓ 常见问题

**Q：修改了 YAML 文件，但界面没变化？**  
A：Keypeek 不监听文件变化。请切换一下左侧的应用，或者重启 Keypeek。

**Q：图标不显示？**  
A：检查图片路径是否正确、格式是否支持、大小是否超标。加载失败会降级为默认图标。

**Q：字体设置后没生效？**  
A：确认字体名拼写正确，且系统已安装该字体。找不到时会回退默认字体。

**Q：Linux 上启动报错缺少库？**  
A：请安装 X11 与 pango/cairo 运行库，Debian/Ubuntu 完整清单：`sudo apt-get install -qq --no-install-recommends libx11-6 libxinerama1 libxft2 libxext6 libxcursor1 libxrender1 libxfixes3 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libpangoxft-1.0-0 libglib2.0-0 libfontconfig1`。

**Q：支持 `.yml` 文件吗？**  
A：只支持 `.yaml`，不识别 `.yml`。

**Q：可以编辑快捷键吗？**  
A：不可以。Keypeek 是只读工具，请直接编辑 YAML 文件。

---

## 🔒 隐私与安全

- **完全离线**：不联网、不监听、不上传任何数据。
- **只读**：不会修改你的 YAML 文件。
- **安全检查**：图标路径禁止外部 URL 和路径逃逸；SVG 仅允许无脚本、无外部引用的安全子集。
- **无后台进程**：关闭窗口即完全退出。

---

## 🧱 依赖与维护状态

面向维护者：这里是「为什么选它、坏了往哪退、什么时候真正引入」的单一记录处。选型依据见 `tech-plan.md` ADR-005 / ADR-008，分层禁令见 §2.2，CI 的三处取舍（不用 sccache、矩阵只留 Windows、audit 归 S1）见 ADR-011。

### 已引入（Sprint 0）

| crate | 钉定版本 | 用途 | 允许所在层 | 维护状态（核实日期） | 已知风险 | 退路 |
|---|---|---|---|---|---|---|
| `serde` | `1`（derive） | 反序列化派生 | domain / infra | 活跃，生态基座 | 无 | 无（不可替） |
| `noyalib` | `0.0.51` + `compat-serde-yaml` | YAML 解析（替代已归档的 `serde_yaml`） | infra / domain（S0-3 定案：`Value` 等纯数据类型可进 domain） | **0.0.x 预发布**，单人维护（核实 2026-10-01） | 与上游 serde_yaml 0.9 存在布尔/合并键等行为差异；`0.0.*` 内可随时破坏兼容 | `domain::parse` 只依赖通用 `Value`，替换成本限于一个文件 |
| `dirs` | `6` | 配置目录定位 | infra | 活跃 | Win/Linux 路径差异 | 自实现 `std::env` 分支 |
| `pretty_assertions` | `1`（dev） | 断言差异可读 | tests | 活跃 | 无 | 去掉依赖即可 |
| `tempfile` | `3`（dev） | 单测临时目录注入（S0-5 起在用） | tests / 各层 `#[cfg(test)]` 区块 | 活跃 | 无 | 去掉依赖即可 |

### 计划引入（尚未进 `Cargo.toml`，勿提前加）

| crate | 引入 Sprint | 用途 | 体积/风险备注 |
|---|---|---|---|
| `fltk` | S3 | 自绘 UI | 静态编译，Linux 需 X11 + pango/cairo 运行库（R-07，完整清单见「💻 系统要求」；引入后须用真实产物 `ldd` 复验该清单） |
| `indexmap` | S1/S2 | 有序字段承载 | `noyalib::Mapping` 已是 `IndexMap`，先确认能否直接复用再决定加依赖 |
| `image` | S4 | PNG/JPEG/WebP/GIF 解码 | 需关闭非必需特性以省体积（S5-5） |
| `resvg` / `usvg` / `tiny-skia` | S4 | SVG 栅格化 | R-02：可能撑破 15 MB，S5-5 实测后决定降级路径 |

### 版本与可复现约定

- `Cargo.lock` 必须提交，CI 全程 `--locked`；上表的 caret 版本只是「允许 `cargo update` 修 CVE」的通道，不是自动升级许可。
- CI 编译缓存用 `actions/cache` 缓存 cargo 目录，**不用 sccache**：当前依赖图只有个位数 crate，`Compile hits` 天然可能为 0，拿它当验收会出现「流水线正常但验收失败」。S3 引入 fltk 后若瓶颈转移到 CMake 侧再评估（sccache 对它无效），顺序仍是先改 tech-plan §11.1 再动 workflow —— 依据见 ADR-011。
- `noyalib` 属 0.0.x：每次 `cargo update` 前跑 `cargo update --dry-run -p noyalib` 看目标版本，升级后必须重跑 `scripts/verify-s0-2.sh` 与 `tests/dependency_smoke.rs`（后者固化了 ADR-008 的实测语义）。
- MSRV：`Cargo.toml` 的 `rust-version = "1.86"`（由 `noyalib` 要求）。`rust-toolchain.toml` 保持浮动 `stable`——写死具体版本号会让 rustup 下载版本化通道，实测阻塞构建 10 分钟以上。
- 已归档的 `serde_yaml` / `serde_yml` 由门禁脚本禁止回流。
- 分层禁令由 `scripts/check-layering.sh` 强制（四层全覆盖：import、完整限定路径、花括号多段三类命中形态；先剥注释再匹配，`main.rs`/`tests/` 不判定）。
  rustfmt 会把超长的 `use` 树拆成多行，所以除逐行匹配外还有一遍「压平匹配」；层目录缺失、层内无 `.rs` 文件、检查器自身执行失败都退出非 0。
  门禁自身的可失败性由 `bash scripts/check-layering.sh --self-test` 看护（152 项断言，约 30 s，fixture 建在临时目录，不改工作树；另有 16 个针对脚本自身的变异体全部被抓到）。真实仓库扫描本身 < 1 s。
- 当前依赖树规模：`cargo tree --locked` 共 35 个包（`cargo tree -d` 无重复版本，由门禁断言看护）。

---

## 🐛 反馈与建议

如果你遇到问题或有功能建议，欢迎提交 Issue。  
请附上你的操作系统、Keypeek 版本，以及出问题的 YAML 片段（如有）。

---

## 📄 许可证

MIT / Apache-2.0（以实际发布为准）

---

**Keypeek（键览）** — 让快捷键查询变得简单。
