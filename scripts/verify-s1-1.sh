#!/usr/bin/env bash
# S1-1 契约门禁：domain 核心类型（sprint-plan.md S1-1 三条验收 + tech-plan §3.1/§3.2/§2.3）。
# 模板逐字对照 verify-s0-6.sh（吸收 S1-16「切片删除」教训）：
#   - rules 与 expected_rule_pairs 互校，删规则即失败；
#   - 失败按子断言 id 记账（R3[Entry] 而非整条 R3）——删一条子断言，其变异体必让 self-test 期望集对不上；
#   - 字面基准数组（类型 7 / IconRef 变体 3 / derive trait 3）长度与去重机械守卫；
#   - --self-test 变异体证明每条子断言可证伪，诱饵证明不误报，model.rs 缺失 fail-closed；
#   - R7 委托 check-layering.sh，R8 守 tech-plan §11.2（src 内 #[path]/include! 纪律，去注释后扫）。
# 检查一律在**去注释文本**上进行（awk 状态机与 check-layering.sh 同源），
# 注释里讨论 HashMap/dirs/include! 不会自炸，代码里的违例也不会被行尾注释掩护成绿。
set -uo pipefail

rules=(
  "R1|7 个核心类型逐个在 model.rs 声明（契约「需要创建的文件」与 §3.1 表的字面基准，缺一即红）"
  "R2|Entry.fields 为 Vec<(String, String)> 且不存在 fields 的 HashMap 形态（§3.2，验收第二条）"
  "R3|每个类型声明前窗口内 Debug/Clone/PartialEq 逐 trait 在位、顺序无关（验收第三条；Eq/Hash 为设计超集不罚）"
  "R4|GroupOutcome 的 Ok(Vec<Entry>) 与 Failed(GroupError) 逐字在位，且 error.rs 先行定义 GroupError（Q-1 受记录偏差）"
  "R5|IconRef 恰含 Emoji/Image/Default 三变体（§3.1 三态；arity 子断言防悄悄加第四个）"
  "R6|CI 接线：check job 存在 S1-1 domain model gate step 且指向本脚本（脚本没接进流水线=门禁形同虚设）"
  "R7|分层禁令委托：check-layering.sh 对四层必须全绿"
  "R8|tech-plan §11.2：src/ 内不出现 #[path 或 include!（去注释后扫描）"
)
expected_rule_pairs='R1 R2 R3 R4 R5 R6 R7 R8'

