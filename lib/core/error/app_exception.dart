// 应用统一异常（待实现）。
//
// 与 Rust 侧 `WanError`（rust/src/error.rs）对应。
// Repository 捕获 Rust 异常后包装为本类型向上抛，
// UI 只处理 AppException，不接触原始错误字符串。
