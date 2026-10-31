import AppKit
import SwiftUI

@main
struct SingBoxTesterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runner: SingBoxRunner

    init() {
        let runner = SingBoxRunner()
        _runner = StateObject(wrappedValue: runner)
        AppDelegate.runner = runner
    }

    var body: some Scene {
        WindowGroup("Sing-box REALITY 测试器", id: "main") {
            ContentView(runner: runner)
                .frame(minWidth: 760, minHeight: 600)
        }
        .defaultSize(width: 920, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("选择配置…") {
                    runner.chooseConfig()
                }
                .keyboardShortcut("o")
            }

            CommandMenu("运行") {
                Button("校验配置") {
                    runner.validateConfig()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!runner.canValidate)

                Button("启动") {
                    runner.start()
                }
                .keyboardShortcut("r")
                .disabled(!runner.canStart)

                Button("停止") {
                    runner.stop()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!runner.canStop)

                Divider()

                Button("用管理员终端启动") {
                    runner.openAdminLauncher()
                }
                .disabled(runner.selectedConfig == nil)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var runner: SingBoxRunner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.runner?.stopForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
