import Foundation
import SwiftUI

struct CarrierInfo: Equatable {
    var operatorName = "—"
    var networkType = "—"
    var signalLevel = 0
    var simReady = false
    var wanIP = "—"
    var dns = "—"
    var firmware = "—"
    var hardware = "—"
    var model = "—"
    var temperature = "—"
    var uptime = "—"
    var dataOn = true

    var shortOperator: String {
        let upper = operatorName.uppercased()
        if upper.contains("MCI") || upper.contains("HAMRAH") { return "MCI" }
        if upper.contains("IRANCELL") || upper.contains("MTN") { return "Irancell" }
        if upper.contains("RIGHTEL") { return "Rightel" }
        if operatorName.isEmpty || operatorName == "—" { return "Unknown" }
        return operatorName
            .replacingOccurrences(of: "IR - ", with: "")
            .replacingOccurrences(of: " Wap", with: "")
    }

    var carrierNote: String {
        switch shortOperator {
        case "MCI":
            return "MCI (Hamrah-e Aval). The SIM supplies its own APN, so the router "
                 + "already has what it needs. The main thing to improve is the path "
                 + "out — that is what the VPN does."
        case "Irancell":
            return "Irancell. Its APN is also supplied by the SIM. Signal and network "
                 + "mode are managed automatically; the app measures before changing "
                 + "anything."
        case "Rightel":
            return "Rightel. The SIM supplies the APN. If data stops working after "
                 + "switching SIMs, reset the APN in the router's own panel."
        default:
            return "This app does not recognise the operator name. It will still work; "
                 + "the carrier screen simply has less to say about it."
        }
    }
}

struct ConfigEntry: Identifiable, Equatable {
    let name: String
    var endpoint: String
    var id: String { name }
}

struct TunnelStatus: Equatable {
    var daemonRunning = false
    var bootEnabled = false
    var routeThroughTunnel = false
    var handshakeEpoch = 0
    var txBytes: Int64 = 0
    var rxBytes: Int64 = 0
    var exitIP = "—"
    var config = "—"

    var isOn: Bool { daemonRunning && routeThroughTunnel }

    var handshakeText: String {
        guard handshakeEpoch > 0 else { return "no handshake yet" }
        let age = max(0, Int(Date().timeIntervalSince1970) - handshakeEpoch)
        if age < 60 { return "\(age)s ago" }
        if age < 3600 { return "\(age / 60)m ago" }
        return "\(age / 3600)h ago"
    }

    var trafficText: String {
        let total = txBytes + rxBytes
        if total < 1024 { return "\(total) B" }
        if total < 1_048_576 { return String(format: "%.0f KB", Double(total) / 1024) }
        if total < 1_073_741_824 {
            return String(format: "%.1f MB", Double(total) / 1_048_576)
        }
        return String(format: "%.2f GB", Double(total) / 1_073_741_824)
    }
}

/// The second engine. The router runs one engine at a time; this describes
/// whichever of them is selected, independently of AmneziaWG's TunnelStatus.
struct SBTunnelStatus: Equatable {
    var installed = false
    var running = false
    var bootEnabled = false
    var routed = false
    var active = "-"
    var exitIP = "—"

    var isOn: Bool { running && routed }
}

struct LinkEntry: Identifiable, Equatable {
    let name: String          // router file name, also the key for every action
    let kind: String
    let server: String
    var title: String
    var raw: String
    var status: LinkStatus = .untested
    var id: String { name }
    var label: String { title.isEmpty ? server : title }
}

enum LinkStatus: Equatable {
    case untested
    case testing
    case alive(ms: Int, bytesPerSecond: Int)
    case dead(String)

    var isAlive: Bool { if case .alive = self { return true }; return false }

    var summary: String {
        switch self {
        case .untested: return "Not tested yet"
        case .testing: return "Testing…"
        case .alive(let ms, let bytes):
            let speed = bytes >= 1_000_000
                ? String(format: "%.1f MB/s", Double(bytes) / 1_000_000)
                : String(format: "%.0f KB/s", Double(bytes) / 1000)
            return "Alive · \(ms) ms · \(speed)"
        case .dead(let why): return why
        }
    }
}

enum VPNEngine: String, CaseIterable, Identifiable {
    case amnezia = "AmneziaWG"
    case links = "Links"

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .amnezia:
            return "A .conf file from your own AmneziaWG server. One tunnel, "
                 + "one server, nothing to test."
        case .links:
            return "Paste share links (vless, vmess, trojan, shadowsocks, "
                 + "hysteria2). Try several, keep the fastest, drop the dead ones."
        }
    }
}

struct SpeedResult: Equatable {
    let bytes: Int
    let seconds: Double
    var mbps: Double { seconds > 0 ? Double(bytes) * 8 / seconds / 1_000_000 : 0 }
    var megabytesPerSecond: Double {
        seconds > 0 ? Double(bytes) / seconds / 1_000_000 : 0
    }
}

struct SpeedSample: Identifiable, Equatable {
    let label: String
    let result: SpeedResult
    var id: String { label }
}

struct RadioCell: Identifiable, Equatable {
    let generation: String        // "4G" or "5G"
    let pci: String
    let earfcn: Int
    let rsrp: Int

    var id: String { "\(generation)-\(pci)-\(earfcn)" }
    var bandNumber: Int? {
        generation == "5G" ? BandPlan.nrBand(for: earfcn) : BandPlan.lteBand(for: earfcn)
    }
    var bandLabel: String {
        guard let band = bandNumber else { return "Band not recognised" }
        return generation == "5G" ? "n\(band)" : "Band \(band)"
    }
    var frequency: String {
        BandPlan.frequency(generation: generation, band: bandNumber)
    }
    var signalWord: String {
        if rsrp >= -85 { return "strong" }
        if rsrp >= -95 { return "good" }
        if rsrp >= -105 { return "fair" }
        return "weak"
    }
}

struct BandSettings: Equatable {
    var lock4g = false
    var lock5g = false
    var all4g = ""
    var all5g = ""
    var mask4g = ""
    var mask5g = ""

    var isLocked: Bool { lock4g || lock5g }
    var pinned4g: [Int] { lock4g ? BandPlan.bands(inMask: mask4g) : [] }
    var pinned5g: [Int] { lock5g ? BandPlan.bands(inMask: mask5g) : [] }

    var summary: String {
        guard isLocked else { return "Every band the SIM supports" }
        var parts: [String] = []
        if lock4g {
            parts.append(pinned4g.isEmpty ? "4G pinned"
                         : "4G " + pinned4g.map { "B\($0)" }.joined(separator: "+"))
        }
        if lock5g {
            parts.append(pinned5g.isEmpty ? "5G pinned"
                         : "5G " + pinned5g.map { "n\($0)" }.joined(separator: "+"))
        }
        return parts.joined(separator: " · ")
    }
}

enum BandPlan {
    // The X28 reports EARFCN, not the band number, so these are the standard
    // LTE and NR-ARFCN ranges for the bands this router supports.
    private static let lte: [(band: Int, range: ClosedRange<Int>)] = [
        (1, 0...599), (3, 1200...1949), (7, 2750...3449), (8, 3450...3799),
        (20, 6150...6449), (28, 9210...9659), (32, 9920...10359),
        (38, 37750...38249), (40, 38650...39649), (41, 39650...41589),
        (42, 41590...43589), (43, 43590...45589),
    ]
    private static let nr: [(band: Int, range: ClosedRange<Int>)] = [
        (1, 422000...434000), (3, 361000...376000), (5, 173800...178800),
        (8, 185000...192000), (28, 151600...160600), (40, 460000...479999),
        (41, 499200...537999), (78, 620000...653333),
    ]

