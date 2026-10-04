//! 分级错误（tech-plan §6，F-04）。S1-1 仅先行定义 `GroupOutcome` 编译所需的 `GroupError`
//! （受记录偏差 Q-1：契约文件清单只列 model.rs，归置有 §2.3 目录规约 domain/error 背书）；
//! `FileError` / `EntryWarning` / `ParseOutcome` 归 S1-8，语义须与 §6 表一一对应。
#![allow(dead_code)] // 同 model.rs：消费方接线后移除

/// 分组级失败（§6：触发条件为「分组 value 非数组」）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GroupError {
    ValueNotSequence,
}
