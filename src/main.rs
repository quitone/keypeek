mod app;
mod domain;
mod infra;
mod ui;

fn main() {
    // 首次启动自动创建配置目录（PRD F-70）
    if let Err(e) = infra::paths::ensure_config_dir() {
        eprintln!("错误: {e}");
        std::process::exit(1);
    }
}
