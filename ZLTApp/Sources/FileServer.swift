import Foundation
import Network

/// A tiny read-only web server. The router pulls the installer and its binaries
/// from here over the LAN, which is far faster and more reliable than pushing
/// megabytes through a terminal.
final class FileServer {
    private var listener: NWListener?
    private let root: URL
    private let queue = DispatchQueue(label: "zlt.fileserver")
    private(set) var port: UInt16 = 0
    var onRequest: ((String) -> Void)?

    init(root: URL) { self.root = root }

    func start(preferred: UInt16 = 8137) throws {
        if listener != nil { return }
        for candidate in preferred...(preferred + 12) {
            guard let endpoint = NWEndpoint.Port(rawValue: candidate) else { continue }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let candidateListener = try? NWListener(using: parameters, on: endpoint) else {
                continue
            }
            let ready = DispatchSemaphore(value: 0)
            candidateListener.stateUpdateHandler = { state in
                if case .ready = state { ready.signal() }
                if case .failed = state { ready.signal() }
            }
            candidateListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            candidateListener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 3)
            if candidateListener.state == .ready {
                listener = candidateListener
                port = candidate
                return
            }
            candidateListener.cancel()
        }
        throw ZLTError("Could not start the file server on this Mac.")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
            [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var collected = buffer
            if let data { collected.append(data) }
            if let delimiter = collected.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: collected[..<delimiter.lowerBound],
                                  as: UTF8.self)
                self.respond(connection, head: head)
                return
            }
            if complete || error != nil || collected.count > 65536 {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: collected)
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            send(connection, status: "405 Method Not Allowed", body: Data())
            return
        }
        var path = String(parts[1])
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        path = path.removingPercentEncoding ?? path
        guard !path.contains("..") else {
            send(connection, status: "403 Forbidden", body: Data())
            return
        }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let file = root.appendingPathComponent(relative).standardizedFileURL
        let base = root.standardizedFileURL.path
        guard file.path.hasPrefix(base), relative != "" else {
            send(connection, status: "404 Not Found", body: Data())
            return
        }
        guard let body = try? Data(contentsOf: file) else {
            send(connection, status: "404 Not Found", body: Data())
            return
        }
        onRequest?(relative)
        let type = file.pathExtension == "sh" ? "text/plain; charset=utf-8"
                                             : "application/octet-stream"
        send(connection, status: "200 OK", body: body, contentType: type)
    }

    private func send(_ connection: NWConnection, status: String, body: Data,
                      contentType: String = "text/plain; charset=utf-8") {
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
