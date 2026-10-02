# AGENTS.md

Keypeek（键览）：跨平台只读快捷键浏览桌面工具（Rust + fltk-rs）。当前为 Sprint 0 脚手架阶段（仅空模块骨架，无业务代码）。全部规划文档为中文，界面语言为中文。

## 文档即契约（动手前先读）

**真源在 wiki，不在本仓库**（2026-10-02 迁出）：

- [PRD](https://github.com/quitone/keypeek/wiki/PRD) — 产品需求与数据模型（YAML 结构、字段规则、九条键帽用例）
- [Tech-Plan](https://github.com/quitone/keypeek/wiki/Tech-Plan) — 架构、ADR、CI 强制依赖规则
- [Sprint-Plan](https://github.com/quitone/keypeek/wiki/Sprint-Plan) — 任务与验收标准
- [Home](https://github.com/quitone/keypeek/wiki/Home) / [Traceability](https://github.com/quitone/keypeek/wiki/Traceability) — 导航页与需求追踪矩阵（这两页由 `gen.py` 从 Sprint-Plan 机械汇总生成，别手工改）

本机 `specification-doc/*.md` 只是**工作副本**，已在 `.gitignore` 里，`git ls-files` 查不到它们。三种路径写法指的是同一份东西：wiki 页名 `PRD` / 工作副本 `specification-doc/prd.md` / `gen.py` 产物 `wiki/PRD.md`；历史文档与 issue 里出现的 `specification-doc/...` 一律按此理解。

改文档的动作序：编辑工作副本 → `python3 /tmp/keypeek-github/gen.py <本仓库> /tmp/keypeek-github` 刷新草稿 → `REPO_DIR=<本仓库> FORCE=1 DRY_RUN=0 bash /tmp/keypeek-github/scripts/03-wiki.sh` 推 wiki（**只有确认本机较新时才加 FORCE**，否则 wiki 上的较新修订会被过期草稿吃掉）→ 必要时 `MODE=update` 同步 issue 正文。

代价要认：wiki 侧编辑**没有 PR 评审**，CI 也不读这三份文档（`scripts/` 与 `.github/` 里没有任何引用）。回滚靠 wiki 仓库自身的历史：`git log -p Sprint-Plan.md`。

## 分层单体结构（tech-plan §2）

依赖方向只允许自上而下：`main（组合根） → ui / infra → app（状态机） → domain（纯逻辑）`。

每层有硬性依赖禁令（见 `src/*/mod.rs` 头注释，tech-plan §2.2 / §11.2，由 `scripts/check-layering.sh` 在 CI 强制，越界阻塞合并）：

| 层 | 禁止依赖 |
|---|---|
| domain | fltk、std::fs、dirs（`noyalib::Value` 属允许列，S0-3 定案） |
| app | fltk、std::fs、noyalib |
| infra | fltk |
| ui | std::fs、noyalib、dirs |

YAML 能力由 `noyalib` 提供（ADR-008，`serde_yaml` 已归档不用）；禁令同样覆盖它的兼容路径 `noyalib::compat::serde_yaml`。

新增任何 `use` / 跨层调用前先核对上表。

## 构建与验证

- 工具链由 `rust-toolchain.toml` 固定：stable + rustfmt + clippy（channel 保持浮动 `stable`，写死具体版本号会让 rustup 去下载版本化通道，本机实测阻塞构建 10 分钟以上）
- MSRV 由 `Cargo.toml` 的 `rust-version = "1.86"` 声明（`noyalib` 0.0.51 的硬性要求）
- CI 缓存 key = `[os, rustc -vV 的 release 行, hashFiles('Cargo.lock')]`。**不要**改成 `hashFiles('rust-toolchain.toml')`：该文件内容恒为 `channel = "stable"`，编译器版本变了哈希不变，它提供不了 AGENTS.md 曾声称的保护。错配只浪费编译时间（cargo 指纹本身含编译器哈希），不是正确性问题
- CI 流水线：`.github/workflows/ci.yml`，job = `check`（ubuntu-24.04，全部静态检查与三道门禁）+ `build`（windows-2022 矩阵轴，只 `cargo build --locked`）+ `ci-required`（汇总，分支保护只把这个 check 名设为 required）；所有 action 钉到 40 位 commit SHA，禁用 `@vN`/`@main` 可变标签与 `*-latest` runner
- 远端为 `github.com/quitone/keypeek`（public），**默认分支是 `master`**：写 `push: branches:` 时漏掉 `master` 会让主干推送静默不触发 CI（首跑实测踩过，现由 `verify-s0-4.sh` R2 三条断言看护）；分支保护的 required check 只设 `ci-required`（`strict=false`、`enforce_admins=false`）
- 门禁有效性已有真实证据，改 CI 时不要退化：主干 run `36983307319` 全绿、同 commit 复跑命中目录缓存；探针 run `36984104277` 证明 `src/app` 越界引用 `noyalib` 只让分层 step 变红并阻塞合并（`mergeStateStatus=BLOCKED`），其余 step 保持绿
- 流水线契约门禁：`bash scripts/verify-s0-4.sh`（14 组语义断言，同时被 CI 的 check job 调用）+ `bash scripts/verify-s0-4.sh --self-test`（35 项：27 个变异体/破坏样例各自以对应规则号变红、`&&` / 注释 `&` / `>&2` / `${{ }}` / YAML 锚点诱饵必须全绿、结构缺失 fail-closed）；改断言必须同步 `rules` 与 `expected_rule_pairs`
- 改 CI 时的既有约束：分层检查依赖 GNU grep，只能放 ubuntu job；`cargo audit` 与 dependabot 属 S1，启用前必须先改 tech-plan §11.1；size-guard 属 S5-4
- CI 的三处与原方案不符的取舍（不用 sccache 改用目录缓存、build 矩阵只留 Windows、audit/dependabot 归 S1）是 **ADR-011** 的决策内容，不要当成随手改文档回滚；回退的前提也是先改 §11.1
- 脚手架验收门禁：`scripts/verify-s0-1.sh`（fmt → build → test → clippy `-D warnings` → 文件存在性检查）
- 分层禁令检查：`bash scripts/check-layering.sh`（扫四层，真实仓库 <1s）+ `bash scripts/check-layering.sh --self-test`（含 152 项可证伪断言，约 30s，fixture 建在 `mktemp -d`）；改禁令必须同步 tech-plan §2.2、脚本 `rules` 与 `expected_rule_pairs`
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