import Foundation

/// The one-time "make this router capable" sequence.
///
/// It does not flash anything. It uses the router's own admin panel to start a
/// temporary Telnet door, installs this Mac's SSH key through that door, closes
/// the door again, then copies the VPN engine over SSH and starts it.
@MainActor
final class Provisioner {
    private let password: String
    private let server: FileServer
    private let publish: (String) -> Void

    init(password: String, server: FileServer, publish: @escaping (String) -> Void) {
        self.password = password
        self.server = server
        self.publish = publish
    }

    func provision() async throws {
        guard let macIP = LocalAddress.onRouterLAN() else {
            throw ZLTError("This Mac has no address on the router's network. "
                           + "Connect to the X28's Wi-Fi first.")
        }
        publish("This Mac is at \(macIP). The router will fetch the files from here.")

        try await RouterSSH.ensureKey()
        let publicKey = await RouterSSH.publicKey()
        guard !publicKey.isEmpty else {
            throw ZLTError("The app could not create its SSH key.")
        }

        publish("Signing in to the router's admin panel…")
        let panel = PanelClient(password: password)
        let device = try await panel.command(113)
        let model = device["board_type"] as? String ?? "ZLT X28"
        let firmware = device["fake_version"] as? String ?? "unknown"
        publish("Found \(model), firmware \(firmware).")

        if firmware != "1.5.13" {
            publish("Note: this setup was proven on firmware 1.5.13. Continuing anyway.")
        }

        let currentDMZ = try? await panel.command(172)
        let oldEnabled = currentDMZ?["enabled"] as? String ?? "0"
        let oldIP = currentDMZ?["ip"] as? String ?? ""

        publish("Opening a temporary setup door…")
        do {
            _ = try await panel.injectTelnetd()
        } catch {
            throw ZLTError("The router did not accept the setup request. "
                           + "Check the admin password and firmware.")
        }

        do {
            try await Task.sleep(nanoseconds: 2_500_000_000)
            publish("Installing this Mac's key…")
            let command = "mkdir -p /etc/dropbear; "
                + "grep -qF '\(publicKey)' /etc/dropbear/authorized_keys 2>/dev/null || "
                + "echo '\(publicKey)' >> /etc/dropbear/authorized_keys; "
                + "chmod 600 /etc/dropbear/authorized_keys; echo KEY_OK"
            let transcript = try await telnetRun([command])
            guard transcript.contains("KEY_OK") else {
                throw ZLTError("The temporary door opened but the key was not installed.")
            }
            publish("The router accepted this Mac's key.")
        } catch {
            _ = try? await panel.revertDMZ(enabled: oldEnabled, ip: oldIP)
            throw error
        }

        publish("Closing the temporary door…")
        _ = try? await panel.revertDMZ(enabled: oldEnabled, ip: oldIP)

        publish("Checking password-free access…")
        var sshReady = false
        for _ in 0..<8 {
            let probe = await RouterSSH.run("echo SSH_OK", timeout: 10)
            if probe.output.contains("SSH_OK") { sshReady = true; break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard sshReady else {
            throw ZLTError("The key was added but SSH did not come up. "
                           + "Reboot the router and run setup again.")
        }

        publish("Starting the local file server…")
        try server.start()
        defer { server.stop() }
        let base = "http://\(macIP):\(server.port)"
        publish("Serving files at \(base).")

        let reach = await RouterSSH.run(
            "curl -fsS --max-time 10 \(base)/install.sh -o /dev/null && echo REACH_OK",
            timeout: 25)
        guard reach.output.contains("REACH_OK") else {
            throw ZLTError("The router cannot reach this Mac. A firewall on the Mac "
                           + "may be blocking incoming connections.")
        }

        publish("Copying the VPN engine to the router (about 14 MB)…")
        let install = await RouterSSH.run(
            "curl -fsS --max-time 60 \(base)/install.sh -o /tmp/zlt-install.sh && "
            + "sh /tmp/zlt-install.sh \(base) 2>&1 | tail -40",
            timeout: 300)
        for line in install.output.components(separatedBy: .newlines)
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            publish(line)
        }
        guard install.output.contains("ZLT_INSTALL_OK") else {
            throw ZLTError("The engine did not finish installing. "
                           + (install.trimmed.isEmpty ? "The router stopped answering."
                                                      : "See the log above."))
        }

        publish("Verifying the engine…")
        let verify = await RouterSSH.run(
            "ls -l /usr/bin/amneziawg-go /usr/bin/awgctl /usr/bin/uapipush "
            + "/usr/bin/dotbridge /usr/bin/vpn /usr/bin/vpn-keepalive "
            + "/etc/init.d/amneziawg | awk '{print $NF}'", timeout: 25)
        for line in verify.output.components(separatedBy: .newlines) where !line.isEmpty {
            publish("  installed: \(line)")
        }
        publish("The router is ready.")
    }

    private func telnetRun(_ commands: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let client = try TelnetClient(host: RouterSSH.host, port: 23,
                                                  connectTimeout: 15)
                    defer { client.close() }
                    continuation.resume(returning: client.run(commands, settle: 0.8))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
