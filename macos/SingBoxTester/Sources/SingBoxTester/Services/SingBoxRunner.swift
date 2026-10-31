import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SingBoxRunner: ObservableObject {
    @Published private(set) var selectedConfig: URL?
    @Published private(set) var status: RunnerStatus = .idle
    @Published private(set) var logs = ""
    @Published private(set) var isValidating = false

    private var process: Process?
    private var outputPipe: Pipe?
    private var expectedTermination = false
    private let maximumLogCharacters = 250_000

    var canStart: Bool {
        selectedConfig != nil && process == nil && !isValidating
    }

    var canStop: Bool {
        process?.isRunning == true
    }

    var canValidate: Bool {
        selectedConfig != nil && process == nil && !isValidating
    }

    var bundledBinaryPath: String? {
        binaryURL?.path
    }

    func chooseConfig() {
        let panel = NSOpenPanel()
        panel.title = "选择 sing-box 配置"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        selectConfig(url)
    }

    func selectConfig(_ url: URL) {
        guard !canStop else {
            appendLog("请先停止当前实例，再切换配置文件。\n")
            return
        }
        selectedConfig = url.standardizedFileURL
        status = .idle
        logs = ""
        appendLog("已选择配置：\(url.path)\n")
    }

    func validateConfig() {
        guard canValidate, let configURL = selectedConfig, let binaryURL else {
            return
        }

        isValidating = true
        defer { isValidating = false }

        let validation = Process()
        let pipe = Pipe()
        validation.executableURL = binaryURL
        validation.currentDirectoryURL = configURL.deletingLastPathComponent()
        validation.arguments = ["check", "-c", configURL.path]
        validation.standardOutput = pipe
        validation.standardError = pipe
        validation.environment = processEnvironment

        appendLog("\n检查配置：\(configURL.path)\n")
        do {
            try validation.run()
            validation.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            if !output.isEmpty {
                appendLog(output)
            }
            if validation.terminationStatus == 0 {
                status = .idle
                appendLog("配置校验通过。\n")
            } else {
                status = .failed
                appendLog("配置校验失败，退出代码 \(validation.terminationStatus)。\n")
            }
        } catch {
            status = .failed
            appendLog("无法执行配置校验：\(error.localizedDescription)\n")
        }
    }

    func start() {
        guard canStart else {
            return
        }
        guard let configURL = selectedConfig else {
            status = .failed
            appendLog("尚未选择配置文件。\n")
            return
        }
        guard let binaryURL else {
            status = .failed
            appendLog("应用包中缺少 sing-box 可执行文件。\n")
            return
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            status = .failed
            appendLog("配置文件不存在：\(configURL.path)\n")
            return
        }
        if configRequiresRoot(configURL) {
            logs = ""
            status = .idle
            appendLog("检测到 TUN 入站，正在打开管理员 Terminal。\n")
            appendLog("请在 Terminal 中输入 macOS 管理员密码；sing-box 日志会显示在 Terminal 中。\n")
            openAdminLauncher()
            return
        }

        logs = ""
        status = .starting
        expectedTermination = false
        appendLog("Sing-box REALITY 测试器\n")
        appendLog("配置：\(configURL.path)\n")
        appendLog("内核：\(binaryURL.path)\n\n")

        let newProcess = Process()
        let pipe = Pipe()
        newProcess.executableURL = binaryURL
        newProcess.currentDirectoryURL = configURL.deletingLastPathComponent()
        newProcess.arguments = ["run", "-c", configURL.path]
        newProcess.standardOutput = pipe
        newProcess.standardError = pipe
        newProcess.environment = processEnvironment

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.appendLog(text)
            }
        }

        newProcess.terminationHandler = { [weak self] terminatedProcess in
            let terminationStatus = terminatedProcess.terminationStatus
            Task { @MainActor [weak self] in
                self?.processDidExit(status: terminationStatus)
            }
        }

        do {
            try newProcess.run()
            process = newProcess
            outputPipe = pipe
            status = .running
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            outputPipe = nil
            status = .failed
            appendLog("无法启动 sing-box：\(error.localizedDescription)\n")
        }
    }

    func stop() {
        guard let process, process.isRunning else {
            return
        }
        expectedTermination = true
        status = .stopping
        appendLog("\n正在停止 sing-box…\n")
        process.terminate()
    }

    func stopForTermination() {
        guard let process, process.isRunning else {
            return
        }
        expectedTermination = true
        process.terminate()
        for _ in 0..<20 where process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    func clearLogs() {
        logs = ""
    }

    func copyLogs() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logs, forType: .string)
    }

    func openConfigDirectory() {
        guard let directory = selectedConfig?.deletingLastPathComponent() else {
            return
        }
        NSWorkspace.shared.open(directory)
    }

    func openAdminLauncher() {
        guard
            let configURL = selectedConfig,
            let binaryURL
        else {
            return
        }

        do {
            let supportDirectory = try applicationSupportDirectory()
            let launcherURL = supportDirectory.appendingPathComponent("以管理员启动.command")
            let configDirectory = configURL.deletingLastPathComponent()
            let dnsAddress = tunDNSAddress(configURL) ?? ""
            let contents = """
            #!/bin/zsh
            set -u

            if /usr/bin/pgrep -f \(shellQuote(binaryURL.path + " run -c " + configURL.path)) >/dev/null 2>&1; then
              echo "sing-box is already running for this configuration."
              echo "Stop it in its existing Terminal with Ctrl+C before starting another instance."
              exit 0
            fi

            if (( EUID != 0 )); then
              exec /usr/bin/sudo -- /bin/zsh "$0" "$@"
            fi

            DNS_ADDRESS=\(shellQuote(dnsAddress))
            NETWORK_SERVICE=""
            ORIGINAL_DNS=""
            RESTORE_DNS=0

            find_network_service() {
              local interface
              interface="$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
              [[ -n "$interface" ]] || return 1
              /usr/sbin/networksetup -listnetworkserviceorder | /usr/bin/awk -v target="$interface" '
                /^\\([0-9]+\\) / {
                  service = $0
                  sub(/^\\([0-9]+\\) /, "", service)
                }
                /^\\(Hardware Port:/ {
                  device = $0
                  sub(/^.*Device: /, "", device)
                  sub(/\\).*$/, "", device)
                  if (device == target) {
                    print service
                    exit
                  }
                }
              '
            }

            restore_dns() {
              if (( RESTORE_DNS )); then
                RESTORE_DNS=0
                if [[ "$ORIGINAL_DNS" == "There aren't any DNS Servers set on "* ]]; then
                  /usr/sbin/networksetup -setdnsservers "$NETWORK_SERVICE" Empty
                else
                  /usr/sbin/networksetup -setdnsservers "$NETWORK_SERVICE" ${=ORIGINAL_DNS}
                fi
                /usr/bin/dscacheutil -flushcache >/dev/null 2>&1 || true
                /usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true
              fi
            }

            trap restore_dns EXIT INT TERM HUP

            if [[ -n "$DNS_ADDRESS" ]]; then
              NETWORK_SERVICE="$(find_network_service || true)"
              if [[ -n "$NETWORK_SERVICE" ]]; then
                ORIGINAL_DNS="$(/usr/sbin/networksetup -getdnsservers "$NETWORK_SERVICE" 2>/dev/null || true)"
                if /usr/sbin/networksetup -setdnsservers "$NETWORK_SERVICE" "$DNS_ADDRESS"; then
                  RESTORE_DNS=1
                  /usr/bin/dscacheutil -flushcache >/dev/null 2>&1 || true
                  /usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true
                  echo "DNS: $NETWORK_SERVICE -> $DNS_ADDRESS (restored on exit)"
                fi
              fi
            fi

            cd \(shellQuote(configDirectory.path))
            \(shellQuote(binaryURL.path)) run -c \(shellQuote(configURL.path))
            exit $?
            """
            try contents.write(to: launcherURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: launcherURL.path
            )
            if NSWorkspace.shared.open(launcherURL) {
                appendLog("管理员启动脚本已打开：\(launcherURL.path)\n")
            } else {
                appendLog("无法打开管理员启动脚本：\(launcherURL.path)\n")
            }
        } catch {
            appendLog("无法创建管理员启动脚本：\(error.localizedDescription)\n")
        }
    }

    private var binaryURL: URL? {
        if let explicitPath = ProcessInfo.processInfo.environment["SING_BOX_BINARY_PATH"] {
            let url = URL(fileURLWithPath: explicitPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        guard let url = Bundle.main.url(forResource: "sing-box", withExtension: nil) else {
            return nil
        }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            bundleResourceDirectory?.path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        .compactMap { $0 }
        .joined(separator: ":")
        return environment
    }

    private var bundleResourceDirectory: URL? {
        Bundle.main.resourceURL
    }

    private func processDidExit(status terminationStatus: Int32) {
        let wasExpected = expectedTermination
        expectedTermination = false
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil

        if wasExpected {
            status = .idle
            appendLog("sing-box 已停止。\n")
        } else if terminationStatus == 0 {
            status = .idle
            appendLog("\nsing-box 已退出。\n")
        } else {
            status = .failed
            appendLog("\nsing-box 异常退出，代码 \(terminationStatus)。\n")
        }
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > maximumLogCharacters {
            logs.removeFirst(logs.count - maximumLogCharacters)
        }
    }

    private func applicationSupportDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let supportURL = baseURL.appendingPathComponent("SingBoxTester", isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )
        return supportURL
    }

    private func configRequiresRoot(_ configURL: URL) -> Bool {
        guard
            let data = try? Data(contentsOf: configURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let inbounds = root["inbounds"] as? [[String: Any]]
        else {
            return false
        }
        return inbounds.contains { inbound in
            inbound["type"] as? String == "tun"
        }
    }

    private func tunDNSAddress(_ configURL: URL) -> String? {
        guard
            let data = try? Data(contentsOf: configURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let inbounds = root["inbounds"] as? [[String: Any]],
            let tun = inbounds.first(where: { $0["type"] as? String == "tun" })
        else {
            return nil
        }
        if
            let configuredAddresses = tun["dns_address"] as? [String],
            let configuredAddress = configuredAddresses.first(where: { !$0.contains(":") })
        {
            return configuredAddress
        }
        guard
            let addresses = tun["address"] as? [String],
            let firstIPv4 = addresses.first(where: { !$0.contains(":") })
        else {
            return nil
        }
        return nextIPv4Address(firstIPv4)
    }

    private func nextIPv4Address(_ value: String) -> String? {
        let host = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        let octets = host.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else {
            return nil
        }
        var address = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        guard address < UInt32.max else {
            return nil
        }
        address += 1
        return [
            address >> 24,
            (address >> 16) & 0xff,
            (address >> 8) & 0xff,
            address & 0xff
        ]
        .map(String.init)
        .joined(separator: ".")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
