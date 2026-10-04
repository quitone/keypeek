#!/usr/bin/env bash
# S1-3 契约门禁：已知键名表（sprint-plan.md:217-224 三条验收 + tech-plan.md:228 关键设计点 + ADR-009 tech-plan.md:648）。
# 骨架逐字对照 verify-s1-1.sh / verify-s0-6.sh：
#   - rules 与 expected_rule_pairs 互校，删规则即 GATE-BROKEN；
#   - 失败按子断言 id 记账（R1[Ctrl] 形态），字面基准数组带长度与去重守卫；
#   - --self-test：基线 GREEN + 每条规则 ≥1 变异体红于指定 id + 诱饵 GREEN + 文件缺失 fail-closed；
#   - R7 CI 接线自证、R8 委托 check-layering.sh。
# 全部断言**状态无关**（S1-1~S1-4 计划修订 #8）：钉表内容/条数/查表链路/注释/测试名/接线，
# 不钉「未命中=原样输出」这类占位行为，S1-4 落地后回跑本门禁必须绿。
set -uo pipefail

rules=(
  "R1|主表 35 条逐个在位且条数恰为 35（只扫 const KNOWN_KEY_NAMES 的数组区；35 条封闭集是开放契约的工程收敛，属实现决策 Q-4）"
  "R2|别名表恰含 pgdn/pgup 两对且规范形逐字在位（ADR-009 逐字举例 pgdn + 对称收敛 pgup，Q-4）"
  "R3|单字母禁令静态面：主表区与别名表区每个字符串条目都是 2 位以上 ASCII 字母数字；非 test 区无切片索引形态（含大写标识符，补 verify-s1-2 R2 只认小写标识符的盲区）"
  "R4|查表与归一化链路在位：lookup_key_name 签名、normalize_literal 签名、normalize_literal 体内调用 lookup_key_name、resolve_segment 的 Literal 臂接 normalize_literal"
  "R5|§5.1 关键设计点注释在位：紧邻主表上方的注释块内须出现 单字母 / g+s+a / S1-6 三个标记"
  "R6|五个状态无关验收测试名逐字在位（去注释后扫，注释里写同名不算；两个 …_until_s1_4 占位名刻意不进名单，否则与 S1-4 的强制翻转互斥）"
  "R7|CI 接线：check job 存在 S1-3 key name table gate step 且指向本脚本（脚本没接进流水线=门禁形同虚设）"
  "R8|分层禁令委托：check-layering.sh 对四层必须全绿（新增常量与函数自动进扫描面）"
)
expected_rule_pairs='R1 R2 R3 R4 R5 R6 R7 R8'

key_name_entries=(
  Ctrl Alt Shift Cmd Super Meta Leader LocalLeader
  Enter Esc Tab Space Backspace Delete Insert Home End
  PageUp PageDown Up Down Left Right
  F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12
)
alias_keys=(pgdn pgup)
alias_canonicals=(PageDown PageUp)
rationale_ids=(single-letter-keyphrase g-plus-s-plus-a s1-6-separate-table)
rationale_markers=('单字母' 'g+s+a' 'S1-6')
gated_test_names=(
  lookup_ctrl_hits
  lookup_single_letter_misses
  table_has_no_single_char_entries
  table_round_trips_to_canonical
  known_segment_normalized_in_pipeline
)

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

