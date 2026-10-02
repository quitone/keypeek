#!/usr/bin/env bash
# 分层依赖检查：tech-plan §2.2 禁令表的 CI 强制（§11.2）。
# 依赖 GNU grep 的 \b 边界，只在 CI check 阶段（ubuntu）运行。
# domain 允许 noyalib（S0-3 定案：按 §2.2 现文本放行，由 --self-test 的用例钉住）。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${LAYERING_ROOT:-$REPO_ROOT}"

# 每层一行，逐项 mirror tech-plan §2.2 的「禁止依赖」列；改规则必须先改文档。
rules=(
  "domain|fltk std::fs dirs"
  "app|fltk std::fs noyalib"
  "infra|fltk"
  "ui|std::fs noyalib dirs"
)

# rules 展开后的完整禁令对，独立于 rules 硬写。放宽/新增任何一条都必须同时改这里，
# 两处不一致即失败——否则「从 rules 里删一项」这种最常见的门禁腐烂方式无人发现。
expected_rule_pairs='
app|fltk
app|noyalib
app|std::fs
domain|dirs
domain|fltk
domain|std::fs
infra|fltk
ui|dirs
ui|noyalib
ui|std::fs'

# ---- 唯一的文本源：去注释、保留行号 --------------------------------------------
# 两遍匹配（逐行 / 压平）必须读同一份代码文本，否则会出现「一处认为它是注释、
# 另一处把它当代码」的误报。awk 逐行输出（注释替换为空但不删行），grep -n 的行号
# 仍是源文件行号。
# 已知代价：字符串字面量里的 "//" 或 "/*" 会被当注释（例：let u = "https://x";）
# → 该行为被截断，只会少报、不会多报；缺口记账在 tech-plan §11.2。
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

declare -A STRIPPED=()
declare -A FLAT=()

# 每个文件只 awk 一次、压平一次，结果按路径缓存（一次 run_scan 内有效）。
# 缓存的意义不只是速度：两遍读的是同一份文本，才不会出现「一边当注释、一边当代码」。
prepare_file() {
  local f="$1"
  [ -n "${STRIPPED["$f"]+set}" ] && return 0
  STRIPPED["$f"]=$(strip_comments "$f")
  # 压平：整文件收成一行，供跨行 import 判定
  FLAT["$f"]=$(printf '%s ' "${STRIPPED["$f"]}" | tr -s ' \t')
}

# ---- 正则：两遍各一份 -----------------------------------------------------------
# 逐行遍用 GNU grep -E（可用 \b）；压平遍用 bash =~（POSIX ERE，\b 未定义，改用
# 显式字符类），所以同一语义必须写两条，且都由 --self-test 的形态样例钉住。

# 单条规则的逐行 ERE，一次覆盖三类命中形态：
#   ① import（use / pub use / pub(crate) use / extern crate，含 as 别名定义行）
#   ② 完整限定路径（token::、::token::）
#   ③ 同一行的花括号多段（use std::{fs, io}）
# 合并成一个 alternation 而不是分多次 grep，保证同一行只按规则计一次。
rule_re() {
  case "$1" in
    std::fs)
      printf '%s' '^[[:space:]]*(pub[[:space:]]*)?use[[:space:]]+[^;]*(std::fs|\{[^;}]*\bfs\b)|(^|[^[:alnum:]_:])std::fs::|::std::fs::|(^|[^[:alnum:]_.:])fs::'
      ;;
    *)
      printf '%s' "^[[:space:]]*(pub([[:space:]]*\(crate\))?[[:space:]]*)?(use|extern[[:space:]]+crate)[[:space:]]+[^;]*\b$1\b|(^|[^[:alnum:]_:])$1::|::$1::"
      ;;
  esac
}

# POSIX ERE（供 bash =~ 用，不用 \b）；`[^;]*` 保证匹配不越过语句边界。
flat_re_for() {
  case "$1" in
    std::fs)
      printf '%s' '(^|[^[:alnum:]_.])use[[:space:]]+[^;]*(std::fs|\{[^;}]*fs([[:space:]]*[,}]|[[:space:]]))|(^|[^[:alnum:]_:])std::fs::|::std::fs::'
      ;;
    *)
      printf '%s' "(^|[^[:alnum:]_.])use[[:space:]]+[^;]*(^|[[:space:]]|\\))$1([[:space:]]*::|[[:space:]]*;|[[:space:]]+as|[[:space:]]*[,}])|(^|[^[:alnum:]_:])$1::|::$1::"
      ;;
  esac
}

