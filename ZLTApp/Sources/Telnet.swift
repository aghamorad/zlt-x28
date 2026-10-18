import Foundation

/// Minimal Telnet client. The X28's busybox telnetd needs no negotiation beyond
/// ignoring the IAC bytes, so a plain socket plus a filter is enough.
final class TelnetClient {
    private var fd: Int32 = -1
    private let readTimeout = 0.45

    init(host: String, port: UInt16 = 23, connectTimeout: TimeInterval = 6) throws {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw ZLTError("The router address is not valid.")
        }
        let started = Date()
        var connected = false
        while Date().timeIntervalSince(started) < connectTimeout {
            let candidate = socket(AF_INET, SOCK_STREAM, 0)
            guard candidate >= 0 else { break }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(candidate, $0,
                                   socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 {
                fd = candidate
                connected = true
                break
            }
            Darwin.close(candidate)
            usleep(350_000)
        }
        guard connected, fd >= 0 else {
            throw ZLTError("Could not open the router's setup port.")
        }
        var readTV = timeval(tv_sec: 0,
                             tv_usec: __darwin_suseconds_t(readTimeout * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &readTV,
                   socklen_t(MemoryLayout<timeval>.size))
    }

    deinit { close() }

    func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    func send(_ line: String) {
        guard fd >= 0 else { return }
        let bytes = Array((line + "\r\n").utf8)
        bytes.withUnsafeBufferPointer {
            _ = Darwin.send(fd, $0.baseAddress, $0.count, 0)
        }
    }

    private func readAvailable() -> Data {
        guard fd >= 0 else { return Data() }
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                collected.append(buffer, count: count)
            } else {
                break
            }
        }
        return collected
    }

    /// Runs commands in one shell and returns the cleaned transcript.
    func run(_ commands: [String], settle: TimeInterval = 0.6) -> String {
        _ = readAvailable()
        var text = ""
        for command in commands {
            send(command)
            usleep(useconds_t(settle * 1_000_000))
            text += clean(readAvailable())
        }
        return text
    }

    private func clean(_ data: Data) -> String {
        var output = [UInt8]()
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 255, index + 1 < bytes.count {
                let next = bytes[index + 1]
                if next == 255 {
                    output.append(255); index += 2; continue
                }
                if next == 250 {
                    index += 2
                    while index + 1 < bytes.count {
                        if bytes[index] == 255 && bytes[index + 1] == 240 {
                            index += 2; break
                        }
                        index += 1
                    }
                    continue
                }
                if next >= 251 && next <= 254 {
                    index += 3; continue
                }
                index += 2; continue
            }
            output.append(byte)
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }
}