    static func lteBand(for earfcn: Int) -> Int? {
        lte.first { $0.range.contains(earfcn) }?.band
    }
    static func nrBand(for arfcn: Int) -> Int? {
        nr.first { $0.range.contains(arfcn) }?.band
    }
    static func frequency(generation: String, band: Int?) -> String {
        guard let band else { return "frequency unknown" }
        switch (generation, band) {
        case ("4G", 1): return "2100 MHz"
        case ("4G", 3): return "1800 MHz"
        case ("4G", 7): return "2600 MHz"
        case ("4G", 8): return "900 MHz"
        case ("4G", 20): return "800 MHz"
        case ("4G", 28): return "700 MHz"
        case ("4G", 32): return "1500 MHz"
        case ("4G", 38): return "2600 MHz TDD"
        case ("4G", 40): return "2300 MHz TDD"
        case ("4G", 41): return "2500 MHz TDD"
        case ("4G", 42): return "3500 MHz TDD"
        case ("4G", 43): return "3700 MHz TDD"
        case ("5G", 1): return "2100 MHz"
        case ("5G", 3): return "1800 MHz"
        case ("5G", 5): return "850 MHz"
        case ("5G", 8): return "900 MHz"
        case ("5G", 28): return "700 MHz"
        case ("5G", 40): return "2300 MHz"
        case ("5G", 41): return "2500 MHz"
        case ("5G", 78): return "3500 MHz"
        default: return "frequency unknown"
        }
    }

    /// Router mask: bit N-1 means band N, written most-significant nibble first.
    static func mask(bands: [Int]) -> String {
        var bits = Array(repeating: "0", count: 128)
        for band in bands where band >= 1 && band <= 128 { bits[band - 1] = "1" }
        var text = bits.reversed().joined()
        while text.count % 4 != 0 { text = "0" + text }
        let chars = Array(text)
        var out = ""
        for index in stride(from: 0, to: chars.count, by: 4) {
            let nibble = String(chars[index..<index + 4])
            out += String(Int(nibble, radix: 2) ?? 0, radix: 16)
        }
        let trimmed = out.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed).uppercased()
    }

    static func bands(inMask mask: String) -> [Int] {
        let hex = mask.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !hex.isEmpty else { return [] }
        var bits = ""
        for character in hex {
            guard let value = character.hexDigitValue else { continue }
            let chunk = String(value, radix: 2)
            bits += String(repeating: "0", count: 4 - chunk.count) + chunk
        }
        var bands: [Int] = []
        for (index, bit) in String(bits.reversed()).enumerated() where bit == "1" {
            bands.append(index + 1)
        }
        return bands
    }
}

/// What is actually known about the two Iranian carriers this router is sold
/// for, kept next to the optimiser so the app decides from the carrier rather
/// than from a guess. Band numbers are the carriers' own holdings; the app
/// still only ever pins to a band it has seen a cell on.
enum CarrierProfile: String {
    case irancell, mci, other

    static func of(_ info: CarrierInfo) -> CarrierProfile {
        switch info.shortOperator {
        case "Irancell": return .irancell
        case "MCI": return .mci
        default: return .other
        }
    }

    var name: String {
        switch self {
        case .irancell: return "Irancell"
        case .mci: return "MCI"
        case .other: return "this SIM"
        }
    }

    /// Most useful first.
    var lteBands: [Int] {
        switch self {
        case .irancell: return [3, 7, 1, 8]
        case .mci: return [3, 1, 8, 7]
        case .other: return [3, 7, 1, 8]
        }
    }

    var nrBands: [Int] {
        switch self {
        case .irancell, .mci: return [78, 41, 40]
        case .other: return [78, 41, 40, 1, 3, 28]
        }
    }

    /// One sentence: where this carrier's speed actually comes from.
    var fastLane: String {
        switch self {
        case .irancell:
            return "Irancell's 4G sits on band 3 (1800 MHz) with band 7 (2600 MHz) "
                 + "able to add capacity, and its 5G is n78 (3500 MHz), which always "
                 + "rides on an LTE anchor. An anchor plus n78 is the fast lane."
        case .mci:
            return "MCI's 4G sits on band 3 (1800 MHz) with bands 1 and 8 as "
                 + "fallbacks, and its 5G is n78 (3500 MHz) riding on an LTE anchor. "
                 + "LTE band 3 plus n78 is the fast lane."
        case .other:
            return "The fast lane on any carrier is an LTE anchor plus a 5G carrier; "
                 + "when a 5G cell is visible, pinning to it usually beats a 4G-only lock."
        }
    }

    /// The thing that most often goes wrong and is worth saying plainly.
    var warning: String {
        switch self {
        case .irancell, .mci:
            return "A 5G lock without an LTE anchor cannot register on these "
                 + "networks, so the app never tries it."
        case .other:
            return "A 5G lock without an LTE anchor can fail on non-standalone "
                 + "networks, so the app keeps the anchor."
        }
    }
}

struct CheckItem: Identifiable {
    let id = UUID()
    let title: String
    let ok: Bool
    let detail: String
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Reach: Equatable { case checking, reachable, unreachable }

    @Published var reach: Reach = .checking
    @Published var provisioned = false
    @Published var carrier = CarrierInfo()
    @Published var status = TunnelStatus()
    @Published var configs: [ConfigEntry] = []
    @Published var currentConfig = "—"

