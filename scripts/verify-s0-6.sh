#!/usr/bin/env bash
# S0-6 契约门禁：README + 数据格式说明占位（sprint-plan.md:162-169 三条验收标准）。
# 惯例与 verify-s0-4 / verify-s0-5 / check-layering 一致：
#   - rules 与 expected_rule_pairs 互校，删规则即失败；
#   - 失败按**子断言 id**记账（R3[libxext6] 而非整条 R3），这样"删掉一条子断言"必然让
#     self-test 的期望集对不上 —— 吸取 S0-4 复盘 S1-16「切片删除」的教训；
#   - --self-test 用变异体证明每条子断言可证伪，诱饵样例证明不误报，结构缺失 fail-closed；
#   - 不依赖 python：AC1 的解析证据由 tests/readme_yaml.rs（noyalib，本 app 真正用的解析器）
#     在 CI 已有的 `cargo test --locked` step 里产出，本脚本只守"这条看护链没被拆掉"。
set -uo pipefail

rules=(
  "R1|AC1 看护链完整：README 有 yaml 围栏 + tests/readme_yaml.rs 存在且引用 README.md 与 noyalib"
  "R2|AC2 句形：快速开始与 FAQ 两节各有一条同句含「切换」「重启」（内容锚，不锁行号）"
  "R3|AC3 清单：13 项必需依赖逐个存在（系统要求与 FAQ 两处都要有）+ 条件项 + 来源句 + ldd not-run 声明"
  "R4|数据格式约定「.yaml 与 .yml 的取舍」在两节各出现一次（按 README 实际措辞断言）"
  "R5|依赖表清账：tempfile 属已引入表，不得出现在「计划引入」表"
  "R6|CI 接线：check job 有 S0-6 README gate step 且指向本脚本，cargo test --locked step 健在"
)
expected_rule_pairs='R1 R2 R3 R4 R5 R6'

# AC3 的权威清单：fltk-rs 上游 README「Runtime Dependencies / Linux」，核实日期 2026-10-04。
required_pkgs=(
  libx11-6 libxinerama1 libxft2 libxext6 libxcursor1 libxrender1 libxfixes3
  libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libpangoxft-1.0-0 libglib2.0-0 libfontconfig1
)
conditional_pkgs=(libglu1-mesa libgl1)

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------- 规则一致性自检
declare -a RULE_IDS=()
for entry in "${rules[@]}"; do RULE_IDS+=("${entry%%|*}"); done
actual_sorted="$(printf '%s\n' "${RULE_IDS[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
expected_sorted="$(printf '%s\n' ${expected_rule_pairs} | sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$actual_sorted" != "$expected_sorted" ]]; then
  echo "GATE-BROKEN: rules 与 expected_rule_pairs 不一致（改门禁必须两处同步）"
  echo "  rules 展开:   $actual_sorted"
  echo "  expected:     $expected_sorted"
  exit 1
fi