# 自测与独立调用用的便捷入口：给文件+禁用名，直接返回三态并填 FLAT_MATCH。
# 用前清掉该文件的缓存，否则改了 fixture 内容会读到旧文本。
flat_probe() {
  local f="$1" token="$2"
  unset 'STRIPPED[$f]' 'FLAT[$f]'
  prepare_file "$f"
  flat_match "${FLAT[$f]}" "$(flat_re_for "$token")"
}

# 压平匹配，用返回码把「命中 / 没命中 / 我自己没跑成」三态传出去。
# 返回 2 时调用方必须报「检查器执行失败」，不能当成干净。
# bash 5.2 实测：非法规则并非都返回 2 —— `((((` 返回 2，而 `a)` 返回 1（被当字面量）。
# 所以 rc=2 只能兜住一部分「检查器自己坏了」；坏到「永不匹配」的那一类靠 C3 的
# 跨行样例兜底：压平正则一旦退化，4 个 rustfmt 拆行样例就全红。
flat_match() {
  FLAT_MATCH=""
  [[ $1 =~ $2 ]]
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    FLAT_MATCH="${BASH_REMATCH[0]}"
  fi
  return "$rc"
}

# ---- 扫描 ---------------------------------------------------------------------

scan_file_token() {
  local layer="$1" token="$2" file="$3" grepline="$4" flatre="$5"
  local code hit rc one disp
  disp="${file#"$ROOT/"}"

  code="${STRIPPED["$file"]}"
  hit=$(grep -nE -- "$grepline" <<< "$code")
  rc=$?
  # grep 的 2 是「我自己没跑成」，不是「没找到」。把它当干净就是静默假绿。
  if [ "$rc" -ge 2 ]; then
    printf '[violation] %s 禁止 %s  检查器执行失败（grep rc=%s，正则语法不可用）: %s\n' \
      "$layer" "$token" "$rc" "$disp"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r one; do
      [ -n "$one" ] || continue
      printf '[violation] %s 禁止 %s  %s:%s\n' "$layer" "$token" "$disp" "$one"
    done <<< "$hit"
    return 0
  fi

  # 没有单行命中才看跨行：rustfmt 会把超长的 use 树拆成多行，拆完 `fs` 独占一行，
  # 逐行匹配看不见它。实测 cargo fmt --check 通过的产物能绕过纯逐行门禁。
  # 同一 (文件, token) 已有行命中时不再压平，避免重复计数。
  flat_match "${FLAT["$file"]}" "$flatre"
  rc=$?
  case "$rc" in
    0)
      printf '[violation] %s 禁止 %s  %s:跨行import:%s\n' \
        "$layer" "$token" "$file" "${FLAT_MATCH:0:120}"
      ;;
    2)
      printf '[violation] %s 禁止 %s  检查器执行失败（压平正则 rc=2，正则语法不可用）: %s\n' \
        "$layer" "$token" "$file"
      ;;
  esac
}

scan_layer() {
  local layer="$1" tokens="$2" dir files file token rc
  local -a toks=() lines=() flats=()
  local i=0
  for token in $tokens; do
    toks[$i]="$token"
    lines[$i]=$(rule_re "$token")
    flats[$i]=$(flat_re_for "$token")
    i=$((i + 1))
  done
  dir="$ROOT/src/$layer"
  files=$(find "$dir" -type f -name '*.rs' 2>/dev/null | sort)
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    printf '[violation] %s 禁止 [文件枚举]  检查器执行失败（find rc=%s）: %s\n' \
      "$layer" "$rc" "$dir"
    return 0
  fi
  # 层里一个 .rs 都没有 = 这一层的禁令无处可查。删空一层是最省事的绕过方式，必须报。
  if [ -z "$files" ]; then
    printf '[violation] 层 %s 没有任何 .rs 文件（该层禁令未被检查，骨架被破坏或文件被删空）: %s\n' \
      "$layer" "$dir"
    return 0
  fi
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    prepare_file "$file"
    for i in "${!toks[@]}"; do
      scan_file_token "$layer" "${toks[$i]}" "$file" "${lines[$i]}" "${flats[$i]}"
    done
  done <<< "$files"
}

