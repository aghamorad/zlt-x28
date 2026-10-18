import Foundation
import CryptoKit

/// Client for the stock ZLT X28 web panel. It needs no root: the app uses it to
/// read the SIM state and, once, to open the temporary door used for setup.
final class PanelClient {
    private let base = URL(string: "http://\(RouterSSH.host)/cgi-bin/http.cgi")!
    private let session: URLSession
    private var sid = ""
    var password: String

    init(password: String) {
        self.password = password
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
    }

    func login() async throws {
        let challenge = try await post(["cmd": 232, "method": "GET", "sessionId": ""])
        guard let token = challenge["token"] as? String, !token.isEmpty else {
            throw ZLTError("The router did not accept the login request.")
        }
        let digest = SHA256.hash(data: Data((token + password).utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let reply = try await post([
            "cmd": 100, "method": "POST", "sessionId": PanelClient.randomHex(),
            "username": "admin", "passwd": hash,
            "isAutoUpgrade": "0", "subcmd": 0
        ])
        guard let value = reply["sessionId"] as? String, !value.isEmpty else {
            throw ZLTError("The router rejected the admin password.")
        }
        sid = value
    }

    func command(_ cmd: Int, extra: [String: Any] = [:],
                 method: String = "GET") async throws -> [String: Any] {
        if sid.isEmpty { try await login() }
        var body: [String: Any] = ["cmd": cmd, "method": method, "sessionId": sid]
        for (key, value) in extra { body[key] = value }
        let reply = try await post(body)
        if reply["success"] as? Bool == false {
            throw ZLTError("The router refused that request.")
        }
        return reply
    }

    func injectTelnetd() async throws -> [String: Any] {
        try await command(172, extra: [
            "enabled": "1",
            "ip": "192.168.1.1 ; telnetd -l /bin/ash",
            "subcmd": 6,
            "language": "EN"
        ], method: "POST")
    }

    func revertDMZ(enabled: String, ip: String) async throws -> [String: Any] {
        try await command(172, extra: [
            "enabled": enabled, "ip": ip, "subcmd": 6, "language": "EN"
        ], method: "POST")
    }

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: base)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw ZLTError("The router answered with HTTP \(http.statusCode).")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ZLTError("The router sent an answer this app could not read.")
            }
            return json
        } catch let error as ZLTError {
            throw error
        } catch {
            throw ZLTError("Cannot reach the router at \(RouterSSH.host). "
                           + "Make sure this Mac is connected to the X28's Wi-Fi.")
        }
    }

    private static func randomHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
