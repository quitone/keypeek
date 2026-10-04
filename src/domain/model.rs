//! domain 核心数据类型（tech-plan §3.1 表、§3.2 有序字段依据）。纯数据，零 IO 零 UI。
#![allow(dead_code)] // bin-only 现状：生产调用方在 S2/S3 接线；接线后移除本行交由 clippy -D warnings 复证

use std::path::PathBuf;

use crate::domain::error::GroupError;

/// app 唯一标识 = YAML 文件名 stem（PRD §4，不含扩展名）。
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct AppId(pub String);

/// 启动扫描产出的轻量摘要（F-01/F-10/F-15）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppSummary {
    pub id: AppId,
    /// 文件名原样保留（含扩展名；大小写不敏感比较只发生在扫描侧）
    pub display_name: String,
    /// 文件绝对路径。由 infra 填充；domain 不打开它。
    pub path: PathBuf,
    pub icon: IconRef,
    /// F-15：文件级失败/不可用标记
    pub healthy: bool,
}

/// 图标引用三态（§3.1）。`Image` 的「已校验」是构造侧契约：路径校验（§8.1）归 S2-3，
/// 类型本身不携带运行时不变量（疑点 Q-7）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IconRef {
    Emoji(String),
    Image(PathBuf),
    Default,
}

/// 完整解析结果（F-02）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppDefinition {
    /// `icon` 字段原值（emoji 或路径字符串）。校验发生在 S2/S4（疑点 Q-3）。
    pub icon: Option<String>,
    /// 字段名 → 显示名（F-32）。有序 Vec 而非映射：不新增依赖，条目 <10 线性足够（§3.2 同因）。
    pub key_names: Vec<(String, String)>,
    /// 分组按 YAML 出现顺序（F-20 下拉顺序的来源）。
    pub groups: Vec<Group>,
}

/// 分组（§3.1）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Group {
    pub name: String,
    pub outcome: GroupOutcome,
}

/// 分组结果（§3.1）。变体名 `Ok`/`Failed` 按契约逐字使用，不改名。
/// 空分组是 `Ok(vec![])` 而非失败（F-20/F-05，语义测试归 S1-10）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GroupOutcome {
    Ok(Vec<Entry>),
    Failed(GroupError),
}

/// 一条快捷键条目（§3.1 关键字段全量落地）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    /// keys 字段原始字符串（F-21 双重匹配的「原串」来源）。
    pub keys_raw: String,
    /// 解析时预计算（§3.3 一次算清），产出逻辑归 S1-2~S1-6。
    pub keycaps: Vec<String>,
    /// 条目全部原始字段（含 `keys` 自身），(字段名, 字段值字符串化)，
    /// 保留 YAML 出现顺序（§3.2：F-31 列推导与 F-32 的前提）。
    pub fields: Vec<(String, String)>,
    /// S1-14 预计算（F-21 全局搜索）。形态固化于疑点 Q-2；S1-14 若改形态算显式接口变更。
    pub search_blob: String,
    /// S1-14 预计算（F-33/36 列过滤用小写文本）：(字段名, 小写值文本)。
    pub col_text: Vec<(String, String)>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_entry() -> Entry {
        Entry {
            keys_raw: "j".to_string(),
            keycaps: vec!["j".to_string()],
            fields: vec![
                ("keys".to_string(), "j".to_string()),
                ("description".to_string(), "Down".to_string()),
            ],
            search_blob: String::new(),
            col_text: Vec::new(),
        }
    }

    #[test]
    fn model_types_constructible() {
        let def = AppDefinition {
            icon: Some("\u{2328}".to_string()),
            key_names: vec![("keys".to_string(), "按键".to_string())],
            groups: vec![Group {
                name: "Git".to_string(),
                outcome: GroupOutcome::Ok(vec![sample_entry()]),
            }],
        };
        assert_eq!(def, def.clone());

        let summary = AppSummary {
            id: AppId("neovim".to_string()),
            display_name: "neovim.yaml".to_string(),
            path: PathBuf::from("/x/neovim.yaml"),
            icon: IconRef::Default,
            healthy: true,
        };
        assert_eq!(summary, summary.clone());
        assert_ne!(AppId("a".to_string()), AppId("b".to_string()));
    }

    #[test]
    fn entry_fields_keep_declaration_order() {
        let e = sample_entry();
        assert_eq!(e.fields[0].0, "keys");
        assert_eq!(e.fields[1].0, "description");
    }

    #[test]
    fn group_failed_variant_carries_group_error() {
        let outcome = GroupOutcome::Failed(GroupError::ValueNotSequence);
        assert!(matches!(
            outcome,
            GroupOutcome::Failed(GroupError::ValueNotSequence)
        ));
    }
}
