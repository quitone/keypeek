//! 配置目录路径解析与创建（PRD F-70）。
//!
//! Linux: `~/.config/keypeek/`；Windows: `%APPDATA%\keypeek\`（平台差异由 `dirs` 承担）。

use std::path::{Path, PathBuf};

/// 配置目录操作错误
#[derive(Debug)]
pub enum ConfigError {
    /// 无法获取系统配置目录（`dirs::config_dir()` 返回 None）
    DirNotFound,
    /// 创建配置目录失败（含路径与底层 OS 错误）
    CreateFailed(String),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::DirNotFound => write!(f, "无法获取系统配置目录"),
            ConfigError::CreateFailed(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for ConfigError {}

/// 返回平台适配的配置目录 `<系统配置根>/keypeek`。不落盘、不创建目录。
pub fn config_dir() -> Result<PathBuf, ConfigError> {
    let base = dirs::config_dir().ok_or(ConfigError::DirNotFound)?;
    Ok(base.join("keypeek"))
}

/// 确保配置目录存在（对应 F-70）。已存在时为无操作。
pub fn ensure_config_dir() -> Result<(), ConfigError> {
    ensure_dir_at(&config_dir()?)
}

/// 对任意给定路径幂等创建目录（`create_dir_all` 对已存在路径返回 Ok，故幂等）。
/// 私有：单元测试经 `super::*` 用 tempdir 注入隔离环境（Sprint-Plan「临时目录注入」）。
fn ensure_dir_at(path: &Path) -> Result<(), ConfigError> {
    std::fs::create_dir_all(path)
        .map_err(|e| ConfigError::CreateFailed(format!("无法创建目录 {}: {}", path.display(), e)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn config_dir_ends_with_keypeek() {
        let dir = config_dir().expect("测试环境应能取到系统配置目录");
        assert!(dir.ends_with("keypeek"));
        assert!(dir.parent().is_some());
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn config_dir_linux_parent_is_dotconfig() {
        let dir = config_dir().expect("测试环境应能取到系统配置目录");
        let parent = dir.parent().unwrap().display().to_string();
        assert!(parent.ends_with("/.config"), "实际父目录: {parent}");
    }

    // CI 的 Windows 轴只 build 不跑 test，此用例仅本地手动验证时生效。
    #[cfg(target_os = "windows")]
    #[test]
    fn config_dir_windows_parent_is_appdata() {
        let dir = config_dir().expect("测试环境应能取到系统配置目录");
        let parent = dir.parent().unwrap().display().to_string();
        assert!(parent.contains("AppData"), "实际父目录: {parent}");
    }

    #[test]
    fn ensure_dir_at_creates_nested() {
        let tmp = tempfile::TempDir::new().expect("tempdir 应可创建");
        let target = tmp.path().join("a/b/keypeek");
        ensure_dir_at(&target).expect("嵌套创建应成功");
        assert!(fs::metadata(&target).expect("目录应存在").is_dir());
    }

    #[test]
    fn ensure_dir_at_idempotent() {
        let tmp = tempfile::TempDir::new().expect("tempdir 应可创建");
        let target = tmp.path().join("keypeek");
        ensure_dir_at(&target).expect("首次创建应成功");
        fs::write(target.join("keep.yaml"), b"x").expect("应可写入标记文件");
        ensure_dir_at(&target).expect("重复调用应成功（幂等）");
        assert!(
            target.join("keep.yaml").exists(),
            "重复调用不应破坏已有内容"
        );
    }

    #[test]
    fn ensure_dir_at_file_at_target_fails() {
        let tmp = tempfile::TempDir::new().expect("tempdir 应可创建");
        let file = tmp.path().join("blocked");
        fs::write(&file, b"x").expect("应可写入文件");
        let err = ensure_dir_at(&file).expect_err("对文件路径建目录应失败");
        assert!(matches!(err, ConfigError::CreateFailed(_)));
    }

    #[cfg(unix)]
    #[test]
    fn ensure_dir_at_permission_denied_fails() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = tempfile::TempDir::new().expect("tempdir 应可创建");
        let readonly = tmp.path().join("readonly");
        fs::create_dir(&readonly).expect("应可创建父目录");
        // 0o500 = r-x：可读可进但不可写，无法在其下创建子目录。
        fs::set_permissions(&readonly, fs::Permissions::from_mode(0o500)).expect("应可设置权限");
        let err = ensure_dir_at(&readonly.join("child")).expect_err("只读父目录下建子目录应失败");
        assert!(matches!(err, ConfigError::CreateFailed(_)));
        // 恢复权限，否则 TempDir 清理失败。
        fs::set_permissions(&readonly, fs::Permissions::from_mode(0o700)).expect("应可恢复权限");
    }
}
