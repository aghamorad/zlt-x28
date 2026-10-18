import Foundation

/// Turns a share link (vless://, vmess://, trojan://, ss://, hysteria2://,
/// socks://) into the two sing-box configs this app needs: one that runs the
/// router's whole LAN through the link, and one that only opens a local proxy
/// port so the link can be measured without touching the LAN route.
struct ShareLink: Equatable {
    let raw: String
    let fileBase: String       // router-safe file name, e.g. vless-host-443
    let title: String          // the #fragment, if the link had one
    let kind: String           // VLESS, VMess, Trojan, Shadowsocks, Hysteria2, SOCKS
    let server: String         // host:port
    let outbound: [String: Any]

    static func == (lhs: ShareLink, rhs: ShareLink) -> Bool {
        lhs.raw == rhs.raw
    }
}

enum SingBox {
    static let tunName = "sb0"
    static let testPort = 18080
    static let version = "1.14.3"

    // MARK: - Parsing

    static func parse(_ raw: String) -> ShareLink? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sep = text.range(of: "://") else { return nil }
        let scheme = text[..<sep.lowerBound].lowercased()
        let rest = String(text[sep.upperBound...])
        switch scheme {
        case "vless":          return parseVless(rest, raw: text)
        case "vmess":          return parseVmess(rest, raw: text)
        case "trojan":         return parseTrojan(rest, raw: text)
        case "ss":             return parseShadowsocks(rest, raw: text)
        case "hysteria2", "hy2": return parseHysteria2(rest, raw: text)
        case "socks", "socks5": return parseSocks(rest, raw: text)
        default:               return nil
        }
    }

    /// Splits "userinfo@host:port?query#name" without losing percent-encoded
    /// pieces, which URLComponents() rejects in some of these links.
    private struct Parts {
        var userinfo = ""
        var host = ""
        var port = 0
        var query: [String: String] = [:]
        var fragment = ""
    }

    private static func split(_ body: String) -> Parts? {
        var rest = body
        var parts = Parts()
        if let hash = rest.firstIndex(of: "#") {
            parts.fragment = percentDecode(String(rest[rest.index(after: hash)...]))
            rest = String(rest[..<hash])
        }
        var queryText = ""
        if let q = rest.firstIndex(of: "?") {
            queryText = String(rest[rest.index(after: q)...])
            rest = String(rest[..<q])
        }
        if let at = rest.lastIndex(of: "@") {
            parts.userinfo = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
        }
        guard let (host, port) = hostPort(rest) else { return nil }
        parts.host = host
        parts.port = port
        for pair in queryText.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? percentDecode(String(kv[1])) : ""
            parts.query[String(key).lowercased()] = value
        }
        return parts
    }

    private static func hostPort(_ text: String) -> (String, Int)? {
        if text.hasPrefix("[") {                                  // [2001:db8::1]:443
            guard let close = text.firstIndex(of: "]") else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let tail = text[text.index(after: close)...]
            let port = tail.drop(while: { $0 == ":" })
            return Int(port).map { (host, $0) }
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let host = String(text[..<colon])
        let port = String(text[text.index(after: colon)...])
        guard let number = Int(port), number > 0, number < 65536, !host.isEmpty else { return nil }
        return (host, number)
    }

    private static func percentDecode(_ text: String) -> String {
        text.removingPercentEncoding ?? text
    }

    private static func parseVless(_ body: String, raw: String) -> ShareLink? {
        guard var parts = split(body) else { return nil }
        let uuid = percentDecode(parts.userinfo)
        guard !uuid.isEmpty else { return nil }
        let q = parts.query

        var outbound: [String: Any] = [
            "type": "vless", "tag": "proxy",
            "server": parts.host, "server_port": parts.port, "uuid": uuid
        ]
        if let flow = q["flow"], !flow.isEmpty { outbound["flow"] = flow }
        if let tls = tlsDict(security: q["security"], q: q, host: parts.host) {
            outbound["tls"] = tls
        }
        if let transport = transportDict(q: q) { outbound["transport"] = transport }
        return finish(raw: raw, parts: parts, kind: "VLESS", outbound: outbound)
    }

    private static func parseTrojan(_ body: String, raw: String) -> ShareLink? {
        guard var parts = split(body) else { return nil }
        let password = percentDecode(parts.userinfo)
        guard !password.isEmpty else { return nil }
        let q = parts.query
        var outbound: [String: Any] = [
            "type": "trojan", "tag": "proxy",
            "server": parts.host, "server_port": parts.port, "password": password
        ]
        outbound["tls"] = tlsDict(security: "tls", q: q, host: parts.host)
            ?? ["enabled": true, "server_name": q["sni"] ?? parts.host]
        if let transport = transportDict(q: q) { outbound["transport"] = transport }
        return finish(raw: raw, parts: parts, kind: "Trojan", outbound: outbound)
    }

    private static func parseHysteria2(_ body: String, raw: String) -> ShareLink? {
        guard var parts = split(body) else { return nil }
        let password = percentDecode(parts.userinfo)
        guard !password.isEmpty else { return nil }
        let q = parts.query
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": q["sni"] ?? q["peer"] ?? parts.host
        ]
        if q["insecure"] == "1" || q["insecure"] == "true" { tls["insecure"] = true }
        if let alpn = q["alpn"], !alpn.isEmpty {
            tls["alpn"] = alpn.split(separator: ",").map(String.init)
        }
        var outbound: [String: Any] = [
            "type": "hysteria2", "tag": "proxy",
            "server": parts.host, "server_port": parts.port,
            "password": password, "tls": tls
        ]
        if let obfs = q["obfs"], !obfs.isEmpty {
            outbound["obfs"] = ["type": obfs, "password": q["obfs-password"] ?? ""]
        }
        return finish(raw: raw, parts: parts, kind: "Hysteria2", outbound: outbound)
    }

    private static func parseVmess(_ body: String, raw: String) -> ShareLink? {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = base64Data(text),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        func str(_ key: String) -> String { "\(object[key] ?? "")" }
        let host = str("add")
        guard let port = Int(str("port")), !host.isEmpty, !str("id").isEmpty else { return nil }

        var parts = Parts()
        parts.host = host
        parts.port = port
        parts.fragment = str("ps")

        var outbound: [String: Any] = [
            "type": "vmess", "tag": "proxy",
            "server": host, "server_port": port,
            "uuid": str("id"),
            "alter_id": Int(str("aid")) ?? 0,
            "security": str("scy").isEmpty ? "auto" : str("scy")
        ]
        let tlsMode = str("tls").lowercased()
        if tlsMode == "tls" {
            var tls: [String: Any] = ["enabled": true]
            let sni = str("sni").isEmpty ? (str("host").isEmpty ? host : str("host")) : str("sni")
            tls["server_name"] = sni
            if let fp = optional(str("fp")) {
                tls["utls"] = ["enabled": true, "fingerprint": fp]
            }
            outbound["tls"] = tls
        }
        let net = str("net").lowercased()
        let path = str("path")
        let headerHost = str("host")
        switch net {
        case "ws":
            var ws: [String: Any] = ["type": "ws", "path": path.isEmpty ? "/" : path]
            if !headerHost.isEmpty { ws["headers"] = ["Host": headerHost] }
            outbound["transport"] = ws
        case "grpc":
            outbound["transport"] = ["type": "grpc", "service_name": path]
        case "h2", "http":
            outbound["transport"] = ["type": "http",
                                     "path": path.isEmpty ? "/" : path,
                                     "host": headerHost.isEmpty ? [host] : [headerHost]]
        default:
            break
        }
        return finish(raw: raw, parts: parts, kind: "VMess", outbound: outbound)
    }

    private static func parseShadowsocks(_ body: String, raw: String) -> ShareLink? {
        var body = body
        if let hash = body.firstIndex(of: "#") { body = String(body[..<hash]) }
        if let q = body.firstIndex(of: "?") {
            body = String(body[..<q])
        }

        var userinfo = ""
        var hostPortText = ""
        if let at = body.lastIndex(of: "@") {
            userinfo = String(body[..<at])
            hostPortText = String(body[body.index(after: at)...])
        } else {
            // Legacy form: the whole thing is base64(method:password@host:port).
            guard let data = base64Data(body),
                  let decoded = String(data: data, encoding: .utf8),
                  let at = decoded.lastIndex(of: "@") else { return nil }
            userinfo = String(decoded[..<at])
            hostPortText = String(decoded[decoded.index(after: at)...])
        }
        let decodedUser = base64String(userinfo) ?? percentDecode(userinfo)
        guard let colon = decodedUser.firstIndex(of: ":") else { return nil }
        let method = String(decodedUser[..<colon])
        let password = String(decodedUser[decodedUser.index(after: colon)...])
        guard let (host, port) = hostPort(hostPortText), !method.isEmpty else { return nil }

        var parts = Parts()
        parts.host = host
        parts.port = port
        if let hash = raw.firstIndex(of: "#") {
            parts.fragment = percentDecode(String(raw[raw.index(after: hash)...]))
        }
        let outbound: [String: Any] = [
            "type": "shadowsocks", "tag": "proxy",
            "server": host, "server_port": port,
            "method": method, "password": password
        ]
        return finish(raw: raw, parts: parts, kind: "Shadowsocks", outbound: outbound)
    }

    private static func parseSocks(_ body: String, raw: String) -> ShareLink? {
        guard var parts = split(body) else { return nil }
        var outbound: [String: Any] = [
            "type": "socks", "tag": "proxy",
            "server": parts.host, "server_port": parts.port, "version": "5"
        ]
        let decoded = base64String(parts.userinfo) ?? percentDecode(parts.userinfo)
        if let colon = decoded.firstIndex(of: ":") {
            outbound["username"] = String(decoded[..<colon])
            outbound["password"] = String(decoded[decoded.index(after: colon)...])
        }
        return finish(raw: raw, parts: parts, kind: "SOCKS", outbound: outbound)
    }

    private static func finish(raw: String, parts: Parts,
                               kind: String, outbound: [String: Any]) -> ShareLink {
        let title = parts.fragment.trimmingCharacters(in: .whitespaces)
        let shown = title.isEmpty ? "\(parts.host):\(parts.port)" : title
        let stem = "\(kind.lowercased())-\(parts.host)-\(parts.port)"
        let safe = String(stem.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
        return ShareLink(raw: raw, fileBase: safe, title: shown,
                         kind: kind, server: "\(parts.host):\(parts.port)",
                         outbound: outbound)
    }

    // MARK: - Shared pieces

    private static func tlsDict(security: String?, q: [String: String],
                                host: String) -> [String: Any]? {
        let mode = (security ?? q["security"] ?? "").lowercased()
        let sni = q["sni"].flatMap { $0.isEmpty ? nil : $0 }
            ?? q["peer"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (q["host"]?.isEmpty == false ? q["host"] : host)
        switch mode {
        case "tls", "xtls":
            var tls: [String: Any] = ["enabled": true, "server_name": sni]
            if let fp = q["fp"], !fp.isEmpty {
                tls["utls"] = ["enabled": true, "fingerprint": fp]
            }
            if q["allowinsecure"] == "1" || q["insecure"] == "1" { tls["insecure"] = true }
            if let alpn = q["alpn"], !alpn.isEmpty {
                tls["alpn"] = alpn.split(separator: ",").map(String.init)
            }
            return tls
        case "reality":
            var tls: [String: Any] = [
                "enabled": true,
                "server_name": sni,
                "utls": ["enabled": true,
                         "fingerprint": q["fp"].flatMap { $0.isEmpty ? nil : $0 } ?? "chrome"],
                "reality": ["enabled": true,
                            "public_key": q["pbk"] ?? "",
                            "short_id": q["sid"] ?? ""]
            ]
            if q["allowinsecure"] == "1" { tls["insecure"] = true }
            return tls
        default:
            return nil
        }
    }

    private static func transportDict(q: [String: String]) -> [String: Any]? {
        let net = (q["type"] ?? "tcp").lowercased()
        let path = q["path"].flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        let headerHost = q["host"].flatMap { $0.isEmpty ? nil : $0 }
        switch net {
        case "ws":
            var ws: [String: Any] = ["type": "ws", "path": path]
            if let headerHost { ws["headers"] = ["Host": headerHost] }
            return ws
        case "grpc":
            return ["type": "grpc", "service_name": q["servicename"] ?? path]
        case "httpupgrade":
            var up: [String: Any] = ["type": "httpupgrade", "path": path]
            if let headerHost { up["host"] = headerHost }
            return up
        case "h2", "http":
            return ["type": "http", "path": path,
                    "host": headerHost.map { [$0] } ?? []]
        case "tcp", "none", "":
            return nil
        default:
            return nil
        }
    }

    private static func optional(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func base64Data(_ text: String) -> Data? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    private static func base64String(_ text: String) -> String? {
        guard let data = base64Data(text) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Configs

    static func tunConfig(outbound: [String: Any]) -> Data? {
        let config: [String: Any] = [
            "log": ["level": "warn"],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "interface_name": tunName,
                "address": ["10.77.0.1/30"],
                "mtu": 1420,
                "stack": "gvisor",
                "auto_route": false,
                "strict_route": false
            ]],
            "outbounds": [outbound, ["type": "direct", "tag": "direct"]],
            "route": ["final": "proxy"]
        ]
        return try? JSONSerialization.data(withJSONObject: config,
                                           options: [.prettyPrinted])
    }

    static func testConfig(outbound: [String: Any]) -> Data? {
        let config: [String: Any] = [
            "log": ["level": "error"],
            "inbounds": [[
                "type": "mixed",
                "tag": "test-in",
                "listen": "127.0.0.1",
                "listen_port": testPort
            ]],
            "outbounds": [outbound, ["type": "direct", "tag": "direct"]],
            "route": ["final": "proxy"]
        ]
        return try? JSONSerialization.data(withJSONObject: config,
                                           options: [.prettyPrinted])
    }
}
