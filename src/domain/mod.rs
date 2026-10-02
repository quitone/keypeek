//! domain 层：纯逻辑，零 IO 零 UI。
//! 禁止依赖：fltk、std::fs、dirs。
//! 允许：`noyalib` 的纯数据类型（`Value` / `Mapping`），S0-3 定案，见 tech-plan ADR-008 与 §2.2。