collect_violations() {
  local entry layer missing=""
  STRIPPED=()
  FLAT=()
  for entry in "${rules[@]}"; do
    layer="${entry%%|*}"
    if [ ! -d "$ROOT/src/$layer" ]; then
      missing="$missing
[violation] 缺失层目录 $ROOT/src/$layer（骨架被破坏）"
      continue
    fi
    scan_layer "$layer" "${entry#*|}"
  done
  [ -z "$missing" ] || printf '%s\n' "$missing"
}

run_scan() {
  local report n
  report=$(collect_violations)
  [ -n "$report" ] && printf '%s\n' "$report"
  n=$(printf '%s\n' "$report" | grep -c '^\[violation\]')
  [ "$n" -eq 0 ]
}

# --------------------------------------------------------------------------- self-test

ST_TMP=""
ST_PASS=0
ST_FAIL=0
declare -A ST_PAIRS=()
declare -A ST_FORMS=()

probe_write() {
  printf '%s\n' "$2" > "$ST_TMP/src/$1/probe.rs"
}

probe_clear() {
  rm -f "$ST_TMP/src/$1/probe.rs"
}

expect_blocked() {
  local layer="$1" token="$2" snippet="$3" out rc
  probe_write "$layer" "$snippet"
  out=$(run_scan 2>&1)
  rc=$?
  probe_clear "$layer"
  # 单行样例必须报出「文件:行号:内容」——只说「命中了」不够，退化到压平遍
  # （报 :跨行import:、无行号）也算失败：A1/A2 验收要求定位到具体文件与行号。
  if [ $rc -eq 0 ] || ! printf '%s' "$out" | grep -qF "] $layer 禁止 $token " \
    || ! printf '%s' "$out" | grep -qE "$layer/probe\.rs:[0-9]+:"; then
    echo "  FAIL 未拦截 [$layer / $token]: $snippet"
    echo "       实际输出: ${out:-<空>}"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
    ST_PAIRS["$layer|$token"]=1
    ST_FORMS["$layer|$token|$snippet"]=1
  fi
}

# 跨行样例：$3 是多行内容（用 \n 转义传入），必须恰好 1 处命中
expect_blocked_multiline() {
  local layer="$1" token="$2" content="$3" out rc n
  printf '%b' "$content" > "$ST_TMP/src/$1/probe.rs"
  out=$(run_scan 2>&1)
  rc=$?
  probe_clear "$layer"
  n=$(printf '%s\n' "$out" | grep -c '^\[violation\]')
  if [ $rc -eq 0 ] || ! printf '%s' "$out" | grep -qF "] $layer 禁止 $token "; then
    echo "  FAIL 跨行未拦截 [$layer / $token]"
    echo "       实际输出: ${out:-<空>}"
    ST_FAIL=$((ST_FAIL + 1))
  elif [ "$n" -ne 1 ]; then
    echo "  FAIL 跨行样例应恰好 1 处命中，实际 $n 处（重复计数或漏计）"
    echo "$out" | sed 's/^/        /'
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
}

expect_clean() {
  local layer="$1" snippet="$2" why="$3" out rc
  probe_write "$layer" "$snippet"
  out=$(run_scan 2>&1)
  rc=$?
  probe_clear "$layer"
  if [ $rc -ne 0 ]; then
    echo "  FAIL 误报 [$layer]: $snippet —— $why"
    echo "       实际输出: $out"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
}

expect_clean_multiline() {
  local layer="$1" content="$2" why="$3" out rc
  printf '%b' "$content" > "$ST_TMP/src/$1/probe.rs"
  out=$(run_scan 2>&1)
  rc=$?
  probe_clear "$layer"
  if [ $rc -ne 0 ]; then
    echo "  FAIL 跨行误报 [$layer]: $why"
    echo "       实际输出: $out"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
}

# 每种形态的样例数，独立于 forms_for 硬写：删掉任何一个样例都必须在这里被抓到。
# 基准若取自 forms_for 自身就成了循环定义，「删测试样例」会静默放宽检测。
expected_form_count_for() {
  case "$1" in
    fltk) printf '7' ;;
    dirs) printf '5' ;;
    noyalib) printf '6' ;;
    std::fs) printf '6' ;;
    *) printf 'NO-BASELINE' ;;
  esac
}

