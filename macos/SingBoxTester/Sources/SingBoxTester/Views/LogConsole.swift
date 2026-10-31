import SwiftUI

struct LogConsole: View {
    @ObservedObject var runner: SingBoxRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("运行日志", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                Button("复制") {
                    runner.copyLogs()
                }
                .disabled(runner.logs.isEmpty)
                Button("清空") {
                    runner.clearLogs()
                }
                .disabled(runner.logs.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if runner.logs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.system(size: 28, weight: .light))
                            Text("启动后在这里查看实时日志")
                                .font(.callout)
                        }
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        Text(runner.logs)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(height: 1)
                            .id("log-bottom")
                    }
                }
                .onChange(of: runner.logs) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
            .padding(12)
            .frame(minHeight: 230)
            .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }
}