# 清单长度也是契约：缩短数组 = 悄悄删子断言（S1-16「切片删除」的同族口子），此处机械挡住。
if ((${#required_pkgs[@]} != 13)) || ((${#conditional_pkgs[@]} != 2)); then
  echo "GATE-BROKEN: 依赖数组长度与 AC3 契约不符（必需 13 / 条件 2），改清单须先重新取证上游"
  exit 1
fi
if [[ "$(printf '%s\n' "${required_pkgs[@]}" | sort -u | wc -l)" -ne 13 ]]; then
  echo "GATE-BROKEN: 必需依赖数组含重复项，子断言会互相掩盖"
  exit 1
fi

FAILED=()
fail() { # $1=子断言 id $2=原因
  [[ "$1" =~ ^R[0-9]+(\[[^]]+\])?$ ]] || { echo "GATE-BROKEN: 非法子断言 id '$1'"; exit 1; }
  local prefix
  [[ "$1" =~ ^(R[0-9]+) ]] && prefix="${BASH_REMATCH[1]}"
  if ! printf '%s\n' "${RULE_IDS[@]}" | grep -qx "$prefix"; then
    echo "GATE-BROKEN: 子断言 '$1' 的父规则 '$prefix' 未在 rules 中声明"
    exit 1
  fi
  FAILED+=("$1")
  echo "FAIL $1: $2"
}

# ---------------------------------------------------------------- 主检查
run_checks() {
  local root="$1"
  local readme="$root/README.md"
  local test_rs="$root/tests/readme_yaml.rs"
  local ci="$root/.github/workflows/ci.yml"

  # README 缺失 → fail-closed，AC 相关规则整体红（不因文件不在就"无内容可查"而变绿）
  if [[ ! -f "$readme" ]]; then
    local r
    for r in R1 R2 R3 R4 R5; do fail "${r}[readme-missing]" "README.md 不存在"; done
  else
    # 取区间文本：从匹配 start 的首行到下一个匹配 end 的行之前
    region() { # $1=start 正则 $2=end 正则
      awk -v s="$1" -v e="$2" '
        !seen && $0 ~ s {seen=1; inside=1; print; next}
        inside && $0 ~ e {inside=0; next}
        inside {print}
      ' "$readme"
    }
    local quickstart filesec faq sysreq dep_planned dep_introduced
    quickstart="$(region '^### 3[.] 查看更新' '^---')"
    filesec="$(region '^### 2[.] 放入你的快捷键' '^### ')"
    faq="$(region '^## ❓ 常见问题' '^---')"
    sysreq="$(region '^## 💻 系统要求' '^---')"
    dep_planned="$(region '^### 计划引入' '^### ')"
    dep_introduced="$(region '^### 已引入' '^### ')"

    # --- R1 AC1 看护链
    if ! grep -Eq '^[[:space:]]*```yaml' "$readme"; then
      fail R1[fence] "README 里没有 \`\`\`yaml 围栏（AC1 的最小示例被删光）"
    fi
    if [[ ! -f "$test_rs" ]]; then
      fail R1[test-file] "tests/readme_yaml.rs 不存在（AC1 的解析证据没人产了）"
    else
      grep -q 'README.md' "$test_rs" || fail R1[test-reads-readme] "readme_yaml.rs 不再读 README.md"
      grep -q 'noyalib' "$test_rs" || fail R1[test-uses-noyalib] "readme_yaml.rs 不再用 noyalib 解析"
    fi

    # --- R2 AC2 句形（同句含「切换」「重启」，两节各一条独立子断言）
    local ac2='切换[^。]*重启|重启[^。]*切换'
    printf '%s\n' "$quickstart" | grep -Eq "$ac2" \
      || fail R2[quickstart] "「3. 查看更新」一节没有「改 YAML 后切换 app 或重启」的同句表述"
    printf '%s\n' "$faq" | grep -Eq "$ac2" \
      || fail R2[faq] "「常见问题」一节没有「改 YAML 后切换 app 或重启」的同句表述"

    # --- R3 AC3 清单：逐个包名一条子断言，系统要求与 FAQ 两处都必须齐
    local pkg
    for pkg in "${required_pkgs[@]}"; do
      if ! printf '%s\n' "$sysreq" | grep -qF -- "$pkg"; then
        fail "R3[$pkg]" "「系统要求」缺运行时依赖 $pkg"
      elif ! printf '%s\n' "$faq" | grep -qF -- "$pkg"; then
        fail "R3[$pkg]" "「常见问题」的 apt 命令缺 $pkg"
      fi
    done
    for pkg in "${conditional_pkgs[@]}"; do
      printf '%s\n' "$sysreq" | grep -qF -- "$pkg" || fail "R3[$pkg]" "条件依赖 $pkg 未列出"
    done
    printf '%s\n' "$sysreq" | grep -q 'fltk-rs' \
      && printf '%s\n' "$sysreq" | grep -Eq '核实日期.*2026-10-04' \
      || fail R3[source] "清单缺来源与核实日期（fltk-rs README / 2026-10-04）"
    printf '%s\n' "$sysreq" | grep -q 'ldd' \
      && printf '%s\n' "$sysreq" | grep -q 'not-run' \
      || fail R3[not-run] "清单缺「未经 ldd 实测，记 not-run」的如实声明"

    # --- R4 .yaml / .yml 取舍（按 README 实际措辞，两节各一条）
    printf '%s\n' "$filesec" | grep -E '\.yaml.*\.yml' >/dev/null \
      || fail R4[filename-rule] "「2. 放入你的快捷键 YAML 文件」一节不再说明 .yaml/.yml 取舍"
    printf '%s\n' "$faq" | grep -E '\.yaml.*\.yml' >/dev/null \
      || fail R4[faq] "「常见问题」一节不再说明 .yaml/.yml 取舍"

    # --- R5 依赖表清账
    printf '%s\n' "$dep_planned" | grep -q 'tempfile' \
      && fail R5[not-planned] "tempfile 仍被列在「计划引入（尚未进 Cargo.toml）」表 —— 它已在 Cargo.toml 的 dev 依赖里"
    printf '%s\n' "$dep_introduced" | grep -q 'tempfile' \
      || fail R5[in-introduced] "tempfile 不在「已引入（Sprint 0）」表里"
  fi

  # --- R6 CI 接线（脚本存在但没接进流水线 = 门禁形同虚设，master/main 教训的同族）
  if [[ ! -f "$ci" ]]; then
    fail R6[ci-missing] ".github/workflows/ci.yml 不存在"
  else
    grep -q 'S0-6 README gate' "$ci" || fail R6[step-name] "ci.yml 没有名为 S0-6 README gate 的 step"
    grep -q 'bash scripts/verify-s0-6.sh' "$ci" || fail R6[step-run] "ci.yml 的 gate step 不指向 scripts/verify-s0-6.sh"
    grep -q 'cargo test --locked' "$ci" || fail R6[test-step] "ci.yml 缺 cargo test --locked step（AC1 解析证据的载体）"
  fi
}

summary() {
  if ((${#FAILED[@]})); then
    printf '失败规则: %s\n' "$(printf '%s\n' "${FAILED[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
    exit 1
  fi
  printf '全部通过: %s\n' "$expected_rule_pairs"
  # 必须显式退出：self-test 会对副本再次调用本脚本，缺这行会穿透进 self-test 段（verify-s0-5 首跑实测踩过）
  exit 0
}

# ---------------------------------------------------------------- 入口分发
if [[ "${1:-}" == "--self-test" ]]; then
  ROOT_DEFAULT="${2:-.}"
else
  ROOT_DEFAULT="${1:-.}"
fi

cd "$ROOT_DEFAULT" || { echo "GATE-BROKEN: 无法进入 $ROOT_DEFAULT"; exit 1; }
REPO_ROOT="$PWD"

if [[ "${1:-}" != "--self-test" ]]; then
  run_checks "$REPO_ROOT"
  summary
fi

# ---------------------------------------------------------------- self-test
ST_TMP="$(mktemp -d)"
trap 'rm -rf "$ST_TMP"' EXIT
ST_PASS=0
ST_FAIL=0

make_copy() {
  rm -rf "$ST_TMP/repo"; mkdir -p "$ST_TMP/repo/tests" "$ST_TMP/repo/.github/workflows"
  cp "$REPO_ROOT/README.md" "$ST_TMP/repo/README.md"
  cp "$REPO_ROOT"/tests/*.rs "$ST_TMP/repo/tests/"
  cp "$REPO_ROOT/.github/workflows/ci.yml" "$ST_TMP/repo/.github/workflows/ci.yml"
}

check_case() { # $1=用例名 $2=期望失败集（排序空格分隔，GREEN=无失败）
  local name="$1" expect="$2" out got
  out="$(bash "$SCRIPT_PATH" "$ST_TMP/repo" 2>&1)"
  local rc=$?
  if grep -q '^全部通过' <<<"$out"; then got="GREEN";
  elif grep -q '^失败规则:' <<<"$out"; then
    got="$(grep '^失败规则:' <<<"$out" | sed 's/^失败规则: //; s/ $//')"
  else
    echo "ST-FAIL [$name]: 门禁未给出结构化汇总（fail-closed 视为红）"; ((ST_FAIL++)); return
  fi
  if [[ $expect == "GREEN" && $got == "GREEN" && $rc -eq 0 ]]; then
    echo "ST-OK   [$name]: 绿（无误报）"; ((ST_PASS++))
  elif [[ $got == "$expect" && $rc -ne 0 ]]; then
    echo "ST-OK   [$name]: 红于 {$got}"; ((ST_PASS++))
  else
    echo "ST-FAIL [$name]: 期望 {$expect} 实得 {$got} (rc=$rc)"; ((ST_FAIL++))
  fi
}

echo "== S0-6 门禁 self-test =="

# 基线
make_copy; check_case "D0 基线未变异" "GREEN"

# M1 删掉 README 全部 yaml 围栏开头 → 仅 R1[fence] 红
make_copy; sed -i 's/^[[:space:]]*```yaml/```text/' "$ST_TMP/repo/README.md"
check_case "M1 最小示例围栏消失" "R1[fence]"

# M2 删掉解析看护测试 → 仅 R1[test-file] 红
make_copy; rm -f "$ST_TMP/repo/tests/readme_yaml.rs"
check_case "M2 AC1 看护测试被删" "R1[test-file]"

# M3 测试里不再引用 noyalib（换成外部解析器的假看护）→ 仅 R1[test-uses-noyalib] 红
make_copy; sed -i 's/noyalib/serde_yaml/g' "$ST_TMP/repo/tests/readme_yaml.rs"
check_case "M3 看护测试改用非本项目解析器" "R1[test-uses-noyalib]"

# M4 删快速开始 AC2 句（只删首次出现）→ 仅 R2[quickstart] 红
make_copy; awk '!done && /切换一下左侧的应用，或者重启/ {done=1; next} {print}' \
  "$ST_TMP/repo/README.md" > "$ST_TMP/repo/README.md.n" && mv "$ST_TMP/repo/README.md.n" "$ST_TMP/repo/README.md"
check_case "M4 快速开始不再说切换或重启" "R2[quickstart]"

# M5 删 FAQ AC2 句 → 仅 R2[faq] 红
make_copy; sed -i '/A：Keypeek 不监听文件变化/d' "$ST_TMP/repo/README.md"
check_case "M5 FAQ 不再说切换或重启" "R2[faq]"

# M6 从系统要求 apt 块删 libxext6 → R3[libxext6] 红（FAQ 仍有，故只看系统要求侧）
make_copy; sed -i '/^## 💻 系统要求/,/^---/s/ libxext6//' "$ST_TMP/repo/README.md"
check_case "M6 清单缺 libxext6" "R3[libxext6]"

# M7 从 FAQ 的 apt 命令删 libxrender1 → R3[libxrender1] 红（系统要求侧仍有）
make_copy; sed -i '/^## ❓ 常见问题/,/^---/s/ libxrender1//' "$ST_TMP/repo/README.md"
check_case "M7 FAQ 命令缺 libxrender1" "R3[libxrender1]"

# M8 删掉来源与核实日期句 → 仅 R3[source] 红
make_copy; sed -i '/清单来源：fltk-rs 上游 README/d' "$ST_TMP/repo/README.md"
check_case "M8 清单没有出处" "R3[source]"

# M9 删掉 ldd not-run 声明 → 仅 R3[not-run] 红
make_copy; sed -i '/与真实产物的一致性未经 `ldd` 实测/d' "$ST_TMP/repo/README.md"
check_case "M9 未实测结论被当成实测" "R3[not-run]"

# M10 删条件依赖两项 → R3[libglu1-mesa] R3[libgl1] 红
make_copy; sed -i 's/`libglu1-mesa`、`libgl1`/条件依赖见上游文档/' "$ST_TMP/repo/README.md"
check_case "M10 条件依赖未标注" "R3[libgl1] R3[libglu1-mesa]"

# M11 删快速开始的 .yaml/.yml 注意行 → 仅 R4[quickstart] 红
make_copy; sed -i '/^> 注意：只识别 `.yaml` 扩展名/d' "$ST_TMP/repo/README.md"
check_case "M11 .yaml/.yml 取舍（文件名规则节）丢失" "R4[filename-rule]"

# M12 删 FAQ 的 .yml 问答 → 仅 R4[faq] 红
make_copy; sed -i '/A：只支持 `.yaml`，不识别 `.yml`/d' "$ST_TMP/repo/README.md"
check_case "M12 .yaml/.yml 取舍（FAQ）丢失" "R4[faq]"

# M13 tempfile 被塞回「计划引入」表 → 仅 R5[not-planned] 红
make_copy; sed -i '/^### 计划引入/,/^### /s@^| `indexmap`@| `tempfile` | S0-5 | 单测临时目录注入 | dev 依赖 |\n| `indexmap`@' "$ST_TMP/repo/README.md"
check_case "M13 tempfile 重回计划引入表" "R5[not-planned]"

# M14 从「已引入」表删 tempfile 行 → 仅 R5[in-introduced] 红
make_copy; sed -i '/^| `tempfile` | `3`（dev）/d' "$ST_TMP/repo/README.md"
check_case "M14 tempfile 不在已引入表" "R5[in-introduced]"

# M15 ci.yml 里 gate step 改名 → 仅 R6[step-name] 红
make_copy; sed -i 's/S0-6 README gate/S0-6 docs note/' "$ST_TMP/repo/.github/workflows/ci.yml"
check_case "M15 gate step 改名" "R6[step-name]"

# M16 ci.yml 里 gate step 指向别的脚本 → 仅 R6[step-run] 红
make_copy; sed -i 's|bash scripts/verify-s0-6.sh|bash scripts/verify-s0-5.sh|' "$ST_TMP/repo/.github/workflows/ci.yml"
check_case "M16 gate step 不指向本脚本" "R6[step-run]"

# M17 ci.yml 删掉 cargo test step → 仅 R6[test-step] 红
make_copy; sed -i '/cargo test --locked/d' "$ST_TMP/repo/.github/workflows/ci.yml"
check_case "M17 AC1 解析证据的 step 被删" "R6[test-step]"

# M18 README.md 整体缺失 → fail-closed，R1~R5 各自红
make_copy; rm -f "$ST_TMP/repo/README.md"
check_case "M18 README 缺失 fail-closed" "R1[readme-missing] R2[readme-missing] R3[readme-missing] R4[readme-missing] R5[readme-missing]"

# --- 诱饵：该绿的必绿
# D1 追加一个合法的第二 yaml 示例（格式变化不触发任何断言）
make_copy; printf '\n```yaml\nextra: true\n```\n' >> "$ST_TMP/repo/README.md"
check_case "D1 追加合法 yaml 围栏" "GREEN"

# D2 无关段落里单独出现「重启」→ 必绿（R2 按节区间判定，不是全文关键词）
make_copy; sed -i '/^## 🔒 隐私与安全/i 顺手提一句：重启电脑并不能替代重新加载 YAML。\n' "$ST_TMP/repo/README.md"
check_case "D2 其它段落出现「重启」不误报" "GREEN"

# D3 系统要求里重复列出包名（写法差异/缩进变化）→ 必绿
make_copy; sed -i '/^## 💻 系统要求/a\'$'\n''  备注：libx11-6、libxext6、libxrender1 等包名在不同发行版可能带不同后缀。' "$ST_TMP/repo/README.md"
check_case "D3 包名重复出现不误报" "GREEN"

# D4 ci.yml 增加一个无关 step（门禁不锁 step 总数）→ 必绿
make_copy; sed -i 's@^      - name: S0-6 README gate@      - name: Docs preview\n        run: echo ok\n\n      - name: S0-6 README gate@' "$ST_TMP/repo/.github/workflows/ci.yml"
check_case "D4 新增无关 step 不误报" "GREEN"

# D5 脚本自身的注释里出现危险串（README 注释形态的诱饵由 awk 天然规避）→ 必绿
make_copy; printf '\n# 提醒：不要把它改成用 python 解析，CI 上的 PyYAML 不保证可用。\n' \
  > "$ST_TMP/repo/tests/readme_yaml.rs.n" && cat "$ST_TMP/repo/tests/readme_yaml.rs" >> "$ST_TMP/repo/tests/readme_yaml.rs.n" \
  && mv "$ST_TMP/repo/tests/readme_yaml.rs.n" "$ST_TMP/repo/tests/readme_yaml.rs"
check_case "D5 测试文件加注释不误报" "GREEN"

echo "== self-test 结果: PASS=$ST_PASS FAIL=$ST_FAIL =="
((ST_FAIL == 0)) || exit 1
