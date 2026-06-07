import Foundation

/// iOS App 配置
enum Config {
    /// Mac 本地服务的地址
    /// 模拟器测试用 localhost，真机请改成 Mac 的局域网 IP
    /// 在终端运行 `ifconfig | grep "inet "` 查看
    static let serverURL = "http://zephyr-s.online:3000"
}