forms_for() {
  case "$1" in
    fltk)
      printf '%s\n' 'use fltk::{Button, Group};' 'use fltk::*;' 'fltk::fun::run();' \
        '::fltk::app::App::new();' 'pub use fltk;' 'pub(crate) use fltk;' 'extern crate fltk;'
      ;;
    dirs)
      printf '%s\n' 'use dirs::config_dir;' 'dirs::config_dir();' '::dirs::config_dir();' \
        'pub use dirs;' 'extern crate dirs;'
      ;;
    noyalib)
      printf '%s\n' 'use noyalib::Value;' 'use noyalib::compat::serde_yaml as yaml;' \
        'noyalib::from_str::<yaml::Value>("a: 1");' '::noyalib::Value::from(1);' \
        'pub use noyalib;' 'extern crate noyalib;'
      ;;
    std::fs)
      printf '%s\n' 'use std::fs;' 'use std::fs::File;' 'use std::{fs, io};' \
        'std::fs::read_to_string("x");' 'fs::read("x");' '::std::fs::read("x");'
      ;;
  esac
}

self_test() {
  ST_TMP=$(mktemp -d) || { echo "self-test: 无法创建临时目录"; return 1; }
  trap 'rm -rf "$ST_TMP"' EXIT
  mkdir -p "$ST_TMP/src/domain" "$ST_TMP/src/app" "$ST_TMP/src/infra" "$ST_TMP/src/ui" || {
    echo "self-test: 无法搭建 fixture 目录"; return 1
  }
  # 每层放一个空 mod.rs：真实仓库的四层都有 mod.rs，而「层内无 .rs」本身是失败条件
  # （见 scan_layer），不铺底会让所有负例被这条失败带偏。
  local seed
  for seed in domain app infra ui; do : > "$ST_TMP/src/$seed/mod.rs"; done
  ROOT="$ST_TMP"

  local entry layer token pairs=0 snippet covered out rc n
  local expected_pairs_sorted
  expected_pairs_sorted=$(printf '%s\n' "$expected_rule_pairs" | grep . | sort)

  local forms_expected=0 forms_actual forms_of_token
  echo "== B0. rules 展开必须等于 §2.2 禁令表 =="
  local actual_pairs
  actual_pairs=$(
    for entry in "${rules[@]}"; do
      layer="${entry%%|*}"
      for token in ${entry#*|}; do printf '%s|%s\n' "$layer" "$token"; done
    done | sort
  )
  if [ "$actual_pairs" != "$expected_pairs_sorted" ]; then
    echo "  FAIL rules 与 expected_rule_pairs 不一致"
    echo "       三处必须同步改：tech-plan §2.2 禁令表 → 本脚本 rules → expected_rule_pairs"
    diff <(printf '%s\n' "$actual_pairs") <(printf '%s\n' "$expected_pairs_sorted") | sed 's/^/       /'
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi

  echo "== B. 每条规则的每种形态都必须能失败 =="
  for entry in "${rules[@]}"; do
    layer="${entry%%|*}"
    for token in ${entry#*|}; do
      pairs=$((pairs + 1))
      forms_of_token=$(forms_for "$token" | grep -c .)
      if [ "$forms_of_token" != "$(expected_form_count_for "$token")" ]; then
        echo "  FAIL $token 的样例数 $forms_of_token ≠ 基准 $(expected_form_count_for "$token")（样例被删或正则新增形态）"
        ST_FAIL=$((ST_FAIL + 1))
      fi
      forms_expected=$((forms_expected + forms_of_token))
      while IFS= read -r snippet; do
        expect_blocked "$layer" "$token" "$snippet"
      done < <(forms_for "$token")
    done
  done
  # 基准取 expected_rule_pairs 而非 rules：从 rules 里删一项也必须被这里抓到
  local missing_cov
  missing_cov=$(comm -23 <(printf '%s\n' "$expected_pairs_sorted") <(printf '%s\n' "${!ST_PAIRS[@]}" | sort))
  covered=$(printf '%s\n' "${!ST_PAIRS[@]}" | grep -c .)
  if [ -n "$missing_cov" ]; then
    echo "  FAIL 以下禁令没有任何用例能触发失败："
    printf '%s\n' "$missing_cov" | sed 's/^/        /'
    ST_FAIL=$((ST_FAIL + 1))
  else
    echo "  规则覆盖 $covered/$(printf '%s\n' "$expected_pairs_sorted" | grep -c .)"
  fi

  # 形态级覆盖：任何一条 (层, token, 形态) 用例被删掉都必须被抓到，
  # 否则「删测试样例」会让对应的正则退化静默通过。
  forms_actual=$(printf '%s\n' "${!ST_FORMS[@]}" | grep -c .)
  if [ "$forms_actual" -ne "$forms_expected" ]; then
    echo "  FAIL 形态级覆盖不足：期望 $forms_expected 个 (层,token,形态) 用例，实际触发 $forms_actual 个"
    ST_FAIL=$((ST_FAIL + 1))
  else
    echo "  形态级覆盖 $forms_actual/$forms_expected"
  fi

  echo "== B2. 层内嵌套子目录同样受检（§2.3 会拆出 ui/widgets 等子目录） =="
  mkdir -p "$ST_TMP/src/ui/widgets" "$ST_TMP/src/domain/sub"
  printf '%s\n' 'use std::fs;' > "$ST_TMP/src/ui/widgets/table.rs"
  out=$(run_scan 2>&1)
  rc=$?
  if [ $rc -eq 0 ] || ! printf '%s' "$out" | grep -q 'src/ui/widgets/table.rs'; then
    echo "  FAIL 嵌套子目录漏检: ${out:-<空>}"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  rm -rf "$ST_TMP/src/ui/widgets"
  printf '%s\n' 'mod keycap;' > "$ST_TMP/src/domain/sub/keycap.rs"
  out=$(run_scan 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "  FAIL 嵌套子目录误报: $out"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  rm -rf "$ST_TMP/src/ui/widgets" "$ST_TMP/src/domain/sub"

  echo "== C. 负例：合法写法与注释不得误报 =="
  for layer in domain app infra ui; do
    expect_clean "$layer" '//! 禁止依赖：fltk、std::fs、dirs、noyalib（含 noyalib::compat::serde_yaml）。' \
      '层头注释本身在列举禁用名'
    expect_clean "$layer" '// use fltk::{Button};' '行注释里的示例'
    expect_clean "$layer" '/// 不要调用 dirs::config_dir()' '文档注释里的示例'
    expect_clean "$layer" '/* noyalib::Value 不该出现在这里 */' '块注释'
    expect_clean "$layer" 'let dirs_count = 2;' '同名前缀标识符'
    expect_clean "$layer" 'use crate::infra::dirs_shim;' '自有模块名含 dirs'
    expect_clean "$layer" 'use crate::domain::model;' '跨层 crate:: 路径由人审'
    expect_clean "$layer" 'let home = std::env::var("HOME");' 'std::env 不是 std::fs'
    expect_clean "$layer" 'mod fs;' '模块名 fs 无路径限定'
    expect_clean "$layer" 'let reuse_count = 3;' '压平后 use 前必须是非标识符字符'
    # 两遍读同一份去注释文本，跨行注释必须逐个钉住，否则压平遍会把注释里的示例当代码
    expect_clean_multiline "$layer" '/* 反例：\n    use fltk::group;\n*/\n' '跨行块注释里的示例'
    expect_clean_multiline "$layer" '// 反例：\n// use dirs::config_dir();\n' '跨行行注释里的示例'
    expect_clean_multiline "$layer" '/**\n * 说明：use noyalib::Value 不该出现在这一层\n */\n' '文档块注释'
    expect_clean_multiline "$layer" '/* 用法示例：\n * std::fs::read("x");\n * fs::write("y", b);\n*/\n' '块注释内的裸 * 续行（曾被逐行遍误报）'
    expect_clean_multiline "$layer" 'fn main() {\n    // see use fltk docs\n}\n' '函数体内的行注释'
  done

  echo "== C5. 没有 /* 配对的裸 * 续行按代码处理：宁可多报，不静默漏报 =="
  local bare_reported=0
  for layer in domain app ui; do
    probe_write "$layer" ' * std::fs::read("x");'
    out=$(run_scan 2>&1)
    rc=$?
    probe_clear "$layer"
    if [ $rc -eq 0 ]; then
      echo "  FAIL 裸 * 续行被放行 [$layer]（应 fail-closed 报违规）"
      ST_FAIL=$((ST_FAIL + 1))
    else
      bare_reported=$((bare_reported + 1))
      ST_PASS=$((ST_PASS + 1))
    fi
  done
  echo "  裸 * 续行按代码报违规 $bare_reported/3 层（infra 不禁 std::fs，不计）"
  # 按 §2.2 允许列放行的组合
  expect_clean domain 'use noyalib::Value;' 'S0-3 定案：domain 允许 noyalib（放行）'
  expect_clean domain 'use noyalib::compat::serde_yaml as yaml;' '同上，兼容层路径亦放行'
  expect_clean domain 'use serde::{Deserialize, Serialize};' 'domain 允许纯数据 crate'
  expect_clean app 'use crate::domain::parse;' 'app → domain'
  expect_clean app 'use dirs::config_dir;' '§2.2 app 禁止列未含 dirs（现状放行，见 README 备忘）'
  expect_clean infra 'use noyalib::Value;' 'infra 允许 noyalib'
  expect_clean infra 'use std::fs::File;' 'infra 允许 std::fs'
  expect_clean infra 'use dirs::config_dir;' 'infra 允许 dirs'
  expect_clean ui 'use fltk::group;' 'ui 允许 fltk'
  expect_clean ui 'use crate::app::{Msg, State};' 'ui → app'

  echo "== C2. 组合根 main.rs 不在扫描范围 =="
  printf '%s\n' 'use fltk::run;' 'use dirs::config_dir;' > "$ST_TMP/src/main.rs"
  out=$(run_scan 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "  FAIL main.rs（组合根）被扫了：$out"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  rm -f "$ST_TMP/src/main.rs"

  echo "== C3. 花括号拆行：rustfmt 真实产物必须被压平遍抓到 =="
  expect_blocked_multiline ui std::fs 'use std::{\n    collections::BTreeMap,\n    fs, io,\n    net::{TcpStream, UdpSocket},\n    path::{Path, PathBuf},\n    process::Command, sync::{Arc, Mutex, RwLock},\n    time::{Duration, Instant},\n};\n'
  expect_blocked_multiline domain fltk 'use fltk::{\n    Button,\n    Group,\n    Frame,\n};\n'
  expect_blocked_multiline domain dirs 'use dirs::{\n    config_dir,\n    data_dir,\n    home_dir,\n};\n'
  expect_blocked_multiline app noyalib 'use noyalib::{\n    Value,\n    Mapping,\n    compat::serde_yaml,\n};\n'

  echo "== C4. 同一文件内「单行违规 + 跨行违规」两种 token 都要报，且不重复计数 =="
  printf '%b' 'use fltk::Button;\nuse std::{\n    fs,\n    io,\n};\n' > "$ST_TMP/src/domain/probe.rs"
  out=$(run_scan 2>&1)
  rc=$?
  n=$(printf '%s\n' "$out" | grep -c '^\[violation\]')
  probe_clear domain
  if [ $rc -eq 0 ] || [ "$n" -ne 2 ] \
    || ! printf '%s' "$out" | grep -qF '] domain 禁止 fltk ' \
    || ! printf '%s' "$out" | grep -qF '] domain 禁止 std::fs '; then
    echo "  FAIL 混合样例应报 2 处（fltk 单行 + std::fs 跨行），实际 $n 处"
    echo "$out" | sed 's/^/        /'
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi

  echo "== D. 一次报出全部越界，不在首个命中处停止 =="
  local expected=0
  for entry in "${rules[@]}"; do
    layer="${entry%%|*}"
    : > "$ST_TMP/src/$layer/probe.rs"
    for token in ${entry#*|}; do
      printf 'use %s::x;\n' "$token" >> "$ST_TMP/src/$layer/probe.rs"
      expected=$((expected + 1))
    done
  done
  out=$(run_scan 2>&1)
  rc=$?
  local actual
  actual=$(printf '%s\n' "$out" | grep -c '^\[violation\]')
  if [ $rc -eq 0 ] || [ "$actual" -ne "$expected" ]; then
    echo "  FAIL 应一次报出 $expected 处，实际 $actual 处（含跨行重复计数）"
    echo "$out"
    ST_FAIL=$((ST_FAIL + 1))
  else
    echo "  一次报出 $actual/$expected"
    ST_PASS=$((ST_PASS + 1))
  fi
  for entry in "${rules[@]}"; do
    probe_clear "${entry%%|*}"
  done

  echo "== E. 层目录缺失必须失败 =="
  mv "$ST_TMP/src/ui" "$ST_TMP/src/ui.bak"
  out=$(run_scan 2>&1)
  rc=$?
  if [ $rc -eq 0 ] || ! printf '%s' "$out" | grep -qF '缺失层目录'; then
    echo "  FAIL 缺失 src/ui 未被专门识别（rc=$rc）：${out:-<空>}"
    echo "       必须走「缺失层目录」这条断言，不能靠 find 顺带报错蒙过"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  mv "$ST_TMP/src/ui.bak" "$ST_TMP/src/ui"

  echo "== F. 检查器自身坏掉时必须变红，不得当成「干净」 =="
  # F1：逐行遍的 grep 正则非法 → rc=2 → 报「检查器执行失败」并非 0 退出
  local saved_rules=("${rules[@]}")
  rules=("domain|(((((")
  out=$(run_scan 2>&1)
  rc=$?
  rules=("${saved_rules[@]}")
  if [ $rc -eq 0 ] || ! printf '%s' "$out" | grep -qF '检查器执行失败（grep rc='; then
    echo "  FAIL 无效 grep 正则未被逐行遍表态（rc=$rc）：${out:-<空>}"
    ST_FAIL=$((ST_FAIL + 1))
  else
    echo "  F1 无效 grep 正则 → 逐行遍报「检查器执行失败（grep rc=…）」并 exit 非 0"
    ST_PASS=$((ST_PASS + 1))
  fi

  # F2：压平遍单独证伪——非法 POSIX 正则下 bash =~ 返回 2，必须与「不匹配」的 1 分开
  printf '%s\n' 'use serde::Deserialize;' > "$ST_TMP/src/domain/probe.rs"
  flat_probe "$ST_TMP/src/domain/probe.rs" '(((((' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -lt 2 ]; then
    echo "  FAIL 非法压平正则返回 rc=$rc（应为 2），会被当成「不匹配=干净」"
    ST_FAIL=$((ST_FAIL + 1))
  else
    echo "  F2 非法压平正则 → rc=2（检查器失败，非「干净」）"
    ST_PASS=$((ST_PASS + 1))
  fi
  # 对照：合法正则 + 干净文件必须恰好是 rc=1，否则 F2 的断言没有意义
  flat_probe "$ST_TMP/src/domain/probe.rs" 'fltk' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "  FAIL 合法正则匹配干净文件应 rc=1，实际 rc=$rc"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  # 对照：合法正则 + 真跨行违规必须 rc=0
  printf '%b' 'use fltk::{\n    Button,\n};\n' > "$ST_TMP/src/domain/probe.rs"
  flat_probe "$ST_TMP/src/domain/probe.rs" 'fltk' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL 合法正则匹配跨行违规应 rc=0，实际 rc=$rc"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  probe_clear domain

  # F3：走完整扫描链路时，非法正则规则也必须让退出码非 0
  rules=("domain|std::fs(((((")
  out=$(run_scan 2>&1)
  rc=$?
  rules=("${saved_rules[@]}")
  if [ $rc -eq 0 ]; then
    echo "  FAIL 非法规则在完整扫描中被放行（rc=$rc）：${out:-<空>}"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi

  echo "== G. 层内被删空（无 .rs 文件）必须失败：删空一层等于关掉门禁 =="
  rm -f "$ST_TMP/src/domain/mod.rs"
  out=$(run_scan 2>&1)
  rc=$?
  if [ $rc -eq 0 ] || ! printf '%s' "$out" | grep -qF '没有任何 .rs 文件'; then
    echo "  FAIL 删空 src/domain 仍判干净（rc=$rc）：${out:-<空>}"
    ST_FAIL=$((ST_FAIL + 1))
  else
    ST_PASS=$((ST_PASS + 1))
  fi
  : > "$ST_TMP/src/domain/mod.rs"

  echo "== A. 真实仓库必须干净 =="
  ROOT="$REPO_ROOT"
  out=$(run_scan 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "  FAIL 当前仓库存在越界："
    echo "$out"
    ST_FAIL=$((ST_FAIL + 1))
  else
    echo "  当前仓库 0 处越界"
    ST_PASS=$((ST_PASS + 1))
  fi

  echo
  echo "self-test: $ST_PASS 通过 / $ST_FAIL 失败"
  [ "$ST_FAIL" -eq 0 ]
}

case "${1:-scan}" in
  scan) run_scan; exit $? ;;
  --self-test) self_test; exit $? ;;
  *)
    echo "用法: $(basename "$0") [scan|--self-test]" >&2
    exit 2
    ;;
esac