# 字面基准数组长度/去重同样是契约：缩短数组 = 悄悄删子断言（S1-16 教训）。
if ((${#key_name_entries[@]} != 35)); then
  echo "GATE-BROKEN: key_name_entries 不是 35 条（主表基准 = 23 非 F 键 + F1..F12）"
  exit 1
fi
if [[ "$(printf '%s\n' "${key_name_entries[@]}" | sort -u | wc -l)" -ne 35 ]]; then
  echo "GATE-BROKEN: key_name_entries 含重复项，子断言会互相掩盖"
  exit 1
fi
if ((${#alias_keys[@]} != 2)) || ((${#alias_canonicals[@]} != 2)); then
  echo "GATE-BROKEN: 别名基准数组不是 2 对（ADR-009 逐字 pgdn + 对称 pgup）"
  exit 1
fi
if ((${#rationale_ids[@]} != ${#rationale_markers[@]})) || ((${#rationale_ids[@]} != 3)); then
  echo "GATE-BROKEN: rationale 标记与 id 平行数组长度不一致（改一处必改两处）"
  exit 1
fi
if ((${#gated_test_names[@]} != 5)); then
  echo "GATE-BROKEN: gated_test_names 不是 5 项（R6 名单）"
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
  local ci="$root/.github/workflows/ci.yml"

  if [[ ! -f "$keycap" ]]; then
    # fail-closed：文件缺失时相关规则整体红，不因「无内容可查」变绿
    local r
    for r in R1 R2 R3 R4 R5 R6; do fail "${r}[keycap-missing]" "src/domain/keycap.rs 不存在"; done
  else
    strip_comments "$keycap" > "$WORK/stripped"
    awk '/^#\[cfg\(test\)\]$/{exit} {print}' "$WORK/stripped" > "$WORK/body"

    # 表区（只在去注释文本上取，注释里的同名串进不来）
    local name_region alias_region nl_body rs_body rs_flat
    name_region="$(awk '/^const KNOWN_KEY_NAMES:/{f=1; next} f && /^\];/{exit} f' "$WORK/stripped")"
    alias_region="$(awk '/^const KEY_ALIASES:/{f=1} f{print} f && /\];/{exit}' "$WORK/stripped")"

    # --- R1 主表：35 条逐个在位 + 条数恰为 35
    local t n
    for t in "${key_name_entries[@]}"; do
      grep -qE "\"${t}\"" <<<"$name_region" || fail "R1[$t]" "主表区缺条目 $t（tech-plan §5.1 步骤 4 的查表基准）"
    done
    n="$(grep -oE '"[A-Za-z0-9]+"' <<<"$name_region" | wc -l)"
    [[ "$n" == "${#key_name_entries[@]}" ]] || fail R1[arity] "主表条目数为 $n 而非 ${#key_name_entries[@]}（封闭集改动须走 Q-4 基准同步流程）"

    # --- R2 别名表：两对逐字 + 对数恰为 2
    local i k c
    for i in "${!alias_keys[@]}"; do
      k="${alias_keys[$i]}"; c="${alias_canonicals[$i]}"
      grep -qE "\(\"${k}\",[[:space:]]*\"${c}\"\)" <<<"$alias_region" \
        || fail "R2[$k]" "别名表缺 (\"$k\", \"$c\") 这一对（ADR-009 归一化基准）"
    done
    n="$(grep -oE '\("[A-Za-z0-9]+",[[:space:]]*"[A-Za-z0-9]+"\)' <<<"$alias_region" | wc -l)"
    [[ "$n" == "${#alias_keys[@]}" ]] || fail R2[arity] "别名表对数为 $n 而非 ${#alias_keys[@]}（扩别名须先记疑点再改基准）"

    # --- R3 单字母禁令的静态面 + 切片索引（大写标识符也扫）
    local bad
    bad="$(grep -oE '"[^"]*"' <<<"$name_region" | grep -vE '^"[A-Za-z0-9]{2,}"$' || true)"
    [[ -z "$bad" ]] || fail R3[no-single-char-name] "主表出现单字符/非 ASCII 字母数字条目: $(tr -d '\n' <<<"$bad")"
    bad="$(grep -oE '"[^"]*"' <<<"$alias_region" | grep -vE '^"[A-Za-z0-9]{2,}"$' || true)"
    [[ -z "$bad" ]] || fail R3[no-single-char-alias] "别名表出现单字符/非 ASCII 字母数字条目: $(tr -d '\n' <<<"$bad")"
    grep -qE '\b[A-Za-z_][A-Za-z0-9_]*\[' "$WORK/body" \
      && fail R3[no-index-ident] "非 test 区出现 ident[..] 索引形态（含 KNOWN_KEY_NAMES[..] 这类大写形态）"

    # --- R4 查表与归一化链路
    grep -qF "fn lookup_key_name(seg: &str) -> Option<&'static str>" "$WORK/body" \
      || fail R4[lookup-def] "lookup_key_name 的签名不再逐字在位"
    grep -qF 'fn normalize_literal(seg: &str) -> Vec<String>' "$WORK/body" \
      || fail R4[normalize-def] "normalize_literal 的签名不再逐字在位"
    nl_body="$(awk '/^fn normalize_literal/{f=1; next} f && /^\}/{exit} f' "$WORK/body")"
    grep -qF 'lookup_key_name(' <<<"$nl_body" \
      || fail R4[normalize-uses-lookup] "normalize_literal 不再调用 lookup_key_name（§5.1 步骤 4 的「整体匹配已知键名表」失守）"
    rs_body="$(awk '/^fn resolve_segment/{f=1; next} f && /^\}/{exit} f' "$WORK/body")"
    rs_flat="$(tr '\n' ' ' <<<"$rs_body")"
    grep -qE 'Segment::Literal\([a-z_]+\) => normalize_literal\(' <<<"$rs_flat" \
      || fail R4[literal-wired] "resolve_segment 的 Literal 臂没接 normalize_literal（S1-3 的接线要求）"

    # --- R5 关键设计点注释（扫原文，注释正是被看护对象）
    local doc m j
    doc="$(awk '
      /^const KNOWN_KEY_NAMES:/ { exit }
      /^[[:space:]]*\/\/\/?/ { buf = buf $0 "\n"; next }
      { buf = "" }
      END { printf "%s", buf }
    ' "$keycap")"
    for j in "${!rationale_markers[@]}"; do
      m="${rationale_markers[$j]}"
      grep -qF -- "$m" <<<"$doc" \
        || fail "R5[${rationale_ids[$j]}]" "主表注释块缺标记「$m」（tech-plan.md:228 要求注释说明为何排除单字母）"
    done

    # --- R6 状态无关测试名在位（去注释全文扫，注释里写名字不算数）
    local fn id
    for fn in "${gated_test_names[@]}"; do
      id="R6[$(tr '_' '-' <<<"$fn")]"
      grep -qE "^[[:space:]]*fn ${fn}\(\)" "$WORK/stripped" \
        || fail "$id" "缺测试 $fn（验收对账的行为面）"
    done
  fi

  # --- R7 CI 接线自证
  if [[ ! -f "$ci" ]]; then
    fail R7[ci-missing] ".github/workflows/ci.yml 不存在"
  else
    grep -q 'S1-3 key name table gate' "$ci" || fail R7[step-name] "ci.yml 没有名为 S1-3 key name table gate 的 step"
    grep -q 'bash scripts/verify-s1-3.sh' "$ci" || fail R7[step-run] "gate step 不指向 scripts/verify-s1-3.sh"
  fi

  # --- R8 分层禁令委托
  if ! LAYERING_ROOT="$root" bash "$root/scripts/check-layering.sh" >"$WORK/layering.out" 2>&1; then
    fail R8[layering] "check-layering.sh 变红（末行: $(tail -1 "$WORK/layering.out" 2>/dev/null || echo 无输出)）"
  fi
}

summary() {
  if ((${#FAILED[@]})); then
    # LC_ALL=C 钉死排序：self-test 期望集按字节序书写，locale collation 会换位（sprint-plan.md:201 实测教训）
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
CI="$ST_TMP/repo/.github/workflows/ci.yml"

check_case() { # $1=用例名 $2=期望失败集（LC_ALL=C 字节序，GREEN=无失败）
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

echo "== S1-3 门禁 self-test =="

# 基线
make_copy; check_case "D0 基线未变异" "GREEN"

# R1 主表
make_copy; sed -i '/^    "Ctrl",$/d' "$K"
check_case "M1 主表删 Ctrl" "R1[Ctrl] R1[arity]"
make_copy; sed -i 's/^    "Backspace",$/    "BackSpace",/' "$K"
check_case "M2 主表条目改名（条数不变）" "R1[Backspace]"
make_copy; sed -i '0,/^    "Home",$/s//    "Home",\n    "Home",/' "$K"
check_case "M3 主表重复条目" "R1[arity]"

# R2 别名表
make_copy; sed -i 's/, ("pgup", "PageUp")//' "$K"
check_case "M4 别名表删 pgup 对" "R2[arity] R2[pgup]"
make_copy; sed -i 's/("pgdn", "PageDown")/("pgdn", "PgDn")/' "$K"
check_case "M5 别名规范形偏离主表" "R2[pgdn]"

# R3 单字母禁令静态面 + 索引盲区
make_copy; sed -i '0,/^    "Ctrl",$/s//    "Ctrl",\n    "S",/' "$K"
check_case "M6 主表混入单字母 S" "R1[arity] R3[no-single-char-name]"
make_copy; sed -i 's/&\[("pgdn", "PageDown")/\&[("s", "Shift"), ("pgdn", "PageDown")/' "$K"
check_case "M7 别名表混入单字母 s" "R2[arity] R3[no-single-char-alias]"
make_copy; sed -i '/^#\[cfg(test)\]/i \    let _first = KNOWN_KEY_NAMES[0];' "$K"
check_case "M8 大写标识符切片索引（S1-2 R2 盲区）" "R3[no-index-ident]"

# R4 链路
make_copy; sed -i 's/Segment::Literal(text) => normalize_literal(text),/Segment::Literal(text) => vec![text.to_string()],/' "$K"
check_case "M9 Literal 臂退回占位" "R4[literal-wired]"
make_copy; sed -i '/^fn normalize_literal/,/^}/s/lookup_key_name(/unrelated_lookup(/' "$K"
check_case "M10 normalize_literal 断开查表" "R4[normalize-uses-lookup]"
make_copy; sed -i "s/fn lookup_key_name(seg: &str) -> Option<&'static str>/fn lookup_key_name(seg: \&str) -> Option<\&str>/" "$K"
check_case "M11 lookup 签名改写" "R4[lookup-def]"

# R5 注释
make_copy; sed -i '/S1-6/d' "$K"
check_case "M12 删两表分离的注释行" "R5[s1-6-separate-table]"
make_copy; sed -i 's/单字母/大小写/g' "$K"
check_case "M13 注释不再说明单字母禁令" "R5[single-letter-keyphrase]"

# R6 测试名
make_copy; sed -i 's/fn lookup_ctrl_hits/fn lookup_ctrl_hits_v2/' "$K"
check_case "M14 验收测试改名" "R6[lookup-ctrl-hits]"
make_copy; sed -i '/fn table_round_trips_to_canonical/d' "$K"; printf '\n    // table_round_trips_to_canonical 只是注释里提一句\n' >> "$K"
check_case "M15 删测试但注释留同名串" "R6[table-round-trips-to-canonical]"

# R7 CI 接线
make_copy; sed -i 's/S1-3 key name table gate/S1-3 key names note/' "$CI"
check_case "M16 gate step 改名" "R7[step-name]"
make_copy; sed -i 's|bash scripts/verify-s1-3.sh|bash scripts/verify-s1-2.sh|' "$CI"
check_case "M17 gate step 指错脚本" "R7[step-run]"

# R8 分层
make_copy; printf 'use dirs;\n' >> "$K"
check_case "M18 分层越界注入" "R8[layering]"

# fail-closed
make_copy; rm -f "$K"
check_case "M19 keycap.rs 缺失 fail-closed" "R1[keycap-missing] R2[keycap-missing] R3[keycap-missing] R4[keycap-missing] R5[keycap-missing] R6[keycap-missing]"

make_copy; sed -i 's/^    "Ctrl",$/    "C",/' "$K"
check_case "M20 条目改写成单字母（条数不变）" "R1[Ctrl] R3[no-single-char-name]"

# --- 诱饵：该绿的必绿
# D1 整行注释里写满违禁字样与小写/大写索引形态
make_copy; sed -i '/^#\[cfg(test)\]/i // 反例：unwrap() expect( panic! todo! unimplemented! get_unchecked 与 data[0]、KNOWN_KEY_NAMES[0]' "$K"
check_case "D1 注释含违禁字样与小写/大写索引" "GREEN"
# D2 测试区内另放一个形状相似的常量表（区域提取只认 const KNOWN_KEY_NAMES 之后那段）
make_copy; sed -i '/^mod tests {$/a\    const DECOY_NAMES: \&[\&str] = \&["Zz", "Ctrl"];' "$K"
check_case "D2 测试区同名形态常量不误伤表区" "GREEN"
# D3 主表注释块再加一行同类讨论（R5 只要求标记在位，不锁行数与措辞）
make_copy; sed -i '0,/^const KNOWN_KEY_NAMES:/s//\/\/\/ 另见 S1-6 的修饰键别名表讨论\nconst KNOWN_KEY_NAMES:/' "$K"
check_case "D3 注释块增行不误报" "GREEN"
# D4 别名两对换序（R2 逐对 grep + 对数，不锁顺序）
make_copy; sed -i 's/&\[("pgdn", "PageDown"), ("pgup", "PageUp")\]/\&[("pgup", "PageUp"), ("pgdn", "PageDown")]/' "$K"
check_case "D4 别名表换序不误报" "GREEN"
# D5 删掉 normalize_literal 的空段守卫（S1-4 可能重写函数体，R4 不钉函数体形态）
make_copy; sed -i '/if seg.is_empty() {/,+2d' "$K"
check_case "D5 normalize_literal 函数体改写不误报" "GREEN"
# D6 未被 R6 钉住的测试改名（名单精确，不锁全部测试名）
make_copy; sed -i 's/fn alias_lookup_is_case_insensitive/fn alias_lookup_case_folded/' "$K"
check_case "D6 名单外测试改名不误报" "GREEN"
# D7 Angle 臂内部形态改动（归 S1-5/6，本门禁不钉）
make_copy; sed -i 's/Segment::Angle(raw) => vec!\[raw.to_string()\],/Segment::Angle(raw) => vec![raw.to_string(), raw.to_string()],/' "$K"
check_case "D7 Angle 臂改动不误报" "GREEN"
# D9 表 doc 注释里写单字符引号串（区域提取与 R3 都只在去注释文本上做，注释不算条目）
make_copy; sed -i '0,/^const KNOWN_KEY_NAMES:/s//\/\/\/ 反例讨论：\""S\""、\""g\"" 只出现在注释里\nconst KNOWN_KEY_NAMES:/' "$K"
check_case "D9 注释里的引号单字符不算表条目" "GREEN"
# D8 ci.yml 在 S1-3 step 前插无关 step（不锁 step 总数与顺序）
make_copy; sed -i 's@^      - name: S1-3 key name table gate@      - name: Docs preview\n        run: echo ok\n\n      - name: S1-3 key name table gate@' "$CI"
check_case "D8 ci 增无关 step 不误报" "GREEN"

echo "== self-test 结果: PASS=$ST_PASS FAIL=$ST_FAIL =="
((ST_FAIL == 0)) || exit 1
