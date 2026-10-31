enum RunnerStatus: Equatable {
    case idle
    case starting
    case running
    case stopping
    case failed

    var label: String {
        switch self {
        case .idle:
            return "未运行"
        case .starting:
            return "正在启动"
        case .running:
            return "运行中"
        case .stopping:
            return "正在停止"
        case .failed:
            return "启动失败"
        }
    }
}
