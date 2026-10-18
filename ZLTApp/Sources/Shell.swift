import Foundation

struct ShellResult {
    let status: Int32
    let output: String
    var ok: Bool { status == 0 }
    var trimmed: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Pipe output arrives on a background handler, so the buffer has to be a
/// reference the handler and the caller share.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock(); storage.append(chunk); lock.unlock()
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }; return storage
    }
}

enum Shell {
    static func run(_ tool: String, _ args: [String],
                    timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                let buffer = OutputBuffer()
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { source in
                    let chunk = source.availableData
                    if chunk.isEmpty { return }
                    buffer.append(chunk)
                }
                do {
                    try process.run()
                } catch {
                    handle.readabilityHandler = nil
                    continuation.resume(returning: ShellResult(
                        status: -1, output: error.localizedDescription))
                    return
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning { process.terminate() }
                let grace = Date().addingTimeInterval(2)
                while process.isRunning && Date() < grace {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                handle.readabilityHandler = nil
                buffer.append(handle.readDataToEndOfFile())
                let text = String(data: buffer.data, encoding: .utf8) ?? ""
                continuation.resume(returning: ShellResult(
                    status: process.terminationStatus, output: text))
            }
        }
    }
}

enum LocalAddress {
    /// The Mac's IPv4 address on the router's own subnet, so the router can call back.
    static func onRouterLAN() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var fallback: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0,
                              NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if ip.hasPrefix("192.168.70.") { return ip }
            if fallback == nil && !ip.hasPrefix("169.254.") { fallback = ip }
        }
        return fallback
    }
}