    @Published var engine: VPNEngine =
        VPNEngine(rawValue: UserDefaults.standard.string(forKey: "vpnEngine") ?? "")
            ?? .amnezia {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: "vpnEngine") }
    }
    @Published var sb = SBTunnelStatus()
    @Published var links: [LinkEntry] = []
    @Published var testingAllLinks = false
    @Published var busy: String?
    @Published var notice: String?
    @Published var lastRefresh: Date?
    @Published var speed: SpeedResult?
    @Published var samples: [SpeedSample] = []
    @Published var measuring = false
    @Published var cells: [RadioCell] = []
    @Published var bandSettings = BandSettings()
    @Published var scannedAt: Date?
    @Published var scanningRadio = false
    @Published var radioBusy: String?
    @Published var tuningRadio = false
    @Published var tuneLog: [String] = []
    @Published var tuneSamples: [SpeedSample] = []
    @Published var tuneVerdict: String?

    @Published var checks: [CheckItem] = []
    @Published var checking = false
    @Published var checksPassed: Int?
    @Published var checksTotal: Int?

    @Published var setupLog: [String] = []
    @Published var setupRunning = false
    @Published var setupFinished = false

    @Published var password: String =
        UserDefaults.standard.string(forKey: "panelPassword") ?? "admin" {
        didSet { UserDefaults.standard.set(password, forKey: "panelPassword") }
    }

    private var refreshing = false
    private let server = FileServer(root: AppResources.routerDirectory)

    var vpnOn: Bool { engine == .amnezia ? status.isOn : sb.isOn }
    var linksReady: Bool { sb.installed && !links.isEmpty }

    /// The name of whatever is actually carrying traffic, so no screen has to
    /// name one engine's config while the other one is running.
    var activeLinkLabel: String {
        links.first { $0.name == sb.active }?.label ?? sb.active
    }
    var activeLabel: String {
        engine == .amnezia
            ? (currentConfig == "—" ? "None" : currentConfig)
            : activeLinkLabel
    }
    var activeExitIP: String {
        engine == .amnezia ? status.exitIP : sb.exitIP
    }

    // MARK: - Reading the router

    func refresh() async {
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }
        if reach != .reachable { reach = .checking }

        let panel = PanelClient(password: password)
        var info = CarrierInfo()
        var panelOK = false
        do {
            let basics = try await panel.command(113)
            let network = try? await panel.command(0)
            let detail = try? await panel.command(207)
            panelOK = true
            info.operatorName = basics["network_operator"] as? String ?? "—"
            info.networkType = basics["network_type_str"] as? String ?? "—"
            info.signalLevel = Int(basics["signal_lvl"] as? String ?? "") ?? 0
            info.simReady = (basics["sim_status"] as? String) == "1"
            info.dataOn = (basics["data_switch"] as? String) != "0"
            info.model = basics["board_type"] as? String ?? "ZLT X28"
            info.firmware = basics["fake_version"] as? String ?? "—"
            info.uptime = Self.uptimeText(basics["uptime"] as? String)
            if let network {
                info.wanIP = network["wanIP"] as? String ?? "—"
                let dns1 = network["wanDNS"] as? String ?? ""
                let dns2 = network["wanDNS_2"] as? String ?? ""
                info.dns = [dns1, dns2].filter { !$0.isEmpty && $0 != "NULL" }
                    .joined(separator: ", ")
                if info.dns.isEmpty { info.dns = "—" }
            }
            if let detail {
                info.firmware = detail["real_fwversion"] as? String ?? info.firmware
                info.hardware = detail["hwversion"] as? String ?? "—"
                info.temperature = (detail["device_temperature"] as? String).map { "\($0) °C" } ?? "—"
            }
        } catch {
            panelOK = false
        }

        carrier = info
        reach = panelOK ? .reachable : .unreachable

        guard panelOK else {
            provisioned = false
            lastRefresh = Date()
            return
        }

        let probe = await RouterSSH.run(
            "/usr/bin/vpn awg list 2>/dev/null; echo '@@'; "
            + "/usr/bin/vpn awg status 2>/dev/null; echo '@@'; "
            + "for f in /etc/amneziawg/awg0.conf.*; do [ -f \"$f\" ] || continue; "
            + "n=${f##*.}; [ \"$n\" = current ] && continue; echo \"cfg:$n\"; "
            + "awk -F' *= *' 'tolower($1)==\"endpoint\" {print \"endpoint:\" $2; exit}' \"$f\"; "
            + "done; echo '@@'; /usr/bin/vpn sb status quick 2>/dev/null; echo '@@'; "
            + "[ -x /data/zltx28/bin/sing-box ] && echo SB_INSTALLED || echo SB_MISSING; "
            + "/usr/bin/vpn sb list 2>/dev/null; echo '@@'; "
            + "for f in /data/zltx28/singbox/links/*.link; do [ -f \"$f\" ] || continue; "
            + "n=${f##*/}; n=${n%.link}; echo \"LINK:$n\"; cat \"$f\"; echo; done",
            timeout: 45)

        provisioned = probe.ok && probe.output.contains("daemon")
        guard provisioned else { lastRefresh = Date(); return }

        let sections = probe.output.components(separatedBy: "@@")
        let listing = sections.count > 1 ? sections[0] : ""
        let statusText = sections.count > 2 ? sections[1] : probe.output
        let configText = sections.count > 2 ? sections[2] : ""
        let sbText = sections.count > 4 ? sections[3] : ""
        let sbListText = sections.count > 5 ? sections[4] : ""
        let linkText = sections.count > 5 ? sections[5] : ""

        configs = Self.parseConfigs(listing: listing, details: configText)
        status = Self.parseStatus(statusText)
        currentConfig = status.config
        var parsedSB = Self.parseSB(sbText, listing: sbListText)
        if parsedSB.isOn && parsedSB.exitIP == "—" { parsedSB.exitIP = sb.exitIP }
        sb = parsedSB
        mergeLinks(Self.parseLinks(linkText), installed: sb.installed)
        lastRefresh = Date()
    }

    private static func parseSB(_ text: String, listing: String) -> SBTunnelStatus {
        var parsed = SBTunnelStatus()
        parsed.installed = listing.contains("SB_INSTALLED")
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("daemon") {
                parsed.running = line.contains("running")
            } else if line.hasPrefix("link") {
                let value = Self.value(after: ":", in: line)
                parsed.active = value.isEmpty ? "-" : value
            } else if line.hasPrefix("boot") {
                parsed.bootEnabled = line.contains("enabled")
            } else if line.hasPrefix("route") && line.contains("default") {
                if line.contains(SingBox.tunName) { parsed.routed = true }
            } else if line.hasPrefix("exit IP") {
                let value = Self.value(after: ":", in: line)
                parsed.exitIP = (value.isEmpty || value == "-" || value.contains("no answer"))
                    ? "—" : value
            }
        }
        return parsed
    }

    /// Each `.link` file holds the original share link, one line, so the app
    /// can show it and re-generate configs later without asking again.
    private static func parseLinks(_ text: String) -> [LinkEntry] {
        var entries: [LinkEntry] = []
        var pending: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("LINK:") {
                pending = String(line.dropFirst(5))
                continue
            }
            guard let name = pending, !line.isEmpty else { continue }
            pending = nil
            guard let link = SingBox.parse(line) else {
                entries.append(LinkEntry(name: name, kind: "Unknown", server: "",
                                         title: name, raw: line))
                continue
            }
            entries.append(LinkEntry(name: name, kind: link.kind,
                                     server: link.server, title: link.title,
                                     raw: link.raw))
        }
        return entries
    }

    private func mergeLinks(_ fresh: [LinkEntry], installed: Bool) {
        sb.installed = installed
        let previous = Dictionary(uniqueKeysWithValues: links.map { ($0.name, $0.status) })
        links = fresh.map { entry in
            var copy = entry
            copy.status = previous[entry.name] ?? .untested
            return copy
        }
        if !installed { links = [] }
    }

    private static func uptimeText(_ raw: String?) -> String {
        guard let raw, let seconds = Int(raw), seconds > 0 else { return "—" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        if seconds < 86_400 { return "\(seconds / 3600) h" }
        return "\(seconds / 86_400) d \(seconds % 86_400 / 3600) h"
    }

    private static func parseConfigs(listing: String, details: String) -> [ConfigEntry] {
        var endpoints: [String: String] = [:]
        var pending: String?
        for line in details.components(separatedBy: .newlines) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("cfg:") {
                pending = String(text.dropFirst(4))
            } else if text.hasPrefix("endpoint:"), let name = pending {
                endpoints[name] = String(text.dropFirst(9))
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: ":").first ?? ""
            }
        }
        return listing.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ConfigEntry(name: $0, endpoint: endpoints[$0] ?? "") }
    }

    private static func parseStatus(_ text: String) -> TunnelStatus {
        var parsed = TunnelStatus()
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("daemon") {
                parsed.daemonRunning = line.contains("running")
            } else if line.hasPrefix("config") {
                parsed.config = Self.value(after: ":", in: line)
            } else if line.hasPrefix("boot") {
                parsed.bootEnabled = line.contains("enabled")
            } else if line.hasPrefix("route") && line.contains("default") {
                parsed.routeThroughTunnel = line.contains("awg0")
            } else if line.hasPrefix("tunnel") {
                if let range = line.range(of: "last_handshake_time_sec=") {
                    let tail = line[range.upperBound...]
                    parsed.handshakeEpoch = Int(tail.prefix { $0.isNumber }) ?? 0
                }
                if let range = line.range(of: "tx_bytes=") {
                    let tail = line[range.upperBound...]
                    parsed.txBytes = Int64(tail.prefix { $0.isNumber }) ?? 0
                }
                if let range = line.range(of: "rx_bytes=") {
                    let tail = line[range.upperBound...]
                    parsed.rxBytes = Int64(tail.prefix { $0.isNumber }) ?? 0
                }
            } else if line.hasPrefix("exit IP") {
                let value = Self.value(after: ":", in: line)
                parsed.exitIP = (value.isEmpty || value.contains("no answer")) ? "—" : value
            }
        }
        return parsed
    }

    private static func value(after marker: Character, in line: String) -> String {
        guard let index = line.firstIndex(of: marker) else { return "" }
        return String(line[line.index(after: index)...])
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Tunnel actions

    func turnOn() async {
        if engine == .amnezia { await runVPN("on", label: "Starting the tunnel…") }
        else { await runSB("on", label: "Starting the link tunnel…") }
    }

    func turnOff() async {
        if engine == .amnezia { await runVPN("off", label: "Stopping the tunnel…") }
        else { await runSB("off", label: "Stopping the link tunnel…") }
    }

    func restartTunnel() async {
        if engine == .amnezia { await runVPN("restart", label: "Restarting the tunnel…") }
        else { await runSB("restart", label: "Restarting the link tunnel…") }
    }

    private func runVPN(_ verb: String, label: String) async {
        guard !setupRunning else { return }
        busy = label
        notice = nil
        let result = await RouterSSH.run("/usr/bin/vpn awg \(verb)", timeout: 120)
        busy = nil
        if !result.ok {
            notice = result.trimmed.isEmpty
                ? "The router did not answer. Is this Mac still on the X28 Wi-Fi?"
                : result.trimmed
        }
        await refresh()
    }

    func useConfig(_ name: String) async {
        busy = "Switching to \(name)…"
        notice = nil
        let wasOn = vpnOn
        let suffix = wasOn ? " && /usr/bin/vpn awg restart" : ""
        let result = await RouterSSH.run(
            "/usr/bin/vpn awg use '\(name)'\(suffix)", timeout: 120)
        busy = nil
        if !result.ok { notice = result.trimmed }
        await refresh()
    }

    func removeConfig(_ name: String) async {
        busy = "Removing \(name)…"
        notice = nil
        let stamp = Int(Date().timeIntervalSince1970)
        let result = await RouterSSH.run(
            "mv '/etc/amneziawg/awg0.conf.\(name)' "
            + "'/etc/amneziawg/awg0.conf.\(name).disabled-\(stamp)'",
            timeout: 30)
        busy = nil
        notice = result.ok
            ? "\(name) was set aside. The file is still on the router, renamed with .disabled."
            : "Could not remove the config: \(result.trimmed)"
        await refresh()
    }

    // MARK: - Links (the sing-box engine)

    private func runSB(_ verb: String, label: String) async {
        guard !setupRunning else { return }
        busy = label
        notice = nil
        let result = await RouterSSH.run("/usr/bin/vpn sb \(verb)", timeout: 150)
        busy = nil
        if !result.ok {
            notice = result.trimmed.isEmpty
                ? "The router did not answer. Is this Mac still on the X28 Wi-Fi?"
                : result.trimmed
        }
        await refresh()
        if sb.isOn { await fetchSBExit() }
    }

    /// The polling status call skips the exit-IP lookup to stay quick, so it is
    /// fetched once right after the tunnel comes up.
    private func fetchSBExit() async {
        let result = await RouterSSH.run("/usr/bin/vpn sb status", timeout: 30)
        let detail = Self.parseSB(result.output, listing: "")
        if detail.isOn {
            sb.exitIP = detail.exitIP
            sb.active = detail.active
        }
    }

    func importLinks(_ text: String) async {
        guard sb.installed else {
            notice = "The link engine is not on this router yet. Open Router setup "
                   + "and run setup once — it installs it."
            return
        }
        let raws = text.components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: " ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !raws.isEmpty else { return }

        var known = Set(links.map(\.raw))
        var taken = Set(links.map(\.name))
        var additions: [(link: ShareLink, name: String)] = []
        var unrecognised = 0
        for raw in raws {
            guard let link = SingBox.parse(raw) else { unrecognised += 1; continue }
            if known.contains(link.raw) { continue }
            known.insert(link.raw)
            var name = link.fileBase
            var counter = 2
            while taken.contains(name) {
                name = "\(link.fileBase)-\(counter)"
                counter += 1
            }
            taken.insert(name)
            additions.append((link, name))
        }

        guard !additions.isEmpty else {
            if unrecognised > 0 {
                notice = "Nothing was added: \(unrecognised) line(s) were not a link "
                       + "this app can read. Links start with vless://, vmess://, "
                       + "trojan://, ss:// or hysteria2://."
            } else {
                notice = "Those links are already in the list."
            }
            return
        }

        busy = additions.count == 1
            ? "Copying the link to the router…"
            : "Copying \(additions.count) links to the router…"
        notice = nil

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zlt-links-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var copied: [String] = []
        var failure: String?
        for (link, name) in additions {
            guard let tun = SingBox.tunConfig(outbound: link.outbound),
                  let test = SingBox.testConfig(outbound: link.outbound) else {
                failure = "Could not build a config for \(name)."
                continue
            }
            let tunURL = dir.appendingPathComponent("\(name).json")
            let testURL = dir.appendingPathComponent("\(name).test.json")
            let rawURL = dir.appendingPathComponent("\(name).link")
            do {
                try tun.write(to: tunURL)
                try test.write(to: testURL)
                try (link.raw + "\n").write(to: rawURL, atomically: true, encoding: .utf8)
            } catch {
                failure = "Could not write \(name): \(error.localizedDescription)"
                continue
            }

            let base = "/data/zltx28/singbox/links/\(name)"
            let copies = [(tunURL, "\(base).json"),
                          (testURL, "\(base).test.json"),
                          (rawURL, "\(base).link")]
            var ok = true
            for (file, remote) in copies {
                let result = await RouterSSH.scp(file, to: remote, timeout: 60)
                if !result.ok {
                    ok = false
                    failure = "Could not copy \(name) to the router: \(result.trimmed)"
                    break
                }
            }
            if ok { copied.append(name) }
        }

        if let first = copied.first, sb.active == "-" {
            _ = await RouterSSH.run("/usr/bin/vpn sb use '\(first)'", timeout: 30)
        }
        busy = nil
        await refresh()

        if let failure {
            notice = failure
        } else if unrecognised > 0 {
            notice = "Added \(copied.count) link(s). \(unrecognised) line(s) were skipped "
                   + "because they are not links this app can read."
        } else {
            notice = copied.count == 1
                ? "Link added. Press “Test” to see whether it works."
                : "\(copied.count) links added. Press “Test all” to sort the fast from the dead."
        }
    }

    func testLink(_ name: String) async {
        setLinkStatus(.testing, for: name)
        let result = await RouterSSH.run("/usr/bin/vpn sb test '\(name)'", timeout: 90)
        applyTest(result, expected: name)
    }

    func testAllLinks() async {
        guard !links.isEmpty else { return }
        testingAllLinks = true
        busy = "Testing \(links.count) link\(links.count == 1 ? "" : "s")…"
        notice = nil
        for entry in links { setLinkStatus(.testing, for: entry.name) }
        let timeout = min(600, max(120, Double(links.count) * 80))
        let result = await RouterSSH.run("/usr/bin/vpn sb testall", timeout: timeout)
        for line in result.output.components(separatedBy: .newlines)
            where line.hasPrefix("RESULT|") {
            applyTestLine(line)
        }
        for entry in links where entry.status == .testing {
            setLinkStatus(.dead(result.ok ? "No answer in time"
                                          : "No answer — the router did not finish"),
                          for: entry.name)
        }
        let alive = links.filter { $0.status.isAlive }.count
        busy = nil
        testingAllLinks = false
        notice = alive == 0
            ? "None of those links answered. They may be dead, or the carrier "
            + "may be blocking them."
            : "\(alive) of \(links.count) links answered."
    }

    private func applyTest(_ result: ShellResult, expected name: String) {
        if let line = result.output.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("RESULT|") }) {
            applyTestLine(line)
            return
        }
        let reason = result.trimmed.isEmpty
            ? "No answer — the test could not reach the router"
            : result.trimmed.components(separatedBy: .newlines).last ?? "Test failed"
        setLinkStatus(.dead(reason), for: name)
    }

    private func applyTestLine(_ line: String) {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 5 else { return }
        let name = parts[1]
        let code = parts[2]
        let ms = Int(parts[3]) ?? 0
        let bps = Int(Double(parts[4]) ?? 0)
        if (code == "204" || code == "200") && ms > 0 {
            setLinkStatus(.alive(ms: ms, bytesPerSecond: bps), for: name)
        } else if code == "404" {
            setLinkStatus(.dead("The link file is missing on the router"), for: name)
        } else {
            setLinkStatus(.dead("No answer — dead, blocked, or wrong details"), for: name)
        }
    }

    private func setLinkStatus(_ status: LinkStatus, for name: String) {
        if let index = links.firstIndex(where: { $0.name == name }) {
            links[index].status = status
        }
    }

    func useLink(_ name: String) async {
        busy = "Switching to \(name)…"
        notice = nil
        let wasOn = sb.isOn
        let suffix = wasOn ? " && /usr/bin/vpn sb restart" : ""
        let result = await RouterSSH.run("/usr/bin/vpn sb use '\(name)'\(suffix)",
                                         timeout: 150)
        busy = nil
        if !result.ok { notice = result.trimmed }
        await refresh()
        if sb.isOn { await fetchSBExit() }
    }

    func removeLink(_ name: String) async {
        busy = "Removing \(name)…"
        notice = nil
        let result = await RouterSSH.run("/usr/bin/vpn sb remove '\(name)'", timeout: 60)
        busy = nil
        notice = result.ok
            ? "\(name) was set aside. The router keeps a copy under "
              + "/data/zltx28/singbox/trash, so nothing is lost."
            : "Could not remove the link: \(result.trimmed)"
        await refresh()
    }

    func importConfig(from url: URL) async {
        let stem = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "-")
        let safe = String(stem.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        guard !safe.isEmpty else {
            notice = "That file name cannot be used. Use letters, digits, - or _."
            return
        }
        guard url.pathExtension.lowercased() == "conf" else {
            notice = "Choose a .conf file (WireGuard or AmneziaWG)."
            return
        }
        busy = "Copying \(safe) to the router…"
        notice = nil
        var name = safe
        var counter = 2
        while configs.contains(where: { $0.name == name }) {
            name = "\(safe)-\(counter)"
            counter += 1
        }
        let result = await RouterSSH.scp(
            url, to: "/etc/amneziawg/awg0.conf.\(name)")
        busy = nil
        guard result.ok else {
            notice = "Could not copy the config. \(result.trimmed)"
            return
        }
        await useConfig(name)
        notice = "\(name) is ready. Turn the VPN on to use it."
    }

    func testLogin() async {
        busy = "Checking the admin password…"
        notice = nil
        let panel = PanelClient(password: password)
        do {
            _ = try await panel.command(113)
            notice = "The admin password works. You can install the engine."
        } catch {
            notice = error.localizedDescription
        }
        busy = nil
        await refresh()
    }

    func testTunnel() async {
        busy = "Testing the tunnel…"
        notice = nil
        if engine == .links {
            let result = await RouterSSH.run(
                "/usr/bin/vpn sb status; echo '@@'; "
                + "curl -s -o /dev/null --max-time 10 --interface sb0 "
                + "-w '%{http_code}' https://www.gstatic.com/generate_204 2>/dev/null",
                timeout: 60)
            busy = nil
            let answered = result.output.contains("204")
            notice = answered
                ? "The link tunnel is carrying traffic. Exit IP: \(sb.exitIP)."
                : "The link tunnel is not carrying traffic. Test the links, or "
                  + "try another one, then restart."
            await refresh()
            return
        }
        let result = await RouterSSH.run(
            "/usr/bin/vpn awg status; echo '@@'; "
            + "ping -c2 -W3 -I awg0 8.8.8.8 >/dev/null 2>&1 && echo PING_OK || echo PING_FAIL",
            timeout: 45)
        busy = nil
        let ok = result.output.contains("PING_OK") && result.output.contains("running")
        notice = ok
            ? "The tunnel is carrying traffic. Exit IP: \(status.exitIP)."
            : "The tunnel is not carrying traffic. Try Restart, then check the config."
        await refresh()
    }

    // MARK: - Checks

    /// Runs the same end-to-end checks a person would do by hand, and keeps a
    /// pass/fail row for each one so the user can see exactly where it stopped.
    func runChecks() async {
        guard !checking else { return }
        checking = true
        notice = nil
        checks = []

        await refresh()

        var rows: [CheckItem] = []

        rows.append(CheckItem(
            title: "This Mac can reach the router",
            ok: reach == .reachable,
            detail: reach == .reachable
                ? "The router answered at \(RouterSSH.host)."
                : "No answer. Join the router's Wi-Fi, then press Run the checks again."))

        guard reach == .reachable else {
            checks = rows
            checksPassed = nil
            checking = false
            return
        }

        rows.append(CheckItem(
            title: "The VPN engine is installed",
            ok: provisioned,
            detail: provisioned
                ? "The router has the VPN software and its start-up service."
                : "Not installed yet. Open Setup and run the one-time installation."))

        guard provisioned else {
            checks = rows
            checksPassed = nil
            checking = false
            return
        }

        let probe = await RouterSSH.run(
            "/usr/bin/vpn awg status 2>/dev/null; echo '@@'; "
            + "ping -c2 -W3 -I awg0 1.1.1.1 >/dev/null 2>&1 && echo PING_OK || echo PING_FAIL; "
            + "echo '@@'; "
            + "curl -s -m 8 -o /dev/null -w '%{http_code}' --interface awg0 "
            + "https://api.ipify.org 2>/dev/null; echo; echo '@@'; "
            + "ifconfig awg0 2>/dev/null | grep -o 'inet addr:[0-9.]*' | head -1",
            timeout: 60)

        let sections = probe.output.components(separatedBy: "@@")
        let statusText = sections.count > 0 ? sections[0] : ""
        let pingText = sections.count > 1 ? sections[1] : ""
        let httpText = sections.count > 2 ? sections[2] : ""
        let ifText = sections.count > 3 ? sections[3] : ""

        let live = Self.parseStatus(statusText)
        let pingOK = pingText.contains("PING_OK")
        let httpOK = httpText.contains("200")
        let hasTunnelIP = ifText.contains("inet addr:")

        rows.append(CheckItem(
            title: "The tunnel is running",
            ok: live.daemonRunning,
            detail: live.daemonRunning
                ? "The tunnel software is running on the router."
                : "The tunnel is switched off. Use the switch on the Home screen."))

        rows.append(CheckItem(
            title: "Traffic is routed through the tunnel",
            ok: live.routeThroughTunnel,
            detail: live.routeThroughTunnel
                ? "The router's default route points into the tunnel."
                : "Traffic is going out directly. This is normal when the VPN is off."))

        let fresh = live.handshakeEpoch > 0
            && Date().timeIntervalSince1970 - Double(live.handshakeEpoch) < 180
        rows.append(CheckItem(
            title: "The server has answered recently",
            ok: fresh,
            detail: live.handshakeEpoch > 0
                ? "Last handshake \(live.handshakeText)."
                : "No handshake yet. The server may be down or the config key is wrong."))

        rows.append(CheckItem(
            title: "The tunnel carries real traffic",
            ok: pingOK && (httpOK || hasTunnelIP),
            detail: pingOK && httpOK
                ? "A ping and an HTTPS request both left through the tunnel."
                : pingOK
                ? "Ping worked. The HTTPS test did not — DNS may be blocked."
                : "Nothing came back through the tunnel. Try Restart, then test again."))

        rows.append(CheckItem(
            title: "The tunnel starts after a power cut",
            ok: live.bootEnabled,
            detail: live.bootEnabled
                ? "The tunnel service is enabled at boot."
                : "The service will not start by itself after a reboot."))

        let exitIsDifferent = !live.exitIP.isEmpty && live.exitIP != "—"
            && live.exitIP != carrier.wanIP
        rows.append(CheckItem(
            title: "Websites see a different address",
            ok: exitIsDifferent,
            detail: exitIsDifferent
                ? "Sites see \(live.exitIP); the SIM's own address is \(carrier.wanIP)."
                : "This could not be confirmed. The exit address did not come back."))

        checks = rows
        let passed = rows.filter(\.ok).count
        checksPassed = passed
        checksTotal = rows.count
        checking = false
        notice = passed == rows.count
            ? "All \(rows.count) checks passed. The VPN works."
            : "\(passed) of \(rows.count) checks passed. The red ones say what to do."
        await refresh()
    }

    // MARK: - Speed

    func measureSpeed() async {
        guard !measuring else { return }
        measuring = true
        notice = nil
        let result = await SpeedTest.run()
        measuring = false
        if let result {
            speed = result
            samples = [SpeedSample(label: vpnOn ? "Through VPN" : "Direct (no VPN)",
                                   result: result)]
        } else {
            notice = "The speed test could not finish. The line may be busy or blocked."
        }
    }

    func compareSpeed() async {
        guard !measuring, provisioned else { return }
        measuring = true
        notice = nil
        samples = []
        let wasOn = vpnOn

        if wasOn {
            _ = await RouterSSH.run("/usr/bin/vpn awg off", timeout: 90)
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if let direct = await SpeedTest.run() {
            samples.append(SpeedSample(label: "Direct (no VPN)", result: direct))
        }

        let start = await RouterSSH.run("/usr/bin/vpn awg on", timeout: 120)
        if start.ok {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let tunnelled = await SpeedTest.run() {
                samples.append(SpeedSample(label: "Through VPN", result: tunnelled))
            }
        }

        if !wasOn {
            _ = await RouterSSH.run("/usr/bin/vpn awg off", timeout: 90)
        }
        measuring = false
        if samples.count < 2 {
            notice = "The comparison did not finish. The tunnel was restored to its "
                   + "original state."
        }
        await refresh()
    }

    // MARK: - Radio & bands

    func loadBands() async {
        guard radioBusy == nil else { return }
        let panel = PanelClient(password: password)
        if let reply = try? await panel.command(161) {
            bandSettings = Self.parseBands(reply)
        }
    }

    func scanRadio() async {
        guard !scanningRadio else { return }
        scanningRadio = true
        defer { scanningRadio = false }
        notice = nil

        let panel = PanelClient(password: password)
        if let reply = try? await panel.command(161) {
            bandSettings = Self.parseBands(reply)
        }
        guard let reply = try? await panel.command(342) else {
            notice = "The scan did not answer. The mobile link may be busy; try again."
            return
        }
        let found = Self.parseCells(reply)
        guard !found.isEmpty else {
            let message = Self.text(reply["message"])
            notice = message == "507"
                ? "The scan timed out. Your connection is still up; try again."
                : "No cells came back this time. The router may have dropped the mobile link for a moment; scan again."
            return
        }
        cells = found.sorted { $0.generation == $1.generation ? $0.rsrp > $1.rsrp : $0.generation == "5G" }
        scannedAt = Date()
    }

    func bestCell(_ generation: String) -> RadioCell? {
        cells.filter { $0.generation == generation }.max { $0.rsrp < $1.rsrp }
    }

    func restoreAutomaticBands() async {
        guard radioBusy == nil, !tuningRadio else { return }
        radioBusy = "Putting every band back…"
        defer { radioBusy = nil }
        do {
            try await applyBandLock(lte: nil, nr: nil)
            notice = "The router chooses its own bands again. That is the normal setting."
        } catch {
            notice = error.localizedDescription
        }
    }

    func pinToCurrentBands() async {
        guard radioBusy == nil, !tuningRadio else { return }
        let lte = bestCell("4G")?.bandNumber
        let nr = bestCell("5G")?.bandNumber
        guard lte != nil || nr != nil else {
            notice = "Scan first — there is nothing to pin to yet."
            return
        }
        radioBusy = "Pinning the router to the bands it is using…"
        defer { radioBusy = nil }
        do {
            try await applyBandLock(lte: lte, nr: nr)
            notice = "Pinned to \(Self.bandNames(lte: lte, nr: nr)). Your Wi-Fi is unaffected; the mobile link reconnects by itself."
        } catch {
            notice = error.localizedDescription
        }
    }

    func tuneRadio() async {
        guard !tuningRadio, !scanningRadio else { return }
        tuningRadio = true
        tuneLog = []
        tuneSamples = []
        tuneVerdict = nil
        notice = nil
        defer { tuningRadio = false }

        tuneLog.append("Looking at the cell towers the router can see…")
        await scanRadio()
        guard !cells.isEmpty else {
            tuneLog.append("No cells were visible, so there is nothing to pin to. Nothing was changed.")
            tuneVerdict = "The scan found no cells. Try again when the mobile signal is back."
            return
        }

        let lte = bestCell("4G")?.bandNumber
        let nr = bestCell("5G")?.bandNumber
        let names = Self.bandNames(lte: lte, nr: nr)
        tuneLog.append("Best cells right now: \(names).")

        if bandSettings.isLocked {
            tuneLog.append("The router was pinned before this test. Putting it back on automatic so the test starts from normal.")
            do {
                try await applyBandLock(lte: nil, nr: nil)
            } catch {
                tuneVerdict = "Could not return the router to automatic, so the test stopped: \(error.localizedDescription)"
                return
            }
            _ = await waitForRegistration(seconds: 75)
        }

        tuneLog.append("Measuring with every band allowed (about 8 MB)…")
        guard let automatic = await SpeedTest.run(bytes: 8_000_000) else {
            tuneLog.append("The measurement failed.")
            tuneVerdict = "The first speed test did not finish, so nothing was pinned. The router is on automatic."
            return
        }
        tuneSamples.append(SpeedSample(label: "Automatic (all bands)", result: automatic))
        tuneLog.append("Automatic: \(Self.speedText(automatic)).")

        guard lte != nil || nr != nil else {
            tuneVerdict = "The router's band could not be identified, so nothing was pinned. Automatic stays on."
            return
        }

        tuneLog.append("Pinning to \(names)…")
        do {
            try await applyBandLock(lte: lte, nr: nr)
        } catch {
            tuneLog.append("The router refused the lock.")
            tuneVerdict = "The router refused the band lock, so it stays on automatic. Nothing else changed."
            return
        }

        tuneLog.append("Waiting for it to reconnect on the pinned band…")
        if !(await waitForRegistration(seconds: 90)) {
            tuneLog.append("It did not come back on the pinned band in time.")
            _ = try? await applyBandLock(lte: nil, nr: nil)
            tuneVerdict = "Pinning did not reconnect, so the router was put back on automatic. On this SIM, a band lock would cost you the connection."
            return
        }

        tuneLog.append("Measuring again on the pinned band…")
        guard let pinned = await SpeedTest.run(bytes: 8_000_000) else {
            tuneLog.append("The pinned measurement failed.")
            _ = try? await applyBandLock(lte: nil, nr: nil)
            tuneVerdict = "The second speed test did not finish, so the router was put back on automatic. Not worth risking the link for an unproven gain."
            return
        }
        tuneSamples.append(SpeedSample(label: "Pinned to \(names)", result: pinned))
        tuneLog.append("Pinned: \(Self.speedText(pinned)).")

        let gain = automatic.mbps > 0
            ? (pinned.mbps - automatic.mbps) / automatic.mbps * 100 : 0
        if pinned.mbps > automatic.mbps * 1.08 {
            tuneLog.append("The pinned band wins — keeping it.")
            tuneVerdict = "Pinning is about \(Int(gain.rounded()))% faster (\(Self.speedText(pinned)) vs \(Self.speedText(automatic))). The router is staying on \(names)."
        } else {
            _ = try? await applyBandLock(lte: nil, nr: nil)
            tuneLog.append("No gain — put back on automatic.")
            if pinned.mbps < automatic.mbps * 0.92 {
                tuneVerdict = "Pinning was about \(Int(abs(gain).rounded()))% slower, so the router is back on automatic. A stronger signal does not always mean more speed."
            } else {
                tuneVerdict = "No real difference (\(Self.speedText(pinned)) vs \(Self.speedText(automatic))), so the router is back on automatic. When pinning buys nothing, automatic is the safer setting."
            }
        }
    }

    /// One press: measure the carrier's own fast lane against the band the
    /// router picked by itself, and keep the winner. Every dead end restores
    /// the router rather than leaving it on an unproven lock.
    func optimizeCarrier() async {
        guard !tuningRadio, !scanningRadio, radioBusy == nil else { return }
        tuningRadio = true
        tuneLog = []
        tuneSamples = []
        tuneVerdict = nil
        notice = nil
        defer { tuningRadio = false }

        let profile = CarrierProfile.of(carrier)
        tuneLog.append("Optimising for \(profile.name). \(profile.fastLane)")

        await scanRadio()
        guard !cells.isEmpty else {
            tuneLog.append("No cells were visible.")
            tuneVerdict = "The scan found no cells, so nothing was measured and nothing was changed."
            return
        }
        let seen4 = cells.filter { $0.generation == "4G" }
        let seen5 = cells.filter { $0.generation == "5G" }
        guard let anchor = seen4.max(by: { $0.rsrp < $1.rsrp }),
              let anchorBand = anchor.bandNumber else {
            tuneLog.append("No usable 4G cell was visible.")
            tuneVerdict = "Without a 4G anchor nothing can be pinned safely, so the "
                        + "router stays on automatic."
            return
        }
        let nrCell = seen5.max { $0.rsrp < $1.rsrp }
        let nrBand = nrCell?.bandNumber
        tuneLog.append("Visible now: \(anchor.bandLabel) at \(anchor.rsrp) dBm"
            + (nrCell.map { ", \($0.bandLabel) at \($0.rsrp) dBm" }
               ?? ", no 5G cell"))

        // Plans come from the carrier profile, filtered by bands the radio can
        // actually hear — a band with no cell on it is never one of them.
        struct Plan { let label: String; let lte: Int?; let nr: Int? }
        var plans: [Plan] = []
        if let nrBand {
            plans.append(Plan(label: "\(anchor.bandLabel) + n\(nrBand)",
                              lte: anchorBand, nr: nrBand))
            plans.append(Plan(label: "\(anchor.bandLabel) only (5G off)",
                              lte: anchorBand, nr: nil))
        } else {
            plans.append(Plan(label: "\(anchor.bandLabel) only",
                              lte: anchorBand, nr: nil))
        }
        let seenBands4 = Set(seen4.compactMap { $0.bandNumber })
        let seenBands5 = Set(seen5.compactMap { $0.bandNumber })
        if let preferred4 = profile.lteBands.first(where: { seenBands4.contains($0) }),
           let preferred5 = profile.nrBands.first(where: { seenBands5.contains($0) }),
           !plans.contains(where: { $0.lte == preferred4 && $0.nr == preferred5 }) {
            plans.append(Plan(label: "Band \(preferred4) + n\(preferred5) (carrier pair)",
                              lte: preferred4, nr: preferred5))
        }
        plans = Array(plans.prefix(3))

        // Honest numbers need the tunnel out of the way.
        let hadTunnel = vpnOn
        if hadTunnel {
            tuneLog.append("Turning the VPN off while measuring; it comes back at the end.")
            await turnOff()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        if bandSettings.isLocked {
            tuneLog.append("The router was pinned before this test; returning it to automatic first.")
            _ = try? await applyBandLock(lte: nil, nr: nil)
            _ = await waitForRegistration(seconds: 75)
        }

        tuneLog.append("Measuring with every band allowed (about 8 MB)…")
        guard let automatic = await SpeedTest.run(bytes: 8_000_000) else {
            if hadTunnel { await turnOn() }
            tuneVerdict = "The first measurement did not finish, so nothing was pinned. "
                        + "The router is on automatic."
            return
        }
        tuneSamples.append(SpeedSample(label: "Automatic (all bands)", result: automatic))
        tuneLog.append("Automatic: \(Self.speedText(automatic)).")

        var best: (label: String, lte: Int?, nr: Int?, result: SpeedResult)?
        for plan in plans {
            tuneLog.append("Pinning to \(plan.label)…")
            do {
                try await applyBandLock(lte: plan.lte, nr: plan.nr)
            } catch {
                tuneLog.append("The router refused that lock; going on to the next one.")
                _ = try? await applyBandLock(lte: nil, nr: nil)
                continue
            }
            guard await waitForRegistration(seconds: 90) else {
                tuneLog.append("It did not come back on \(plan.label); skipping it.")
                _ = try? await applyBandLock(lte: nil, nr: nil)
                _ = await waitForRegistration(seconds: 60)
                continue
            }
            guard let result = await SpeedTest.run(bytes: 8_000_000) else {
                tuneLog.append("The measurement on \(plan.label) failed; skipping it.")
                _ = try? await applyBandLock(lte: nil, nr: nil)
                _ = await waitForRegistration(seconds: 60)
                continue
            }
            tuneSamples.append(SpeedSample(label: plan.label, result: result))
            tuneLog.append("\(plan.label): \(Self.speedText(result)).")
            if result.mbps > (best?.result.mbps ?? 0) {
                best = (plan.label, plan.lte, plan.nr, result)
            }
            _ = try? await applyBandLock(lte: nil, nr: nil)
            _ = await waitForRegistration(seconds: 60)
        }

        var kept = false
        if let best, best.result.mbps > automatic.mbps * 1.08 {
            do {
                try await applyBandLock(lte: best.lte, nr: best.nr)
                if await waitForRegistration(seconds: 90) {
                    kept = true
                    tuneLog.append("Keeping \(best.label).")
                    let gain = (best.result.mbps - automatic.mbps) / automatic.mbps * 100
                    tuneVerdict = "\(best.label) is about \(Int(gain.rounded()))% faster "
                        + "(\(Self.speedText(best.result)) vs \(Self.speedText(automatic))), "
                        + "so the router is staying on it. A pin lasts until the tower "
                        + "or your location changes — press Optimize again then."
                }
            } catch {
                tuneLog.append("The router refused to keep the winner.")
            }
        }
        if !kept {
            _ = try? await applyBandLock(lte: nil, nr: nil)
            tuneLog.append("No lock beat automatic, so the router is back on every band.")
            tuneVerdict = "Automatic was as good as or better than every lock this "
                + "time, so the router stays on automatic. That is normal on "
                + "\(profile.name): the network already combines the bands it wants. "
                + "\(profile.warning)"
        }

        if hadTunnel {
            tuneLog.append("Turning the VPN back on…")
            await turnOn()
        }
    }

    private func applyBandLock(lte: Int?, nr: Int?) async throws {
        let all4 = bandSettings.all4g.isEmpty ? "7A0880800D5" : bandSettings.all4g
        let all5 = bandSettings.all5g.isEmpty ? "3000000001A0080800D5" : bandSettings.all5g
        let extra: [String: Any] = [
            "band4gRadio": lte == nil ? "0" : "1",
            "band5gRadio": nr == nil ? "0" : "1",
            "lock4gBand": lte.map { BandPlan.mask(bands: [$0]) } ?? all4,
            "lock5gBand": nr.map { BandPlan.mask(bands: [$0]) } ?? all5,
        ]
        let panel = PanelClient(password: password)
        _ = try await panel.command(161, extra: extra, method: "POST")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if let reply = try? await PanelClient(password: password).command(161) {
            bandSettings = Self.parseBands(reply)
        } else {
            bandSettings.lock4g = lte != nil
            bandSettings.lock5g = nr != nil
        }
    }

    private func waitForRegistration(seconds: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(seconds))
        var goodPolls = 0
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let panel = PanelClient(password: password)
            guard let reply = try? await panel.command(113) else {
                goodPolls = 0
                continue
            }
            let type = Self.text(reply["network_type_str"])
            let level = Int(Self.text(reply["signal_lvl"])) ?? 0
            if !type.isEmpty && level > 0 {
                goodPolls += 1
                if goodPolls >= 2 { return true }
            } else {
                goodPolls = 0
            }
        }
        return false
    }

    private static func parseBands(_ reply: [String: Any]) -> BandSettings {
        var settings = BandSettings()
        settings.lock4g = text(reply["band_4g_switch"]) == "1"
        settings.lock5g = text(reply["band_5g_switch"]) == "1"
        settings.all4g = text(reply["all_band_4g"])
        settings.all5g = text(reply["all_band_5g"])
        settings.mask4g = text(reply["band_4g_mask"])
        settings.mask5g = text(reply["band_5g_mask"])
        return settings
    }

    private static func parseCells(_ reply: [String: Any]) -> [RadioCell] {
        func list(_ key: String) -> [String] {
            text(reply[key]).split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func number(_ raw: String) -> Int? {
            guard let value = Double(raw.filter { "0123456789.-".contains($0) })
            else { return nil }
            return Int(value)
        }
        var found: [RadioCell] = []
        let p4 = list("pcid_4g"), r4 = list("rsrp_4g"), e4 = list("earfcn_4g")
        for index in 0..<p4.count where index < r4.count && index < e4.count {
            guard !p4[index].isEmpty, let rsrp = number(r4[index]),
                  let earfcn = number(e4[index]) else { continue }
            found.append(RadioCell(generation: "4G", pci: p4[index],
                                   earfcn: earfcn, rsrp: rsrp))
        }
        let p5 = list("pcid_5g"), r5 = list("rsrp_5g"), e5 = list("earfcn_5g")
        for index in 0..<p5.count where index < r5.count && index < e5.count {
            guard !p5[index].isEmpty, let rsrp = number(r5[index]),
                  let earfcn = number(e5[index]) else { continue }
            found.append(RadioCell(generation: "5G", pci: p5[index],
                                   earfcn: earfcn, rsrp: rsrp))
        }
        return found
    }

    static func text(_ value: Any?) -> String {
        if let value = value as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    static func bandNames(lte: Int?, nr: Int?) -> String {
        var parts: [String] = []
        if let lte { parts.append("4G Band \(lte)") }
        if let nr { parts.append("5G n\(nr)") }
        return parts.isEmpty ? "no cell" : parts.joined(separator: " + ")
    }

    static func speedText(_ result: SpeedResult) -> String {
        String(format: "%.1f Mbps", result.mbps)
    }

    // MARK: - Setup

    func runSetup() async {
        guard !setupRunning else { return }
        setupRunning = true
        setupFinished = false
        setupLog = []
        notice = nil
        let provisioner = Provisioner(
            password: password,
            server: server,
            publish: { [weak self] line in
                guard let self else { return }
                self.setupLog.append(line)
            })
        do {
            try await provisioner.provision()
            setupLog.append("Setup finished.")
            setupFinished = true
            notice = "The router is ready. Add a VPN config next."
        } catch {
            setupLog.append("Stopped: \(error.localizedDescription)")
            notice = error.localizedDescription
        }
        setupRunning = false
        await refresh()
    }

    func clearSetupLog() { setupLog = [] }
}

enum AppResources {
    static var routerDirectory: URL {
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("router", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/router", isDirectory: true)
    }
}

enum SpeedTest {
    /// Measures through the network interface that reaches the router, so a
    /// band test reflects the X28's link even if the Mac's default route is
    /// somewhere else. Falls back to the ordinary route if that fails.
    static func run(bytes: Int = 10_000_000) async -> SpeedResult? {
        if let interface = await routerInterface(),
           let result = await throughInterface(interface, bytes: bytes) {
            return result
        }
        guard let url = URL(string:
            "https://speed.cloudflare.com/__down?bytes=\(bytes)") else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let started = Date()
        do {
            let (data, _) = try await session.data(for: request)
            let seconds = Date().timeIntervalSince(started)
            guard data.count > 100_000, seconds > 0 else { return nil }
            return SpeedResult(bytes: data.count, seconds: seconds)
        } catch {
            return nil
        }
    }

    private static func routerInterface() async -> String? {
        let reply = await Shell.run("/sbin/route",
                                    ["-n", "get", RouterSSH.host], timeout: 5)
        for line in reply.output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("interface:") {
                let name = text.replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    private static func throughInterface(_ interface: String,
                                         bytes: Int) async -> SpeedResult? {
        guard let url = URL(string:
            "https://speed.cloudflare.com/__down?bytes=\(bytes)") else { return nil }
        let reply = await Shell.run("/usr/bin/curl", [
            "-sS", "-L", "--interface", interface, "--max-time", "90",
            "-o", "/dev/null", "-w", "%{size_download} %{time_total}",
            url.absoluteString,
        ], timeout: 100)
        let parts = reply.output.split(separator: " ")
        guard reply.ok, parts.count >= 2,
              let size = Int(parts[parts.count - 2]),
              let seconds = Double(parts[parts.count - 1]),
              size > bytes / 2, seconds > 0 else { return nil }
        return SpeedResult(bytes: size, seconds: seconds)
    }
}
