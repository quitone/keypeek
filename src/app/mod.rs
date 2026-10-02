//! app 层：状态机与 reducer。
//! 禁止依赖：fltk、std::fs、noyalib（含 noyalib::compat::serde_yaml）。

#[allow(dead_code)]
pub fn layering_probe(value: noyalib::Value) -> noyalib::Value {
    value
}
