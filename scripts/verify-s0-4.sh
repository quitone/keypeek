#!/usr/bin/env bash
# S0-4 流水线契约门禁：把「CI 应该长什么样」变成能失败断言（tech-plan §11.1 / §11.2）。
#
# 为什么需要它：CI 在没有真实运行前本机跑不了；若没有本地证据，S0-4 的验收就等于
# 「我相信这份 YAML 是对的」。本脚本对 .github/workflows/ci.yml 做语义检查，覆盖
# 结构（必需 job 与 needs 图）、供应链（action 钉 SHA、最小权限）、禁令（后台 &、
# 启动服务器、continue-on-error）与缓存 key 的可证伪形态。CI 的 check job 也调用它。
#
# 分工：YAML 语法与 schema 合法性由 actionlint 负责（本机未安装时打 [not-run]，
# 既不静默跳过，也不因此失败）；本脚本只做 actionlint 覆盖不了的语义禁令。
#
# 用法：
#   bash scripts/verify-s0-4.sh                # 检查真实仓库
#   bash scripts/verify-s0-4.sh --self-test    # 证明上面的断言真的会失败
#   KEYPEEK_WORKFLOW=/path/ci.yml ...          # fixture 注入点
set -uo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
WF="${KEYPEEK_WORKFLOW:-$REPO_ROOT/.github/workflows/ci.yml}"
VIOL=0
TMP=""

# ---- 规则表：与 --self-test 的变异体一一对应。改规则必须同时改 expected_rule_pairs ----
rules=(
  "R1|workflow 结构完整（jobs 段与 check/build/ci-required 三个 job）"
  "R2|触发完整（pull_request 与主干 push，master/main 都要在列）"
  "R3|最小权限（permissions.contents 为 read 且不得为 write）"
  "R4|action 钉到 40 位 commit SHA"
  "R5|分层门禁两个 step 齐全（scan 与 --self-test）"
  "R6|分层检查只在 ubuntu job（依赖 GNU grep）"
  "R7|cargo build/test/clippy/tree 一律 --locked"
  "R8|Windows 轴用显式镜像标签且全仓无 latest"
  "R9|缓存 key 同时含编译器版本与 Cargo.lock 哈希"
  "R10|命令无后台 & 操作符"
  "R11|无启动服务器/守护/掩盖失败的命令形态"
  "R12|全仓无 continue-on-error（本轮没有豁免白名单）"
  "R13|ci-required 依赖 check 与 build 且 if: always()"
  "R14|check job 调用本地 parity 门禁（verify-s0-2 / verify-s0-4）"
)
# 独立字面基准：规则 id 清单与条数。删一条 rules 却不改这里 → self-test 失败。
expected_rule_pairs='R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12 R13 R14'
expected_rule_count=14

