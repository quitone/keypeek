//! 键帽拆分主流程骨架（tech-plan §5.1 步骤 1–3，任务 S1-2）。
//! domain 层纯逻辑：禁止 fltk / std::fs / dirs（§2.2 禁令，check-layering 强制）。
//! S1-2 只做结构与切分：归一化归 S1-3/4，Angle 段语义归 S1-5/6（疑点 Q-5）。
#![allow(dead_code)] // bin-only 现状：生产调用方在 S2/S3 接线；接线后移除本行交由 clippy -D warnings 复证

/// 组合键内的中间段（§5.1 步骤 2 的产物）。
/// `Angle` 存剥去尖括号后的原文、不预加工（大小写、别名、`-` 切分全留给 S1-5/6，Q-5）；
/// `Literal` 存按 `+` 切完的字面段。Debug/PartialEq 供 inline 测试直测 `split_combo`。
#[derive(Debug, Clone, PartialEq, Eq)]
enum Segment<'a> {
    Literal(&'a str),
    Angle(&'a str),
}

/// 主入口（签名 = sprint-plan S1-2 契约逐字）。
/// 管线 = 契约三动词（§5.1 步骤 1–3）：按空白切组合键 → 组合键内切 `<...>` → 余段按 `+` 切。
pub fn split_keycaps(keys: &str) -> Vec<String> {
    keys.split_whitespace()
        .flat_map(split_combo)
        .flat_map(resolve_segment)
        .collect()
}

/// 步骤 2+3：在一个组合键内切出 `<...>` token，剩余字面块再按 `+` 切成 `Segment::Literal`。
/// 未闭合 `<`（嵌套 `<a<b>` 或结尾 `abc<`）→ **整段降级**：本组合键不产生 Angle 段，
/// 整体只按 `+` 切（设计注记②）。游离 `>` 不是降级条件，按普通字面文本走后面的路径。
fn split_combo(combo: &str) -> Vec<Segment<'_>> {
    if !angle_balanced(combo) {
        let mut out = Vec::new();
        push_literal_chunks(combo, &mut out);
        return out;
    }
    let mut out = Vec::new();
    let mut rest = combo;
    while let Some((before, after)) = rest.split_once('<') {
        push_literal_chunks(before, &mut out);
        match after.split_once('>') {
            Some((raw, tail)) => {
                // D-1：空壳 `<>` 与空字面段同跳，产 0 帽
                if !raw.is_empty() {
                    out.push(Segment::Angle(raw));
                }
                rest = tail;
            }
            // angle_balanced 已保证每个 `<` 配有 `>`，此臂实际不可达；
            // 不写 panic/unreachable 类宏（验收第三条 + 门禁 R2），把余文按字面量吐出让出。
            None => {
                push_literal_chunks(after, &mut out);
                return out;
            }
        }
    }
    push_literal_chunks(rest, &mut out);
    out
}

/// char_indices 手写扫描器：`<`/`>` 配对判定（§5.1 步骤 2 的前置门）。
/// 判据：出现第二个未配对的 `<`（嵌套）或结尾仍有未闭合的 `<` → 不平衡（整段降级）。
/// 游离 `>` 幂等地视为普通文本。取索引位而全程不做切片，见设计注记①。
fn angle_balanced(combo: &str) -> bool {
    let mut open = false;
    for (_idx, ch) in combo.char_indices() {
        match ch {
            '<' => {
                if open {
                    return false;
                }
                open = true;
            }
            '>' => open = false,
            _ => {}
        }
    }
    !open
}

/// 步骤 3：字面块按 `+` 切；空段跳过（D-1：`+`、`++`、`a+`、`<a>+` 产 0 帽）。
/// 生命周期必须显式绑定（设计注记④，B1）：`&mut Vec<Segment<'_>>` 对元素生命周期不变，
/// 匿名写法会让 text 与 out 两个独立生命周期无法统一，rustc 直接拒绝编译。
fn push_literal_chunks<'a>(text: &'a str, out: &mut Vec<Segment<'a>>) {
    for piece in text.split('+') {
        if !piece.is_empty() {
            out.push(Segment::Literal(piece));
        }
    }
}

