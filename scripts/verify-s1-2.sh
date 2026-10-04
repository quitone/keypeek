#!/usr/bin/env bash
# S1-2 契约门禁：键帽拆分主流程骨架（sprint-plan.md S1-2 三条验收 + tech-plan §5.1 步骤 1–3）。
# 模板逐字对照 verify-s1-1.sh（其本身对照 verify-s0-6.sh）：
#   - rules 与 expected_rule_pairs 互校，删规则即失败；
#   - 失败按子断言 id 记账（R3[plus-split] 而非整条 R3）——删一条子断言，其变异体必让 self-test 期望集对不上；
#   - 字面基准数组（forbidden 7 / required 5）长度与去重机械守卫；
#   - --self-test 变异体 M1~M16 证明每条子断言可证伪，诱饵 D1~D5 证明不误报，keycap.rs 缺失 fail-closed；
#   - R6 委托 check-layering.sh。
# 检查一律在**先截 test 区、再去注释**的文本上进行（截断在剥离前，顺序不可反；
# strip_comments awk 状态机与 check-layering.sh 同源）。
# 全部规则状态无关（钉签名/token/接线/禁令文本，不钉占位输出形态），S1-4 翻转后可安全回跑。
set -uo pipefail

rules=(
  "R1|split_keycaps 契约签名逐字在位（pub fn split_keycaps(keys: &str) -> Vec<String>，sprint-plan S1-2 原文）"
  "R2|非 test 区禁止性扫描：unwrap( / expect( / panic! / todo! / unimplemented! / get_unchecked / 切片索引 七子断言，去注释+区段截断后扫（验收第三条的静态面）"
  "R3|管线 token 在位：split_whitespace() / char_indices() / flat_map(split_combo)+flat_map(resolve_segment) 共用 chain id / '<' / '+'（换 split(' ') 或 '-' 切分即红，§5.1 步骤 1–3 与「- 只在 <...> 内」推导）"
  "R4|domain/mod.rs 恰好一行 pub mod keycap;（缺失/重复/改名皆红）"
  "R5|CI 接线：check job 存在 S1-2 keycap skeleton gate step 且指向本脚本（脚本没接进流水线=门禁形同虚设）"
  "R6|分层禁令委托：check-layering.sh 对四层必须全绿（新 keycap.rs 自动进扫描面）"
)
expected_rule_pairs='R1 R2 R3 R4 R5 R6'

forbidden_ids=(unwrap expect panic! todo! unimplemented! get_unchecked index)
required_ids=(split-whitespace angle-scan chain lt plus-split)

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