cleanup() {
  if [ -n "$TMP" ] && [ -z "${KEEP_TMP:-}" ]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT

die_tool() {
  printf '[tool-error] %s\n' "$*" >&2
  exit 3
}

# ---- 装载：整份 workflow 与按 job 切片，全部保留原始行号（tab 分隔）------------------
tabify() { awk '{ printf "%d\t%s\n", NR, $0 }' "$1" > "$2" || die_tool "tabify $1"; }

split_jobs() {
  awk -v outdir="$TMP" '
    BEGIN { injobs = 0; cur = "" }
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    injobs && /^[^[:space:]#]/ {
      if (cur != "") { close(cur); cur = "" }
      injobs = 0
    }
    injobs {
      if ($0 ~ /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        if (cur != "") close(cur)
        name = $0
        gsub(/^[[:space:]]+|[[:space:]:]+$/, "", name)
        cur = outdir "/job_" name ".tsv"
        print name >> (outdir "/jobs.txt")
        printf "%d\t%s\n", NR, $0 > cur
        next
      }
      if (cur != "") printf "%d\t%s\n", NR, $0 > cur
    }
  ' "$WF" || die_tool "split_jobs"
}

split_top() {
  awk -v outdir="$TMP" '
    BEGIN { cur = "" }
    {
      if ($0 ~ /^on:[[:space:]]*$/) { cur = outdir "/block_on.tsv" }
      else if ($0 ~ /^permissions:[[:space:]]*$/) { cur = outdir "/block_permissions.tsv" }
      else if ($0 ~ /^[^[:space:]#]/) { if (cur != "") { close(cur); cur = "" } }
      if (cur != "") printf "%d\t%s\n", NR, $0 > cur
    }
  ' "$WF" || die_tool "split_top"
}

# ---- 报告：违规行以规则号开头，self-test 据此判定「因正确的原因变红」-----------------
report() { # report <rule> <title> <line> <content>
  printf '[violation] %s %s  %s:%s: %s\n' "$1" "$2" "$WF" "$3" "$4"
  VIOL=$((VIOL + 1))
}
report_absent() { # report_absent <rule> <title>
  printf '[violation] %s %s  %s:-\n' "$1" "$2" "$WF"
  VIOL=$((VIOL + 1))
}

# run_prog <rule> <title> <awk-program> <tsv>：awk-program 每命中一条打印 "行号\t原文"
run_prog() {
  local rule="$1" title="$2" prog="$3" file="$4" out rc ln content
  if [ ! -s "$file" ]; then
    report_absent "$rule" "$title（片段缺失或为空：$(basename "$file")）"
    return
  fi
  out="$(awk -F'\t' "$prog" "$file" 2>&1)"; rc=$?
  if [ "$rc" -ge 2 ]; then
    die_tool "规则 $rule 的 awk 执行失败 rc=$rc：$out"
  fi
  if [ -n "$out" ]; then
    while IFS=$'\t' read -r ln content; do
      [ -z "$ln" ] && continue
      report "$rule" "$title" "$ln" "$content"
    done <<< "$out"
  fi
}

# 只看非注释行（YAML 注释里的 `&` / nohup 不可能真的执行）。
# 注意：切片文件每行形如 "行号\t原文"，所以所有匹配一律走 $2 —— 用 $0 会被行号前缀
# 打掉锚点（实测让 R2/R8/R9/R13 同时静默失效，是这份脚本自己的第一批变异样本）。
CODE_ONLY='$2 !~ /^[[:space:]]*#/'
HAS_PR='BEGIN{hit=0} { if ($2 ~ /^[[:space:]]*-?[[:space:]]*pull_request:/) hit=1 } END{ if (!hit) print "0\t<pull_request 未出现>" }'
HAS_PUSH_MASTER='BEGIN{hit=0} { if ($2 ~ /branches:.*master/) hit=1 } END{ if (!hit) print "0\t<push 触发未含 master>" }'
HAS_PUSH_MAIN='BEGIN{hit=0} { if ($2 ~ /branches:.*main/) hit=1 } END{ if (!hit) print "0\t<push 触发未含 main>" }'
HAS_READ='BEGIN{hit=0} { if ($2 ~ /contents:[[:space:]]*read/) hit=1 } END{ if (!hit) print "0\t<contents: read 未出现>" }'
HAS_SCAN='BEGIN{hit=0} { if ($2 ~ /scripts\/check-layering\.sh[[:space:]]*$/) hit=1 } END{ if (!hit) print "0\t<缺 scan step>" }'
HAS_SELFTEST='BEGIN{hit=0} { if ($2 ~ /check-layering\.sh[[:space:]]+--self-test/) hit=1 } END{ if (!hit) print "0\t<缺 self-test step>" }'
HAS_WIN='BEGIN{hit=0} { if ($2 ~ /^[[:space:]]*-?[[:space:]]*windows-[0-9]/) hit=1 } END{ if (!hit) print "0\t<windows 镜像未显式声明>" }'
HAS_KEY='BEGIN{hit=0} { if ($2 ~ /^[[:space:]]*key:/) hit=1 } END{ if (!hit) print "0\t<无 key: 行>" }'
HAS_ALWAYS='BEGIN{hit=0} { if ($2 ~ /if:[[:space:]]*always\(\)/) hit=1 } END{ if (!hit) print "0\t<缺 if: always()>" }'
HAS_NEED_CHECK='BEGIN{hit=0} { if ($2 ~ /^[[:space:]]*-?[[:space:]]*check[[:space:]]*$/) hit=1 } END{ if (!hit) print "0\t<needs 无 check>" }'
HAS_NEED_BUILD='BEGIN{hit=0} { if ($2 ~ /^[[:space:]]*-?[[:space:]]*build[[:space:]]*$/) hit=1 } END{ if (!hit) print "0\t<needs 无 build>" }'
HAS_V02='BEGIN{hit=0} { if ($2 ~ /scripts\/verify-s0-2\.sh/) hit=1 } END{ if (!hit) print "0\t<缺 verify-s0-2 step>" }'
HAS_V04='BEGIN{hit=0} { if ($2 ~ /scripts\/verify-s0-4\.sh/) hit=1 } END{ if (!hit) print "0\t<缺 verify-s0-4 step>" }'

# ---- 断言主体 -----------------------------------------------------------------------
run_checks() {
  rm -f "$TMP/jobs.txt"
  split_jobs
  split_top
  tabify "$WF" "$TMP/wf.tsv"

  echo "== R1 结构完整 =="
  local need
  for need in check build ci-required; do
    if [ ! -s "$TMP/job_$need.tsv" ]; then
      report_absent R1 "缺少 job: $need"
    fi
  done

  echo "== R2 PR 触发与主干推送触发 =="
  run_prog R2 "on 段缺 pull_request" "$HAS_PR" "$TMP/block_on.tsv"
  run_prog R2 "push 触发缺 master（实测：只写 main 时推 master 不触发任何 run）" \
    "$HAS_PUSH_MASTER" "$TMP/block_on.tsv"
  run_prog R2 "push 触发缺 main（改名成 main 时主干推送会静默失效）" \
    "$HAS_PUSH_MAIN" "$TMP/block_on.tsv"

  echo "== R3 最小权限 =="
  run_prog R3 "permissions 出现 contents: write" \
    '$2 ~ /contents:[[:space:]]*write/ { print $1 "\t" $2 }' "$TMP/block_permissions.tsv"
  run_prog R3 "permissions 缺 contents: read" "$HAS_READ" "$TMP/block_permissions.tsv"

  echo "== R4 action 钉 SHA =="
  run_prog R4 "uses 未钉到 40 位 commit SHA" '
    $2 !~ /^[[:space:]]*#/ {
      i = index($2, "uses:")
      if (i > 0) {
        s = substr($2, i + 5)
        sub(/[[:space:]]+#.*$/, "", s)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        n = split(s, a, "@")
        bad = 0
        if (n != 2 || a[1] !~ /^[A-Za-z0-9._\/-]+\/[A-Za-z0-9._-]+$/) bad = 1
        if (a[2] !~ /^[0-9a-f]+$/ || length(a[2]) != 40) bad = 1
        if (bad) print $1 "\t" $2
      }
    }' "$TMP/wf.tsv"

  echo "== R5 分层门禁两个 step 齐全 =="
  run_prog R5 "check job 缺 check-layering.sh 扫描 step" "$HAS_SCAN" "$TMP/job_check.tsv"
  run_prog R5 "check job 缺 check-layering.sh --self-test" "$HAS_SELFTEST" "$TMP/job_check.tsv"

  echo "== R6 分层检查只在 ubuntu =="
  if [ -s "$TMP/jobs.txt" ]; then
    local jn f has_layering is_ubuntu
    while read -r jn; do
      [ -z "$jn" ] && continue
      f="$TMP/job_$jn.tsv"
      has_layering=$(awk -F'\t' '$2 ~ /check-layering/ { c++ } END { print c + 0 }' "$f")
      is_ubuntu=$(awk -F'\t' '$2 ~ /runs-on:[[:space:]]*ubuntu-/ { c++ } END { print c + 0 }' "$f")
      if [ "$has_layering" -gt 0 ] && [ "$is_ubuntu" -eq 0 ]; then
        report_absent R6 "job $jn 跑 check-layering 但 runs-on 不是 ubuntu-*"
      fi
    done < "$TMP/jobs.txt"
  else
    report_absent R6 "jobs 清单为空（结构缺失不得当成干净）"
  fi

  echo "== R7 --locked 全覆盖 =="
  local jt
  for jt in "$TMP"/job_*.tsv; do
    [ -e "$jt" ] || continue
    run_prog R7 "cargo 命令缺 --locked" \
      "$CODE_ONLY"' && $2 ~ /cargo[[:space:]]+(build|test|clippy|tree)/ && $2 !~ /--locked/ { print $1 "\t" $2 }' "$jt"
  done

  echo "== R8 Windows 轴与显式镜像标签 =="
  run_prog R8 "build 矩阵缺显式 Windows 镜像标签" "$HAS_WIN" "$TMP/job_build.tsv"
  run_prog R8 "出现浮动 runner 标签 latest" \
    '$2 ~ /latest/ { print $1 "\t" $2 }' "$TMP/wf.tsv"

  echo "== R9 缓存 key 可证伪 =="
  run_prog R9 "cache key 缺 hashFiles('Cargo.lock')" \
    '$2 ~ /^[[:space:]]*key:/ && $2 !~ /hashFiles\((.Cargo\.lock.|..Cargo\.lock..)\)/ { print $1 "\t" $2 }' "$TMP/wf.tsv"
  run_prog R9 "cache key 缺编译器版本（steps.*.outputs.*）" \
    '$2 ~ /^[[:space:]]*key:/ && $2 !~ /steps\.[A-Za-z0-9_-]+\.outputs\./ { print $1 "\t" $2 }' "$TMP/wf.tsv"
  run_prog R9 "没有任何 cache key 行" "$HAS_KEY" "$TMP/wf.tsv"

  echo "== R10 无后台 & =="
  run_prog R10 "命令含后台 & 操作符" \
    "$CODE_ONLY"' && $2 ~ /(^|[^&])&([[:space:]]|$)/ { print $1 "\t" $2 }' "$TMP/wf.tsv"

  echo "== R11 无服务器/守护/失败掩盖 =="
  run_prog R11 "出现禁止的命令形态" \
    "$CODE_ONLY"' && $2 ~ /nohup|setsid|http\.server|xvfb|--no-verify|python[0-9.]*[[:space:]]+-m|\|\|[[:space:]]*true([[:space:]]|$)/ { print $1 "\t" $2 }' "$TMP/wf.tsv"

  echo "== R12 无 continue-on-error =="
  run_prog R12 "出现 continue-on-error" \
    '$2 ~ /continue-on-error/ { print $1 "\t" $2 }' "$TMP/wf.tsv"

  echo "== R13 汇总 job 契约 =="
  run_prog R13 "ci-required 缺 if: always()" "$HAS_ALWAYS" "$TMP/job_ci-required.tsv"
  run_prog R13 "ci-required 的 needs 缺 check" "$HAS_NEED_CHECK" "$TMP/job_ci-required.tsv"
  run_prog R13 "ci-required 的 needs 缺 build" "$HAS_NEED_BUILD" "$TMP/job_ci-required.tsv"

  echo "== R14 本地 parity =="
  run_prog R14 "check job 未调用 verify-s0-2.sh" "$HAS_V02" "$TMP/job_check.tsv"
  run_prog R14 "check job 未调用 verify-s0-4.sh" "$HAS_V04" "$TMP/job_check.tsv"
}

# ---- self-test ---------------------------------------------------------------------
# canonical fixture 是独立字面量（不从真实 workflow 派生）：否则「真实文件怎么改都能过」
# 就是假绿。变异体逐条破坏一项契约，且必须报出对应规则号，防止因错误的原因变红。
canonical_workflow() {
  cat <<'FIXTURE'
name: Fixture CI

on:
  pull_request:
  push:
    branches: [master, main]

permissions:
  contents: read

jobs:
  check:
    name: check
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - id: toolchain
        run: echo "release=x" >> "$GITHUB_OUTPUT"
      - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
        with:
          path: ~/.cargo/registry/cache/
          key: cargo-${{ runner.os }}-${{ steps.toolchain.outputs.release }}-${{ hashFiles('Cargo.lock') }}
      - run: cargo build --locked
      - run: cargo test --locked
      - run: bash scripts/check-layering.sh
      - run: bash scripts/check-layering.sh --self-test
      - run: bash scripts/verify-s0-2.sh
      - run: bash scripts/verify-s0-4.sh
  build:
    name: build (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os:
          - windows-2022
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - id: toolchain
        run: echo "release=x" >> "$GITHUB_OUTPUT"
      - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
        with:
          path: ~/.cargo/registry/cache/
          key: cargo-${{ runner.os }}-${{ steps.toolchain.outputs.release }}-${{ hashFiles('Cargo.lock') }}
      - run: cargo build --locked
  ci-required:
    needs:
      - check
      - build
    if: always()
    runs-on: ubuntu-24.04
    steps:
      - run: exit 0
FIXTURE
}

ST_PASS=0
ST_FAIL=0
ST_DIR=""
declare -A ST_COVERED=()

st_run() {
  ST_OUT="$(KEYPEEK_WORKFLOW="$1" bash "$SCRIPT_PATH" 2>&1)"
  ST_RC=$?
}

expect_blocked() { # expect_blocked <rule> <说明> <fixture>
  st_run "$3"
  if [ "$ST_RC" -eq 0 ]; then
    echo "  FAIL [$1] 变异未被抓到：$2"
    ST_FAIL=$((ST_FAIL + 1))
  elif ! printf '%s' "$ST_OUT" | grep -qF "[violation] $1 "; then
    echo "  FAIL [$1] 脚本失败了，但不是这条规则报的（因错误的原因变红）：$2"
    printf '%s\n' "$ST_OUT" | grep -E '^\[(violation|tool-error)\]' | sed 's/^/        /'
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_COVERED["$1"]=1
    ST_PASS=$((ST_PASS + 1))
  fi
}

expect_clean() { # expect_clean <说明> <fixture>
  st_run "$2"
  if [ "$ST_RC" -ne 0 ]; then
    echo "  FAIL 假阳性[$1]"
    printf '%s\n' "$ST_OUT" | grep -E '^\[(violation|tool-error)\]' | sed 's/^/        /'
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
}

mutate() { # mutate <sed 表达式> → 基于 canonical 生成单点变异文件
  local f="$ST_DIR/wf.yml"
  canonical_workflow > "$f"
  sed -e "$1" "$f" > "$f.mut" || die_tool "sed 失败：$1"
  mv "$f.mut" "$f"
  printf '%s' "$f"
}

mutate_append() { # mutate_append <行...> → 在末尾追加（仍在最后一个 job 的缩进块内）
  local f="$ST_DIR/wf.yml" line
  canonical_workflow > "$f"
  for line in "$@"; do printf '%s\n' "$line" >> "$f"; done
  printf '%s' "$f"
}

self_test() {
  ST_DIR="$(mktemp -d)" || die_tool "mktemp -d 失败"
  TMP="$ST_DIR"
  echo "== self-test：fixture 建在 $ST_DIR（不碰工作树）=="

  echo "--- 0. canonical 必须全绿（独立字面基准）---"
  canonical_workflow > "$ST_DIR/canonical.yml"
  expect_clean "canonical fixture" "$ST_DIR/canonical.yml"

  echo "--- 0b. 真实仓库的 ci.yml 必须全绿 ---"
  st_run "$REPO_ROOT/.github/workflows/ci.yml"
  if [ "$ST_RC" -ne 0 ]; then
    echo "  FAIL 真实 workflow 违反契约："
    printf '%s\n' "$ST_OUT" | grep -E '^\[(violation|tool-error)\]' | sed 's/^/        /'
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi

  echo "--- 1. 假阳性诱饵：合法但容易被朴素 grep 误杀的写法必须全绿 ---"
  expect_clean "诱饵（&& / 注释里的 & 结尾 / >&2 重定向 / \${{}} / YAML 锚点 / 注释提禁令名）" \
    "$(mutate_append \
      '      - run: cargo build --locked && cargo tree --locked -d' \
      '      # 注释里出现行尾裸 & 号 &' \
      '      # 注释里提 nohup / xvfb-run / python -m 也不算' \
      '      - run: echo "stderr 重定向 a1>&2 不是后台操作符"' \
      '      - run: echo "表达式 ${{ needs.check.result }} 与锚点 &anchor"')"

  echo "--- 2. 变异体：每条规则至少一个，且必须以该规则编号变红 ---"
  expect_blocked R1 "删掉 ci-required job" "$(mutate '/^  ci-required:/,$d')"
  expect_blocked R2 "删掉 pull_request 触发" "$(mutate '/^  pull_request:$/d')"
  expect_blocked R2 "push 触发只留 main（回归本次实测到的不触发）" "$(mutate 's/branches: \[master, main\]/branches: [main]/')"
  expect_blocked R2 "push 触发只留 master" "$(mutate 's/branches: \[master, main\]/branches: [master]/')"
  expect_blocked R3 "contents: read 改成 write" "$(mutate 's/contents: read/contents: write/')"
  expect_blocked R3 "删掉 contents: read" "$(mutate '/^  contents: read$/d')"
  expect_blocked R4 "action 退回可变标签 @v7" \
    "$(mutate 's|checkout@3d3c42e5aac5ba805825da76410c181273ba90b1|checkout@v7|')"
  expect_blocked R4 "action SHA 被截短" \
    "$(mutate 's|checkout@3d3c42e5aac5ba805825da76410c181273ba90b1|checkout@3d3c42e5|')"
  expect_blocked R5 "删掉分层 self-test step" "$(mutate '/check-layering\.sh --self-test/d')"
  expect_blocked R5 "删掉分层 scan step" "$(mutate '/bash scripts\/check-layering\.sh$/d')"
  expect_blocked R6 "check job 挪到非 ubuntu runner" \
    "$(mutate '0,/runs-on: ubuntu-24\.04/s/runs-on: ubuntu-24\.04/runs-on: self-hosted/')"
  expect_blocked R7 "摘掉一个 --locked" "$(mutate 's/cargo build --locked/cargo build/')"
  expect_blocked R8 "矩阵退回 windows-latest" "$(mutate 's/- windows-2022/- windows-latest/')"
  expect_blocked R8 "删掉 Windows 矩阵轴" "$(mutate '/- windows-2022/d')"
  expect_blocked R9 "cache key 丢掉 Cargo.lock 哈希" "$(mutate "s/hashFiles('Cargo.lock')/x/")"
  expect_blocked R9 "cache key 丢掉编译器版本" "$(mutate 's/steps\.toolchain\.outputs\.release/x/')"
  expect_blocked R10 "追加行尾后台进程" "$(mutate_append '      - run: cargo build --locked &')"
  expect_blocked R10 "追加行中后台操作符" "$(mutate_append '      - run: cargo build --locked & sleep 1')"
  expect_blocked R11 "追加 nohup 守护" "$(mutate_append '      - run: nohup cargo build --locked')"
  expect_blocked R11 "用 || true 掩盖失败" "$(mutate_append '      - run: cargo test --locked || true')"
  expect_blocked R12 "给 step 加 continue-on-error" \
    "$(mutate 's/^      - run: cargo build --locked$/      - run: cargo build --locked\n        continue-on-error: true/')"
  expect_blocked R13 "needs 里删掉 build" "$(mutate '/^      - build$/d')"
  expect_blocked R13 "删掉 if: always()" "$(mutate '/^    if: always()$/d')"
  expect_blocked R14 "不再调用 verify-s0-2.sh" "$(mutate '/scripts\/verify-s0-2\.sh/d')"
  expect_blocked R14 "不再调用 verify-s0-4.sh" "$(mutate '/scripts\/verify-s0-4\.sh/d')"

  echo "--- 3. 结构缺失与文件异常必须 fail-closed ---"
  expect_blocked R1 "jobs 段整行被删" "$(mutate '/^jobs:$/d')"
  expect_blocked R3 "permissions 段整行被删" "$(mutate '/^permissions:$/d')"
  st_run "$ST_DIR/nonexistent.yml"
  if [ "$ST_RC" -eq 0 ]; then
    echo "  FAIL 不存在的 workflow 被判为通过"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_COVERED[R1]=1
    ST_PASS=$((ST_PASS + 1))
  fi
  : > "$ST_DIR/empty.yml"
  st_run "$ST_DIR/empty.yml"
  if [ "$ST_RC" -eq 0 ]; then
    echo "  FAIL 空 workflow 被判为通过"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_COVERED[R1]=1
    ST_PASS=$((ST_PASS + 1))
  fi

  echo "--- 4. 规则集与变异覆盖的字面基准 ---"
  local rule_count declared missing rid
  rule_count="${#rules[@]}"
  if [ "$rule_count" -ne "$expected_rule_count" ]; then
    echo "  FAIL rules 条数 $rule_count != 字面基准 $expected_rule_count"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  declared="$(printf '%s\n' $expected_rule_pairs | wc -w | tr -d ' ')"
  if [ "$declared" -ne "$rule_count" ]; then
    echo "  FAIL rules 与 expected_rule_pairs 条数不一致：$rule_count vs $declared"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  missing=""
  for rid in $expected_rule_pairs; do
    [ -n "${ST_COVERED[$rid]:-}" ] || missing="$missing $rid"
  done
  if [ -n "$missing" ]; then
    echo "  FAIL 以下规则没有任何变异体能触发失败：$missing"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
    echo "  规则覆盖 14/14"
  fi

  echo
  echo "self-test：$ST_PASS 通过 / $ST_FAIL 失败"
  [ "$ST_FAIL" -eq 0 ]
}

# ---- 入口 --------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  self_test
  rc=$?
  exit "$rc"
fi

if [ ! -f "$WF" ]; then
  printf '[violation] R1 workflow 结构完整  %s:- 文件不存在\n' "$WF"
  exit 1
fi
if [ ! -s "$WF" ]; then
  printf '[violation] R1 workflow 结构完整  %s:- 文件为空\n' "$WF"
  exit 1
fi

TMP="$(mktemp -d)" || die_tool "mktemp -d 失败"

if command -v actionlint >/dev/null 2>&1; then
  if ! actionlint "$WF"; then
    VIOL=$((VIOL + 1))
  fi
else
  printf '[not-run] actionlint 未安装：YAML schema 合法性本轮未验证（不记为通过，也不阻塞本脚本）\n'
fi

run_checks

echo
if [ "$VIOL" -gt 0 ]; then
  printf 'S0-4 契约门禁失败：%d 处违规\n' "$VIOL"
  exit 1
fi
echo "S0-4 契约门禁通过（14 条规则，$(grep -c . "$TMP/wf.tsv") 行 workflow 文本）"
