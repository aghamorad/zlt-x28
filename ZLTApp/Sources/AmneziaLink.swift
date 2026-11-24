import Foundation
import Compression

/// Turns Amnezia's `vpn://…` server link into a config this app can install.
///
/// The link is base64url of: a 4-byte big-endian length, then a zlib stream
/// holding JSON. That JSON describes the server container, and — when the link
/// was made from a connected client — carries `last_config`, whose `config`
/// field is already a complete WireGuard/AmneziaWG client config. Values that
/// Amnezia leaves as ranges ("25-35") or as on/off words are normalised here,
/// because the router's engine wants plain numbers.
enum AmneziaLink {

    static func configText(fromPastable text: String) -> String? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.lowercased().hasPrefix("vpn://") else { return nil }
        raw = String(raw.dropFirst("vpn://".count))
        raw = raw.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while raw.count % 4 != 0 { raw += "=" }
        guard let packed = Data(base64Encoded: raw), packed.count > 8 else { return nil }

        // 4-byte length prefix, then zlib.
        let payload = packed.dropFirst(4)
        guard let json = inflate(Data(payload)),
              let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let containers = root["containers"] as? [[String: Any]],
              let awg = containers.first?["awg"] as? [String: Any],
              let last = awg["last_config"] as? String,
              let inner = (try? JSONSerialization.jsonObject(with: Data(last.utf8))) as? [String: Any],
              let config = inner["config"] as? String
        else { return nil }

        return normalise(config, awg: awg, root: root)
    }

    /// A file name that says which server this is, without spaces.
    static func suggestedName(fromPastable text: String) -> String {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.lowercased().hasPrefix("vpn://") else { return "amnezia" }
        raw = String(raw.dropFirst("vpn://".count))
        raw = raw.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while raw.count % 4 != 0 { raw += "=" }
        guard let packed = Data(base64Encoded: raw), packed.count > 8,
              let json = inflate(Data(packed.dropFirst(4))),
              let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        else { return "amnezia" }
        let description = (root["description"] as? String) ?? ""
        let host = (root["hostName"] as? String) ?? ""
        let stem = description.isEmpty ? host : description
        let safe = stem.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        let cleaned = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "amnezia" : String(cleaned.prefix(40))
    }

    // MARK: - Internals

    private static func normalise(_ config: String, awg: [String: Any],
                                  root: [String: Any]) -> String {
        let dns1 = (root["dns1"] as? String) ?? "1.1.1.1"
        let dns2 = (root["dns2"] as? String) ?? "1.0.0.1"
        var lines: [String] = []
        var hasMTU = false
        for rawLine in config.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty {
                line = rawLine
            }
            line = line.replacingOccurrences(of: "$PRIMARY_DNS", with: dns1)
                       .replacingOccurrences(of: "$SECONDARY_DNS", with: dns2)
            if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                var value = line[line.index(after: eq)...]
                    .trimmingCharacters(in: .whitespaces)
                if key == "mtu" { hasMTU = true }
                if value.range(of: #"^\d+-\d+$"#, options: .regularExpression) != nil {
                    let parts = value.split(separator: "-").compactMap { Int($0) }
                    if parts.count == 2 { value = String((parts[0] + parts[1]) / 2) }
                }
                if value.lowercased() == "on" { value = "1" }
                if value.lowercased() == "off" { value = "0" }
                line = line[..<eq] + "= " + value
            }
            lines.append(line)
            if line.lowercased().hasPrefix("address") && !hasMTU {
                lines.append("MTU = 1280")
                hasMTU = true
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func inflate(_ data: Data) -> Data? {
        // zlib header (2 bytes) + deflate body + adler32 (4 bytes).
        guard data.count > 6 else { return nil }
        let body = data.subdata(in: 2..<(data.count - 4))
        var capacity = max(4096, body.count * 8)
        for _ in 0..<6 {
            var out = Data(count: capacity)
            let written = out.withUnsafeMutableBytes { dst -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return body.withUnsafeBytes { src -> Int in
                    guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(dstBase, capacity,
                                                    srcBase, body.count,
                                                    nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 && written < capacity { return out.prefix(written) }
            if written == capacity { capacity *= 2; continue }
            return nil
        }
        return nil
    }
}