/// S1-2 占位落点：两类段一律**原样输出**——不查表、不归一化、不逐字符、不碰别名。
/// 翻转链（S1-1~S1-4 计划修订 #2 / RSK-3）：S1-3 把 Literal 臂接 normalize_literal
/// （命中表→规范形）；S1-4 让未命中段逐字符拆，并把 `bare_dash_stays_literal_until_s1_4`
/// 同 commit 翻转为 `bare_dash_split_per_char`（`"C-k"` → `["C", "-", "k"]`）；
/// Angle 臂由 S1-5/6 接管（Q-5）。
fn resolve_segment(segment: Segment<'_>) -> Vec<String> {
    match segment {
        Segment::Literal(text) => vec![text.to_string()],
        Segment::Angle(raw) => vec![raw.to_string()],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_input_yields_no_keycaps() {
        // 契约验收第一条：空字符串返回空 vec
        assert!(split_keycaps("").is_empty());
    }

    #[test]
    fn whitespace_only_yields_no_keycaps() {
        assert!(split_keycaps("   \t\n ").is_empty());
    }

    #[test]
    fn multi_combo_split_by_any_whitespace() {
        // 契约验收第二条样例（PRD §5.5 用例 3）。占位期字面量逐字保留，
        // 此断言恰与终态一致（Ctrl/Alt 命中表后仍是这两个规范形），可以放心钉。
        assert_eq!(
            split_keycaps("Ctrl+k Ctrl+Alt+c"),
            vec!["Ctrl", "k", "Ctrl", "Alt", "c"]
        );
        // 空白集取宽（Q-6）：制表符同样是组合键边界
        assert_eq!(split_keycaps("a\tb"), vec!["a", "b"]);
    }

    #[test]
    fn plus_splits_within_combo() {
        assert_eq!(split_keycaps("a+b+c"), vec!["a", "b", "c"]);
    }

    #[test]
    fn angle_token_extracted_as_segment() {
        // 直测 split_combo 的中间表示（Angle 管线的终态语义归 S1-5/6，Q-5）
        assert_eq!(
            split_combo("<leader>bb"),
            vec![Segment::Angle("leader"), Segment::Literal("bb")]
        );
        assert_eq!(
            split_combo("a<CR>x<b>"),
            vec![
                Segment::Literal("a"),
                Segment::Angle("CR"),
                Segment::Literal("x"),
                Segment::Angle("b"),
            ]
        );
    }

    #[test]
    fn bare_dash_stays_literal_until_s1_4() {
        // **中间态钉桩**（S1-1~S1-4 计划修订 #2）：`-` 切分只发生在 `<...>` 内部（推导，
        // 出处 §0），S1-2/S1-3 不实现任何 `-` 语义，本断言固化的是占位中间态而非契约终态。
        // S1-4 落地时**同 commit** 把本测试重命名为 bare_dash_split_per_char 并翻转为
        // ["C", "-", "k"]（逐字符拆分未命中段）；verify-s1-2 门禁不钉此行为断言内容
        // （全部状态无关，修订 #8 连锁安全），翻转由 verify-s1-4 的 R3 强制测试名翻转。
        assert_eq!(split_keycaps("C-k"), vec!["C-k"]);
    }

    #[test]
    fn no_panic_on_malformed_input() {
        // 契约验收第三条：无 panic 路径。只断言不 panic、重跑确定、帽非空（D-1），
        // 不钉具体形态——畸形输入的终态语义属 Q-5（Angle 兜底）归 S1-5/6 清算。
        for input in [
            "<", "abc<", "a>", "><", "<>", "<<", "a<>b", "+", "++", "a+", "😀+<",
        ] {
            let first = split_keycaps(input);
            let second = split_keycaps(input);
            assert_eq!(first, second, "重跑输出不确定: {input}");
            assert!(
                first.iter().all(|cap| !cap.is_empty()),
                "出现空键帽: {input}"
            );
        }
        // D-1 的显式落点：空壳与空段产 0 帽
        assert!(split_keycaps("<>").is_empty());
        assert!(split_keycaps("+").is_empty());
        assert!(split_keycaps("++").is_empty());
        assert_eq!(split_keycaps("a+"), vec!["a"]);
    }
}