# 字面基准长度也是契约：缩短数组 = 悄悄删子断言（S1-16 同族口子）。
if ((${#forbidden_ids[@]} != 7)) || ((${#required_ids[@]} != 5)); then
  echo "GATE-BROKEN: 基准数组长度与契约不符（forbidden 7 / required 5）"
  exit 1
fi
if [[ "$(printf '%s\n' "${forbidden_ids[@]}" | sort -u | wc -l)" -ne 7 ]]; then
  echo "GATE-BROKEN: forbidden_ids 含重复项，子断言会互相掩盖"
  exit 1
fi
if [[ "$(printf '%s\n' "${required_ids[@]}" | sort -u | wc -l)" -ne 5 ]]; then
  echo "GATE-BROKEN: required_ids 含重复项，子断言会互相掩盖"
  exit 1
fi

# ---------------------------------------------------------------- 注释剥离（与 check-layering.sh 同源）
strip_comments() {
  awk '
    {
      line = $0; res = ""; i = 1; len = length(line)
      while (i <= len) {
        c = substr(line, i, 1)
        if (inblock) {
          if (c == "*" && substr(line, i, 2) == "*/") { inblock = 0; i += 2 } else { i++ }
          continue
        }
        if (c == "/" && substr(line, i, 2) == "//") { break }
        if (c == "/" && substr(line, i, 2) == "/*") { inblock = 1; i += 2; continue }
        res = res c; i++
      }
      print res
    }
  ' "$1"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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
  local keycap="$root/src/domain/keycap.rs"
  local modrs="$root/src/domain/mod.rs"
  local ci="$root/.github/workflows/ci.yml"
  local body="$WORK/keycap.body"

  if [[ ! -f "$keycap" ]]; then
    # fail-closed：文件缺失时相关规则整体红，不因「无内容可查」变绿；R6 不连坐（其余文件仍在）
    fail R1[keycap-missing] "src/domain/keycap.rs 不存在"
    fail R2[keycap-missing] "src/domain/keycap.rs 不存在"
    fail R3[keycap-missing] "src/domain/keycap.rs 不存在"
  else
    # 先截 test 区、再剥注释（顺序不可反，§5.2 前置截断）
    awk '/^#\[cfg\(test\)\]$/{exit} {print}' "$keycap" > "$WORK/keycap.pretest"
    strip_comments "$WORK/keycap.pretest" > "$body"

    # --- R1 契约签名逐字
    grep -qF 'pub fn split_keycaps(keys: &str) -> Vec<String>' "$body" \
      || fail R1[signature] "split_keycaps 不再是契约签名逐字形态"

    # --- R2 非 test 区禁止性扫描（七子断言，id 与 forbidden_ids 平行）
    local pat idx
    pat=(   'unwrap(' 'expect(' 'panic!' 'todo!' 'unimplemented!' 'get_unchecked')
    idx=(   unwrap    expect    'panic!' 'todo!' 'unimplemented!' get_unchecked)
    local k
    for k in "${!pat[@]}"; do
      grep -qF "${pat[$k]}" "$body" && fail "R2[${idx[$k]}]" "非 test 区出现 ${pat[$k]}（无 panic 路径契约的静态面）"
    done
    # 切片索引：形如 ident[..]（vec![ / #[ 因 !/# 隔断不误报）
    grep -qE '\b[a-z_][a-z0-9_]*\[' "$body" \
      && fail R2[index] "非 test 区出现切片索引（门禁 R2 纪律，手写扫描器以 split_once 借位提取）"

    # --- R3 管线 token 在位（六个 grep、五个子断言 id，与 required_ids 一一对应）
    grep -qF 'split_whitespace()' "$body" || fail R3[split-whitespace] "步骤 1 的空白切分缺失（收窄回 split(' ') 即红，Q-6 取宽）"
    grep -qF 'char_indices()' "$body"     || fail R3[angle-scan] "步骤 2 的 char_indices 手写扫描器缺失"
    { grep -qF 'flat_map(split_combo)' "$body" && grep -qF 'flat_map(resolve_segment)' "$body"; } \
      || fail R3[chain] "flat_map 管线断裂（split_combo 与 resolve_segment 须串入主流程）"
    grep -qF "'<'" "$body" || fail R3[lt] "字面量 '<' 缺失（尖括号配对判定被删）"
    grep -qF "'+'" "$body" || fail R3[plus-split] "字面量 '+' 缺失（步骤 3 的加号切分被删或换成 '-'）"
  fi

  # --- R4 mod.rs 接线
  if [[ ! -f "$modrs" ]]; then
    fail R4[mod-missing] "src/domain/mod.rs 不存在"
  else
    local n
    n="$(grep -cx 'pub mod keycap;' "$modrs" || true)"
    if   ((n == 0)); then fail R4[mod-wiring] "domain/mod.rs 没有 pub mod keycap; 行"
    elif ((n > 1));  then fail R4[duplicate] "domain/mod.rs 出现 $n 行 pub mod keycap;（恰 1 行契约）"
    fi
  fi

  # --- R5 CI 接线自证
  if [[ ! -f "$ci" ]]; then
    fail R5[ci-missing] ".github/workflows/ci.yml 不存在"
  else
    grep -q 'S1-2 keycap skeleton gate' "$ci" || fail R5[step-name] "ci.yml 没有名为 S1-2 keycap skeleton gate 的 step"
    grep -q 'bash scripts/verify-s1-2.sh' "$ci" || fail R5[step-run] "gate step 不指向 scripts/verify-s1-2.sh"
  fi

  # --- R6 分层禁令委托
  if ! LAYERING_ROOT="$root" bash "$root/scripts/check-layering.sh" >"$WORK/layering.out" 2>&1; then
    fail R6[layering] "check-layering.sh 变红（输出见运行日志末行: $(tail -1 "$WORK/layering.out" 2>/dev/null || echo 无输出)）"
  fi
}

summary() {
  if ((${#FAILED[@]})); then
    # LC_ALL=C 钉死排序：self-test 的期望集按字节序书写，locale collation 会换位（S1-1 首跑实测）
    printf '失败规则: %s\n' "$(printf '%s\n' "${FAILED[@]}" | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
    exit 1
  fi
  printf '全部通过: %s\n' "$expected_rule_pairs"
  # 必须显式退出：self-test 会对副本再次调用本脚本，缺这行会穿透进 self-test 段
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
trap 'rm -rf "$ST_TMP" "$WORK"' EXIT
ST_PASS=0
ST_FAIL=0

make_copy() {
  rm -rf "$ST_TMP/repo"; mkdir -p "$ST_TMP/repo/.github/workflows"
  cp -R "$REPO_ROOT/src" "$ST_TMP/repo/src"
  cp -R "$REPO_ROOT/scripts" "$ST_TMP/repo/scripts"
  cp "$REPO_ROOT/.github/workflows/ci.yml" "$ST_TMP/repo/.github/workflows/ci.yml"
}

K="$ST_TMP/repo/src/domain/keycap.rs"
MO="$ST_TMP/repo/src/domain/mod.rs"
CI="$ST_TMP/repo/.github/workflows/ci.yml"

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
    echo "ST-FAIL [$name]: 期望 {$expect} 实得 {$got} (rc=$rc)"; ((ST_FAIL++)); return
  fi
}

echo "== S1-2 门禁 self-test =="

# 基线
make_copy; check_case "D0 基线未变异" "GREEN"

# M1 签名去掉 pub → 仅 R1[signature] 红
make_copy; sed -i 's/^pub fn split_keycaps/fn split_keycaps/' "$K"
check_case "M1 契约签名被改" "R1[signature]"

# M2 非 test 区注入 unwrap/expect → R2[expect] R2[unwrap]（期望集按 LC_ALL=C 字节序）
make_copy; sed -i '/^#\[cfg(test)\]/i let _ = keys.unwrap(); let _ = keys.expect("x");' "$K"
check_case "M2 unwrap/expect 注入" "R2[expect] R2[unwrap]"

# M3 非 test 区注入 panic!/todo!/unimplemented! → 三 id 齐红
make_copy; sed -i '/^#\[cfg(test)\]/i panic!("x"); todo!(); unimplemented!();' "$K"
check_case "M3 panic 类宏注入" "R2[panic!] R2[todo!] R2[unimplemented!]"

# M4 非 test 区注入切片索引 → 仅 R2[index]
make_copy; sed -i '/^#\[cfg(test)\]/i let _c = combo[0];' "$K"
check_case "M4 切片索引注入" "R2[index]"

# M5 非 test 区注入 get_unchecked → 仅 R2[get_unchecked]
make_copy; sed -i '/^#\[cfg(test)\]/i let _ = ptr.get_unchecked();' "$K"
check_case "M5 get_unchecked 注入" "R2[get_unchecked]"

# M6 '+' 切分换成 '-' → 仅 R3[plus-split]（同时证明 '-' 不在允许名单）
make_copy; sed -i "s/split('+')/split('-')/g" "$K"
check_case "M6 加号切分换成减号" "R3[plus-split]"

# M7 split_whitespace() 收窄为 split(' ') → 仅 R3[split-whitespace]（Q-6 取宽不许收窄）
make_copy; sed -i "s/split_whitespace()/split(' ')/" "$K"
check_case "M7 空白集收窄" "R3[split-whitespace]"

# M8 删 char_indices 行 → 仅 R3[angle-scan]（退化到 split('<') 索引重建的写法被抓）
make_copy; sed -i '/char_indices/d' "$K"
check_case "M8 手写扫描器被删" "R3[angle-scan]"

# M9 删 flat_map(resolve_segment) 行 → 仅 R3[chain]
make_copy; sed -i '/flat_map(resolve_segment)/d' "$K"
check_case "M9 flat_map 管线断裂" "R3[chain]"

# M10 删 mod.rs 接线行 → 仅 R4[mod-wiring]
make_copy; sed -i '/^pub mod keycap;$/d' "$MO"
check_case "M10 接线被删" "R4[mod-wiring]"

# M11 删 mod.rs → 仅 R4[mod-missing]
make_copy; rm -f "$MO"
check_case "M11 mod.rs 缺失 fail-closed" "R4[mod-missing]"

# M12 gate step 改名 → 仅 R5[step-name] 红
make_copy; sed -i 's/S1-2 keycap skeleton gate/S1-2 keycap note/' "$CI"
check_case "M12 gate step 改名" "R5[step-name]"

# M13 gate step 指向别的脚本 → 仅 R5[step-run] 红
make_copy; sed -i 's|bash scripts/verify-s1-2.sh|bash scripts/verify-s0-6.sh|' "$CI"
check_case "M13 gate step 不指向本脚本" "R5[step-run]"

# M14 keycap.rs 注入 use dirs; → 仅 R6[layering] 红（委托链真实生效，同 s1-1 M9）
make_copy; printf 'use dirs;\n' >> "$K"
check_case "M14 分层越界注入" "R6[layering]"

# M15 keycap.rs 整体缺失 → fail-closed 三红，不红 R6（其余文件仍在，分层照绿）
make_copy; rm -f "$K"
check_case "M15 keycap.rs 缺失 fail-closed" "R1[keycap-missing] R2[keycap-missing] R3[keycap-missing]"

# M16 删除含字面量 '<' 的两行 → 仅 R3[lt] 红（复核 I1 补：封堵单独删 lt 子断言的 S1-16 同族洞；
# 静态门禁不要求变异后可编译，M8 同法）
make_copy; sed -i "/'<'/d" "$K"
check_case "M16 lt 子断言被单独删除" "R3[lt]"

# --- 诱饵：该绿的必绿
# D1 注释里写签名同串、七个禁止形态与 split(' ') / '-' 讨论（剥离后不留痕，同喂 R1/R2/R3）
make_copy; sed -i '/^#\[cfg(test)\]/i // 反例：pub fn split_keycaps(keys: \&str) -> Vec<String> 与 unwrap( expect( panic! todo! unimplemented! get_unchecked 及 data[0] 切片索引；不用 split( '"'"' '"'"' ) 也不用 '"'"'-'"'"'。' "$K"
check_case "D1 注释讨论违例形态不留痕" "GREEN"

# D2 行尾注释诱饵（unwrap( 与 v[0] 只活在行尾注释里）
make_copy; sed -i '/^#\[cfg(test)\]/i let _ = keys.len(); // unwrap( 与 v[0] 只活在行尾注释' "$K"
check_case "D2 行尾注释掩护不误报" "GREEN"

# D3 在 cfg(test) 行之后注入 unwrap（证明区段截断真实生效，测试区豁免）
make_copy; sed -i '/^#\[cfg(test)\]/a let _ = x.unwrap();' "$K"
check_case "D3 test 区豁免截断在位" "GREEN"

# D4 ci.yml 该 step 前插一个无关 step（门禁不锁 step 总数，s1-1 D3 同形）
make_copy; sed -i 's@^      - name: S1-2 keycap skeleton gate@      - name: Docs preview\n        run: echo ok\n\n      - name: S1-2 keycap skeleton gate@' "$CI"
check_case "D4 新增无关 step 不误报" "GREEN"

# D5 pub mod keycap; 挪到 mod.rs 末行（顺序非契约）
make_copy; sed -i '/^pub mod keycap;$/d' "$MO"; printf 'pub mod keycap;\n' >> "$MO"
check_case "D5 接线行位置无关" "GREEN"

echo "== self-test 结果: PASS=$ST_PASS FAIL=$ST_FAIL =="
((ST_FAIL == 0)) || exit 1
