# AGENTS.md

Keypeek（键览）：跨平台只读快捷键浏览桌面工具（Rust + fltk-rs）。当前为 Sprint 0 脚手架阶段（仅空模块骨架，无业务代码）。全部规划文档为中文，界面语言为中文。

## 文档即契约（动手前先读）

- `prd.md` — 产品需求与数据模型（YAML 结构、字段规则、九条键帽用例）
- `tech-plan.md` — 架构、ADR、CI 强制依赖规则
- `sprint-plan.md` — 任务与验收标准

## 分层单体结构（tech-plan §2）

依赖方向只允许自上而下：`main（组合根） → ui / infra → app（状态机） → domain（纯逻辑）`。

每层有硬性依赖禁令（见 `src/*/mod.rs` 头注释，tech-plan §2.2 / §11.2 计划 CI grep 强制，越界阻塞合并）：

| 层 | 禁止依赖 |
|---|---|
| domain | fltk、std::fs、dirs |
| app | fltk、std::fs、serde_yaml |
| infra | fltk |
| ui | std::fs、serde_yaml、dirs |

新增任何 `use` / 跨层调用前先核对上表。

## 构建与验证

- 工具链由 `rust-toolchain.toml` 固定：stable + rustfmt + clippy
- 脚手架验收门禁：`scripts/verify-s0-1.sh`（fmt → build → test → clippy `-D warnings` → 文件存在性检查）
- 标准命令序：`cargo fmt --check` → `cargo build` → `cargo test` → `cargo clippy --all-targets -- -D warnings`
- `Cargo.lock` 已提交且需保持（CI 用 `--locked`）；`target/` 已 gitignore

## 业务约定（来自 PRD，易踩坑）

- 应用只读：无编辑/网络/文件监听/刷新入口；数据由使用者自维护 YAML
- 配置目录 `dirs::config_dir()/keypeek/`（Linux `~/.config/keypeek/`，Win `%APPDATA%\keypeek\`）
- 只认 `.yaml`（扩展名忽略大小写），**不认 `.yml`**；`settings.yaml` 是设置文件，不算 app
- 一个 `.yaml` = 一个 app，文件名 stem 即 AppId；目录只扫一层，不递归
- 条目字段用**有序列表**保留 YAML 出现顺序（列推导依赖），不用映射

## 测试策略

- 刻意取舍：domain 全自动纯函数单测 + UI 手工矩阵；FLTK 无成熟测试框架，不做 UI 自动化
- 硬门禁用例：PRD §5.5 键帽拆分九条 100% 通过、解析分级（F-04）、过滤语义（F-21/23/24）、图标安全（`../` 逃逸 / `http://` / 超大 / 含 `<script>` 的 SVG）

## 平台与 UI

- 交付：单文件可执行，Linux x64 + Win10 x64，行为需一致，平台差异只允许隔离在 `infra`
- UI 全自绘，深色默认 + 浅色两套主题，禁止依赖原生控件外观
- 自绘尺寸以 DPI 缩放因子为基准，**禁止硬编码像素**