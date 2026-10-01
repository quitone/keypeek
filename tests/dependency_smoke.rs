use noyalib::compat::serde_yaml as yaml;
use pretty_assertions::assert_eq;

/// ADR-008 选型看护：compat 层的映射必须保序（§3.2 有序字段的前提），
/// 且顶层结构能按 PRD §4 的形状取到 `list`。
#[test]
fn compat_yaml_preserves_mapping_order() {
    let source = r#"
name: Neo
list:
  Motion:
    - keys: <C-k>
      description: up
      modes: n
  Text:
    - keys: <CR>
"#;

    let doc = yaml::from_str::<yaml::Value>(source).expect("最小 YAML 应可解析");
    let list = doc
        .get("list")
        .and_then(|v| v.as_mapping())
        .expect("list 应为映射");

    let groups: Vec<&str> = list.keys().map(String::as_str).collect();
    assert_eq!(groups, vec!["Motion", "Text"]);

    let motion = list
        .get("Motion")
        .and_then(|v| v.as_sequence())
        .expect("分组应为序列");
    let fields: Vec<&str> = motion[0]
        .as_mapping()
        .expect("条目应为映射")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(fields, vec!["keys", "description", "modes"]);
}

/// 固化 noyalib 0.0.51 compat 层的实测语义（tech-plan ADR-008 行为表、R-06）。
#[test]
fn compat_yaml_matches_adr008_measured_semantics() {
    let doc = yaml::from_str::<yaml::Value>("when: on\nextra: 0123\ndone: true\n")
        .expect("未知字段不应报错");
    assert_eq!(doc.get("when"), Some(&yaml::Value::String("on".into())));
    assert_eq!(doc.get("extra"), Some(&yaml::Value::String("0123".into())));
    assert_eq!(doc.get("done"), Some(&yaml::Value::Bool(true)));

    let dup = yaml::from_str::<yaml::Value>("a: 1\na: 2\n").expect("重复键不报错");
    assert_eq!(
        dup.as_mapping().map(|m| m.len()),
        Some(1),
        "重复键应后者覆盖而非报错"
    );

    let merged = yaml::from_str::<yaml::Value>("base: &b\n  k: v\napp:\n  <<: *b\n  x: 1\n")
        .expect("合并键不应报错");
    let app = merged.get("app").and_then(|v| v.as_mapping()).unwrap();
    assert!(
        app.get("<<").is_some(),
        "<< 保留为普通条目，别名值已展开；S1-11 需显式处理该键"
    );
}
