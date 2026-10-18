import Foundation

enum RouterSSH {
    static let host = "192.168.70.1"
    static let user = "root"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ZLT X28", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // RSA, not ed25519: the X28's dropbear is built without ed25519 support and
    // silently refuses those keys, even when the authorized_keys line matches.
    static var keyURL: URL { supportDirectory.appendingPathComponent("id_rsa") }
    static var knownHostsURL: URL { supportDirectory.appendingPathComponent("known_hosts") }

    static func ensureKey() async throws {
        retireOldKeyIfNeeded()
        if FileManager.default.fileExists(atPath: keyURL.path) { return }
        let result = await Shell.run("/usr/bin/ssh-keygen", [
            "-q", "-t", "rsa", "-b", "2048", "-N", "", "-C", "zlt-x28-app",
            "-f", keyURL.path
        ], timeout: 20)
        guard result.ok, FileManager.default.fileExists(atPath: keyURL.path) else {
            throw ZLTError("Could not create the app's SSH key. " + result.output)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: keyURL.path)
    }

    /// Earlier builds made an ed25519 key, which this router ignores. Move it out
    /// of the way so a fresh RSA key is made in its place.
    private static func retireOldKeyIfNeeded() {
        let fm = FileManager.default
        for name in ["id_ed25519", "id_ed25519.pub"] {
            let url = supportDirectory.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            let retired = supportDirectory
                .appendingPathComponent(name + ".retired")
            try? fm.removeItem(at: retired)
            try? fm.moveItem(at: url, to: retired)
        }
    }

    static func publicKey() async -> String {
        let url = keyURL.appendingPathExtension("pub")
        return (try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    private static func options() -> [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=6",
            "-o", "HostKeyAlgorithms=+ssh-rsa",
            "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa,ssh-ed25519",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(knownHostsURL.path)",
            "-o", "IdentitiesOnly=yes",
            "-o", "LogLevel=ERROR",
            "-o", "ServerAliveInterval=15"
        ]
    }

    static func run(_ command: String, timeout: TimeInterval = 40) async -> ShellResult {
        var args = options()
        args += ["-i", keyURL.path, "\(user)@\(host)", command]
        return await Shell.run("/usr/bin/ssh", args, timeout: timeout)
    }

    static func scp(_ local: URL, to remotePath: String,
                    timeout: TimeInterval = 180) async -> ShellResult {
        var args = ["-O"] + options()
        args += ["-i", keyURL.path, local.path, "\(user)@\(host):\(remotePath)"]
        return await Shell.run("/usr/bin/scp", args, timeout: timeout)
    }

    /// Follows a long-running command until it prints a marker.
    static func waitFor(_ command: String, marker: String,
                        timeout: TimeInterval) async -> (Bool, String) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let result = await run(command, timeout: 10)
            if result.output.contains(marker) { return (true, result.output) }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        return (false, "Timed out waiting for \(marker)")
    }
}

struct ZLTError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
