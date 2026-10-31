import SwiftUI

struct ConfigSection: View {
    @ObservedObject var runner: SingBoxRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("配置文件", systemImage: "doc.text")
                .font(.headline)

            if let configURL = runner.selectedConfig {
                HStack(spacing: 12) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 23))
                        .foregroundStyle(.tint)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(configURL.lastPathComponent)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(configURL.deletingLastPathComponent().path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Spacer()
                }
                .padding(12)
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .foregroundStyle(.secondary)
                    Text("选择或拖入 sing-box JSON 配置")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 10) {
                Button {
                    runner.chooseConfig()
                } label: {
                    Label("选择配置…", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .disabled(runner.canStop)

                Button {
                    runner.validateConfig()
                } label: {
                    if runner.isValidating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("校验", systemImage: "checkmark.shield")
                    }
                }
                .disabled(!runner.canValidate)

                if runner.selectedConfig != nil {
                    Button {
                        runner.openConfigDirectory()
                    } label: {
                        Label("打开目录", systemImage: "folder.badge.gearshape")
                    }

                    Button {
                        runner.openAdminLauncher()
                    } label: {
                        Label("管理员终端启动", systemImage: "terminal")
                    }
                }

                Spacer()
            }

            Label {
                Text("配置含 TUN 时，“启动”会请求管理员密码，并临时切换系统 DNS；退出时自动恢复。")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }
}