type_names=(AppId AppSummary IconRef AppDefinition Group GroupOutcome Entry)
iconref_variants=(Emoji Image Default)
derive_traits=(Debug Clone PartialEq)

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
if ((${#type_names[@]} != 7)) || ((${#iconref_variants[@]} != 3)) || ((${#derive_traits[@]} != 3)); then
  echo "GATE-BROKEN: 基准数组长度与契约不符（类型 7 / IconRef 变体 3 / derive trait 3）"
  exit 1
fi
if [[ "$(printf '%s\n' "${type_names[@]}" | sort -u | wc -l)" -ne 7 ]]; then
  echo "GATE-BROKEN: type_names 含重复项，子断言会互相掩盖"
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
  local model="$root/src/domain/model.rs"
  local error="$root/src/domain/error.rs"
  local ci="$root/.github/workflows/ci.yml"
  local smodel="$WORK/model.stripped"

  if [[ ! -f "$model" ]]; then
    # fail-closed：文件缺失时 AC 相关规则整体红，不因「无内容可查」变绿
    local r
    for r in R1 R2 R3 R4 R5; do fail "${r}[model-missing]" "src/domain/model.rs 不存在"; done
  else
    strip_comments "$model" > "$smodel"

    # --- R1 类型逐个声明
    local t
    for t in "${type_names[@]}"; do
      grep -Eq "^[[:space:]]*pub (struct|enum) ${t}\b" "$smodel" \
        || fail "R1[$t]" "model.rs 缺少 pub struct/enum $t 声明"
    done

    # --- R2 fields 有序 Vec
    grep -qF 'fields: Vec<(String, String)>' "$smodel" \
      || fail R2[fields-vec] "Entry.fields 不再是 Vec<(String, String)>"
    grep -qE 'fields:.*HashMap' "$smodel" \
      && fail R2[no-hashmap] "出现 fields 的 HashMap 形态（§3.2：列推导依赖出现顺序）"

    # --- R3 derive 三 trait 逐类型、逐 trait（顺序无关；窗口取声明前 6 行）
    for t in "${type_names[@]}"; do
      local ctx
      ctx="$(grep -B6 -E "^[[:space:]]*pub (struct|enum) ${t}\b" "$smodel" || true)"
      if [[ -z "$ctx" ]]; then
        fail "R3[$t]" "找不到 $t 的声明行，derive 无法核验"
        continue
      fi
      local tr
      for tr in "${derive_traits[@]}"; do
        grep -qE "\b${tr}\b" <<<"$ctx" \
          || fail "R3[$t]" "$t 的 derive 窗口内缺 ${tr}（验收第三条逐字要求）"
      done
    done

    # --- R4 GroupOutcome 两变体 + GroupError 先行定义（Q-1）
    grep -qF 'Ok(Vec<Entry>)' "$smodel" || fail R4[ok-variant] "GroupOutcome 缺 Ok(Vec<Entry>)"
    grep -qF 'Failed(GroupError)' "$smodel" || fail R4[failed-variant] "GroupOutcome 缺 Failed(GroupError)"
    if [[ ! -f "$error" ]] || ! grep -Eq '^[[:space:]]*pub enum GroupError\b' <(strip_comments "$error"); then
      fail R4[error-type] "error.rs 缺失或未定义 GroupError（Q-1 受记录偏差的落点）"
    fi

    # --- R5 IconRef 恰三变体
    local body n
    body="$(awk '/^pub enum IconRef/{f=1;next} /^}/{f=0} f' "$smodel")"
    for t in "${iconref_variants[@]}"; do
      grep -Eq "^[[:space:]]+${t}\b" <<<"$body" || fail "R5[$t]" "IconRef 缺变体 $t（§3.1 三态）"
    done
    n="$(grep -cE '^[[:space:]]+[A-Za-z]' <<<"$body")"
    [[ "$n" == "3" ]] || fail R5[arity] "IconRef 变体数为 $n 而非 3（三态契约）"
  fi

  # --- R6 CI 接线自证
  if [[ ! -f "$ci" ]]; then
    fail R6[ci-missing] ".github/workflows/ci.yml 不存在"
  else
    grep -q 'S1-1 domain model gate' "$ci" || fail R6[step-name] "ci.yml 没有名为 S1-1 domain model gate 的 step"
    grep -q 'bash scripts/verify-s1-1.sh' "$ci" || fail R6[step-run] "gate step 不指向 scripts/verify-s1-1.sh"
  fi

  # --- R7 分层禁令委托
  if ! LAYERING_ROOT="$root" bash "$root/scripts/check-layering.sh" >"$WORK/layering.out" 2>&1; then
    fail R7[layering] "check-layering.sh 变红（输出见运行日志末行: $(tail -1 "$WORK/layering.out" 2>/dev/null || echo 无输出)）"
  fi

  # --- R8 §11.2 纪律：src 内去注释后无 #[path / include!
  local f hits_path=0 hits_include=0
  while IFS= read -r -d '' f; do
    strip_comments "$f" > "$WORK/f.stripped"
    grep -qF '#[path' "$WORK/f.stripped" && hits_path=1
    grep -qF 'include!' "$WORK/f.stripped" && hits_include=1
  done < <(find "$root/src" -name '*.rs' -print0)
  ((hits_path == 0)) || fail R8[attr-path] "src 内出现 #[path（tech-plan §11.2：S1 起禁用，用了须手工复核）"
  ((hits_include == 0)) || fail R8[include-macro] "src 内出现 include!（tech-plan §11.2 同上）"
}

summary() {
  if ((${#FAILED[@]})); then
    # LC_ALL=C 钉死排序：self-test 的期望集按字节序书写，locale  collation 会换位（M5 首跑实测）
    printf '失败规则: %s\n' "$(printf '%s\n' "${FAILED[@]}" | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
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
trap 'rm -rf "$ST_TMP" "$WORK"' EXIT
ST_PASS=0
ST_FAIL=0

make_copy() {
  rm -rf "$ST_TMP/repo"; mkdir -p "$ST_TMP/repo/.github/workflows"
  cp -R "$REPO_ROOT/src" "$ST_TMP/repo/src"
  cp -R "$REPO_ROOT/scripts" "$ST_TMP/repo/scripts"
  cp "$REPO_ROOT/.github/workflows/ci.yml" "$ST_TMP/repo/.github/workflows/ci.yml"
}

M="$ST_TMP/repo/src/domain/model.rs"

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

echo "== S1-1 门禁 self-test =="

# 基线
make_copy; check_case "D0 基线未变异" "GREEN"

# M1 删 AppSummary 声明行 → R1[AppSummary] 与 R3[AppSummary] 红
make_copy; sed -i '/^pub struct AppSummary {$/d' "$M"
check_case "M1 核心类型被删" "R1[AppSummary] R3[AppSummary]"

# M2 fields 换成 HashMap → 存在性与禁止性双子断言同红
make_copy; sed -i 's/fields: Vec<(String, String)>/fields: HashMap<String, String>/' "$M"
check_case "M2 fields 退化为映射" "R2[fields-vec] R2[no-hashmap]"

# M3 只删 Entry 之前的 derive 里的 PartialEq → 仅 R3[Entry] 红
make_copy; awk '
  /^pub struct Entry/ { sub(/PartialEq, /, "", prev) }
  NR > 1 { print prev }
  { prev = $0 }
  END { print prev }
' "$M" > "$M.n" && mv "$M.n" "$M"
check_case "M3 Entry 丢 PartialEq" "R3[Entry]"

# M4 Failed 改名 Error → 仅 R4[failed-variant] 红
make_copy; sed -i 's/Failed(GroupError),/Error(GroupError),/' "$M"
check_case "M4 变体名偏离契约" "R4[failed-variant]"

# M5 删 Default 变体 → R5[Default] 与 R5[arity] 红
make_copy; sed -i '/^    Default,$/d' "$M"
check_case "M5 IconRef 三态缺一" "R5[Default] R5[arity]"

# M6 删 error.rs → 仅 R4[error-type] 红（Q-1 落点失守）
make_copy; rm -f "$ST_TMP/repo/src/domain/error.rs"
check_case "M6 GroupError 先行定义被拆" "R4[error-type]"

# M7 gate step 改名 → 仅 R6[step-name] 红
make_copy; sed -i 's/S1-1 domain model gate/S1-1 types note/' "$ST_TMP/repo/.github/workflows/ci.yml"
check_case "M7 gate step 改名" "R6[step-name]"

# M8 gate step 指向别的脚本 → 仅 R6[step-run] 红
make_copy; sed -i 's|bash scripts/verify-s1-1.sh|bash scripts/verify-s0-6.sh|' "$ST_TMP/repo/.github/workflows/ci.yml"
check_case "M8 gate step 不指向本脚本" "R6[step-run]"

# M9 domain 注入 use dirs; → 仅 R7[layering] 红（委托链真实生效）
make_copy; printf 'use dirs;\n' >> "$M"
check_case "M9 分层越界注入" "R7[layering]"

# M10 注入 include! 代码行 → 仅 R8[include-macro] 红
make_copy; printf 'pub const INC: &str = include!("nope");\n' >> "$M"
check_case "M10 §11.2 include! 违例" "R8[include-macro]"

# M11 domain/mod.rs 加 #[path] 属性 → 仅 R8[attr-path] 红
make_copy; sed -i 's/^pub mod error;/#[path = "error.rs"]\npub mod error;/' "$ST_TMP/repo/src/domain/mod.rs"
check_case "M11 §11.2 #[path] 违例" "R8[attr-path]"

# M12 model.rs 整体缺失 → fail-closed，R1~R5 各记 model-missing
make_copy; rm -f "$M"
check_case "M12 model.rs 缺失 fail-closed" "R1[model-missing] R2[model-missing] R3[model-missing] R4[model-missing] R5[model-missing]"

# --- 诱饵：该绿的必绿
# D1 注释里讨论 HashMap 与 AppSummary（剥离后不留痕）
make_copy; printf '\n// 备注：AppSummary 待补；fields 不用 HashMap 保序。\n' >> "$M"
check_case "D1 注释提及违例形态不误报" "GREEN"

# D2 derive 与声明之间插属性行（窗口仍覆盖 derive）
make_copy; sed -i '/^pub enum IconRef/i #[allow(clippy::enum_variant_names)]' "$M"
check_case "D2 属性穿插不误报" "GREEN"

# D3 ci.yml 增加无关 step（门禁不锁 step 总数）
make_copy; sed -i 's@^      - name: S1-1 domain model gate@      - name: Docs preview\n        run: echo ok\n\n      - name: S1-1 domain model gate@' "$ST_TMP/repo/.github/workflows/ci.yml"
check_case "D3 新增无关 step 不误报" "GREEN"

# D4 全部 derive 去掉 Eq（契约三 trait 的等价形态，Eq 只是超集）
make_copy; sed -i 's/, Eq)/)/g' "$M"
check_case "D4 不含 Eq 的契约基线仍绿" "GREEN"

# D5 error.rs 注释里出现 dirs/fltk 字样
make_copy; printf '\n// 提醒：dirs、fltk 属 domain 禁令，注释形态不触雷。\n' >> "$ST_TMP/repo/src/domain/error.rs"
check_case "D5 错误模块注释不误报" "GREEN"

echo "== self-test 结果: PASS=$ST_PASS FAIL=$ST_FAIL =="
((ST_FAIL == 0)) || exit 1
