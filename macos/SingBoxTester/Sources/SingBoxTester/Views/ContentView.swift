import SwiftUI

struct ContentView: View {
    @ObservedObject var runner: SingBoxRunner
    @AppStorage("lastConfigPath") private var lastConfigPath = ""
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    ConfigSection(runner: runner)
                    LogConsole(runner: runner)
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    runner.validateConfig()
                } label: {
                    Label("校验配置", systemImage: "checkmark.shield")
                }
                .disabled(!runner.canValidate)

                Button {
                    runner.start()
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .disabled(!runner.canStart)

                Button {
                    runner.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .disabled(!runner.canStop)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let supportedExtensions = ["json", "config"]
            guard
                let configURL = urls.first,
                supportedExtensions.contains(configURL.pathExtension.lowercased())
            else {
                return false
            }
            runner.selectConfig(configURL)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                    VStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 38, weight: .medium))
                        Text("松开以载入 sing-box 配置")
                            .font(.headline)
                    }
                    .foregroundStyle(.primary)
                }
                .padding(28)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            restoreLastConfig()
        }
        .onChange(of: runner.selectedConfig) { _, newValue in
            lastConfigPath = newValue?.path ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("Sing-box REALITY 测试器")
                    .font(.title3.weight(.semibold))
                Text("内置 X25519MLKEM768 支持的 macOS arm64 测试版本")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(runner.status.label)
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text("含 TUN 的配置会自动通过管理员 Terminal 启动；无 TUN 配置在 app 内运行并显示日志。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let binaryPath = runner.bundledBinaryPath {
                Text(URL(fileURLWithPath: binaryPath).lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch runner.status {
        case .running:
            return .green
        case .starting, .stopping:
            return .orange
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
    }

    private func restoreLastConfig() {
        guard !lastConfigPath.isEmpty else {
            return
        }
        let configURL = URL(fileURLWithPath: lastConfigPath)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }
        if runner.selectedConfig == nil {
            runner.selectConfig(configURL)
        }
    }
}
