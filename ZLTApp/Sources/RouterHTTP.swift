import Foundation

/// Direct HTTP client for the router's own `/cgi-bin/zlt` API — the exact same
/// endpoint the browser page (`http://192.168.70.1/zlt.html`) uses.
///
/// Works on any Mac on the X28 Wi-Fi with zero SSH keys and zero per-computer
/// setup, so a brand-new Mac can immediately read status, flip the VPN switch,
/// switch/rename/delete configs, and toggle split tunnelling or kill switch.
enum RouterHTTP {
    struct StatusPayload: Decodable {
        struct AWG: Decodable {
            let on: Int
            let config: String
            let exit: String
        }
        struct SB: Decodable {
            let on: Int
            let link: String
        }
        struct ConfigItem: Decodable {
            let name: String
            let endpoint: String
        }
        struct LinkItem: Decodable {
            let name: String
        }

        let awg: AWG
        let sb: SB
        let split: Int?
        let kill: Int?
        let configs: [ConfigItem]
        let links: [LinkItem]
    }

    struct ActionReply: Decodable {
        let ok: Bool
        let say: String
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }

    private static func endpointURL(act: String, params: [(String, String)] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = RouterSSH.host
        components.path = "/cgi-bin/zlt"
        var items = [URLQueryItem(name: "act", value: act)]
        for (k, v) in params {
            items.append(URLQueryItem(name: k, value: v))
        }
        components.queryItems = items
        return components.url
    }

    static func fetchStatus(timeout: TimeInterval = 5) async -> StatusPayload? {
        guard let url = endpointURL(act: "status") else { return nil }
        let session = makeSession(timeout: timeout)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(StatusPayload.self, from: data)
        } catch {
            return nil
        }
    }

    static func action(_ act: String, params: [(String, String)] = [],
                       timeout: TimeInterval = 60) async -> ActionReply {
        guard let url = endpointURL(act: act, params: params) else {
            return ActionReply(ok: false, say: "Invalid router request.")
        }
        let session = makeSession(timeout: timeout)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return ActionReply(ok: false, say: "The router answered with an error.")
            }
            if let reply = try? JSONDecoder().decode(ActionReply.self, from: data) {
                return reply
            }
            return ActionReply(ok: false, say: "The router returned an unreadable reply.")
        } catch {
            return ActionReply(ok: false, say: "The router did not answer: \(error.localizedDescription)")
        }
    }
}
