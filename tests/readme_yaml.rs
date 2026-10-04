use noyalib::compat::serde_yaml as yaml;

/// S0-6 验收 AC1「最小 YAML 示例可被用户复制」的真证据：用本工具真正用来解析用户数据的
/// `noyalib`（ADR-008）解析 README 里的围栏，而不是某个外部解释器 —— 复制即用才是"可复制"。
fn readme() -> String {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/README.md");
    std::fs::read_to_string(path).unwrap_or_else(|e| panic!("读取 {path} 失败: {e}"))
}

/// 抽取 README 中所有 ```yaml 围栏的内容（缩进在列表项里的围栏同样认）。
fn yaml_fences(text: &str) -> Vec<String> {
    let mut blocks = Vec::new();
    let mut open = false;
    let mut buf = String::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if !open {
            if trimmed == "```yaml" {
                open = true;
                buf.clear();
            }
        } else if trimmed == "```" {
            blocks.push(std::mem::take(&mut buf));
            open = false;
        } else {
            buf.push_str(line);
            buf.push('\n');
        }
    }
    assert!(!open, "README 里有未闭合的 ```yaml 围栏");
    blocks
}

#[test]
fn readme_yaml_examples_parse_with_noyalib() {
    let blocks = yaml_fences(&readme());
    assert!(
        !blocks.is_empty(),
        "README 必须至少含一个 ```yaml 示例（S0-6 AC1）"
    );
    for (i, block) in blocks.iter().enumerate() {
        yaml::from_str::<yaml::Value>(block)
            .unwrap_or_else(|e| panic!("README 第 {} 个 yaml 示例不可解析: {e}", i + 1));
    }
}

#[test]
fn readme_minimal_example_matches_prd_section4_shape() {
    let blocks = yaml_fences(&readme());
    let first = blocks.first().expect("README 缺最小 YAML 示例");
    let doc = yaml::from_str::<yaml::Value>(first).expect("最小示例应可解析");

    for key in ["icon", "key_names", "list"] {
        assert!(doc.get(key).is_some(), "最小示例缺 PRD §4 顶层字段 `{key}`");
    }

    let list = doc
        .get("list")
        .and_then(|v| v.as_mapping())
        .expect("`list` 应为映射（分组容器）");
    let general = list
        .get("general")
        .and_then(|v| v.as_sequence())
        .expect("`list.general` 应为条目序列");
    let fields: Vec<&str> = general[0]
        .as_mapping()
        .expect("条目应为映射")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(fields, vec!["keys", "description", "modes"]);
}
