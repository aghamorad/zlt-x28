import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SidebarSection: String, CaseIterable, Identifiable {
    case home, vpn, radio, setup, carrier, health, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .vpn: return "VPN"
        case .radio: return "Radio & bands"
        case .setup: return "Router setup"
        case .carrier: return "SIM & carrier"
        case .health: return "Health"
        case .about: return "What it does"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .vpn: return "lock.shield"
        case .radio: return "dot.radiowaves.left.and.right"
        case .setup: return "gearshape"
        case .carrier: return "antenna.radiowaves.left.and.right"
        case .health: return "stethoscope"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SidebarSection? = .home

    var body: some View {
        NavigationSplitView {
            // Plain buttons, not a List: a sidebar List treats its section header
            // as a collapsible outline row, so an arrow key can fold the whole
            // sidebar away and row clicks can miss the selection.
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZLT X28")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        ForEach(SidebarSection.allCases) { item in
                            SidebarRow(item: item, selected: selection == item) {
                                selection = item
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Made by Morad")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await model.checkForUpdate() }
                        } label: {
                            Text("v\(model.appVersion)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Check GitHub for a newer version")
                    }
                    updateLine
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 280)
        } detail: {
            page
                .frame(minWidth: 600, minHeight: 480)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if let busy = model.busy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Read the router again")
                .disabled(model.setupRunning)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice, !notice.isEmpty {
                NoticeToast(text: notice) { model.notice = nil }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.notice)
    }

    private struct SidebarRow: View {
        let item: SidebarSection
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(item.title, systemImage: item.icon)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var page: some View {
        switch selection ?? .home {
        case .home: HomeView(section: $selection)
        case .vpn: VPNView()
        case .radio: RadioView()
        case .setup: SetupView(section: $selection)
        case .carrier: CarrierView()
        case .health: HealthView()
        case .about: ScopeView()
        }
    }

    /// One short line, only when there is something to say. Silence is the
    /// right answer for "I have not checked", not a permanent "up to date".
    @ViewBuilder private var updateLine: some View {
        switch model.update {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Checking GitHub…").font(.caption2).foregroundStyle(.secondary)
            }
        case .upToDate(let note):
            Text(note)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .available(let label, let page):
            Button {
                NSWorkspace.shared.open(page)
            } label: {
                Label(label, systemImage: "arrow.down.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Opens GitHub in your browser")
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var section: SidebarSection?

    var body: some View {
        PageScroll {
            PageHeader(title: "ZLT X28",
                       subtitle: "Your home internet, with one switch that matters.")

            hero

            if model.reach == .unreachable {
                InfoBox(title: "This Mac cannot see the router",
                        text: "The app talks to the router at 192.168.70.1. Join the X28's "
                            + "Wi-Fi (or plug into one of its LAN ports), then press the "
                            + "refresh button. If you are already on its Wi-Fi, the router "
                            + "may still be starting — give it a minute.",
                        icon: "wifi.exclamationmark")
            }

            if !model.provisioned && model.reach == .reachable {
                setupBanner
            }

            HStack(alignment: .top, spacing: 16) {
                routerCard
                simCard
            }

            InfoBox(title: "What the switch actually does",
                    text: "On: everything on this Wi-Fi leaves through your VPN server "
                        + "first, so websites see the server's address instead of your "
                        + "SIM's. Off: traffic goes straight out over the mobile network, "
                        + "for every device at once. The switch changes the route only — "
                        + "it never touches your SIM, your plan, or your Wi-Fi password. "
                        + "The full list of what this app can and cannot do is under "
                        + "\"What it does\" in the sidebar.")
        }
    }

    private var hero: some View {
        let text = heroText()
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.title)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(text.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: toggle)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!model.provisioned || model.reach != .reachable
                              || model.busy != nil || model.setupRunning)
                    .help(model.provisioned ? "Turn the VPN on or off"
                                            : "Set up the router first")
            }

            Divider()

            HStack(spacing: 26) {
                miniStat(label: "Router",
                         value: model.reachWord,
                         ok: model.reach == .reachable)
                miniStat(label: model.engine == .amnezia ? "Config" : "Link",
                         value: model.activeLabel,
                         ok: model.engine == .amnezia ? !model.configs.isEmpty : !model.links.isEmpty)
                miniStat(label: "Last check",
                         value: model.lastRefresh.map(Self.timeText) ?? "—",
                         ok: model.lastRefresh != nil)
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.07)))
    }

    private func heroText() -> (title: String, detail: String) {
        if model.reach == .checking {
            return ("Looking for the router",
                    "Asking 192.168.70.1 for an answer. Nothing is wrong yet — the app "
                    + "has simply not heard back.")
        }
        if model.reach == .unreachable {
            return ("Can't see the router",
                    "Connect this Mac to the X28's Wi-Fi, then press refresh.")
        }
        if !model.provisioned {
            return ("Not set up yet",
                    "The switch needs one short setup step before it can work. "
                    + "It takes about a minute.")
        }
        if model.vpnOn {
            return ("VPN is on",
                    "Every device on this Wi-Fi is going out through "
                    + "\(model.activeLabel). Exit address \(model.activeExitIP).")
        }
        return ("VPN is off",
                "Traffic goes straight out through \(model.carrier.shortOperator). "
                + "Flip the switch to route it through the VPN.")
    }

    private var toggle: Binding<Bool> {
        Binding(
            get: { model.vpnOn },
            set: { value in
                Task {
                    if value { await model.turnOn() } else { await model.turnOff() }
                }
            })
    }

    private func miniStat(label: String, value: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                StatusDot(ok: ok)
                Text(value).font(.callout.weight(.medium)).lineLimit(1)
            }
        }
    }

    private var setupBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text("One-time setup").font(.headline)
                Text("This app has not prepared the router yet. Setup installs the VPN "
                    + "engine and is safe to repeat. It does not flash firmware or "
                    + "change your internet settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open setup") { section = .setup }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.accentColor.opacity(0.08)))
    }

    private var routerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Router").font(.headline)
                InfoRow(label: "Name", value: model.carrier.model)
                InfoRow(label: "Firmware", value: model.carrier.firmware)
                InfoRow(label: "Up time", value: model.carrier.uptime)
                InfoRow(label: "Temperature", value: model.carrier.temperature)
            }
        }
    }

    private var simCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("SIM").font(.headline)
                InfoRow(label: "Operator", value: model.carrier.shortOperator)
                HStack {
                    Text("Signal").foregroundStyle(.secondary)
                    Spacer()
                    SignalBars(level: model.carrier.signalLevel)
                }
                .font(.callout)
                InfoRow(label: "Network", value: model.carrier.networkType)
                InfoRow(label: "Internet address", value: model.carrier.wanIP)
            }
        }
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - VPN

struct VPNView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingRemoval: ConfigEntry?
    @State private var pendingLinkRemoval: LinkEntry?
    @State private var confirmRestart = false
    @State private var pasted = ""

    var body: some View {
        PageScroll {
            PageHeader(title: "VPN",
                       subtitle: "Pick how the router connects, then switch it on.")

            ScopeNote("This page only manages the tunnel. It does not change the SIM, "
                      + "the APN, the Wi-Fi, or the firmware. Switching config while the "
                      + "tunnel is on restarts it, and devices drop for a few seconds.")

            engineCard
            tunnelCard

            switch model.engine {
            case .amnezia:
                configsCard

                InfoBox(title: "What is a config?",
                        text: "A small text file from whoever runs your VPN — your own "
                            + "AmneziaWG server, or a provider. It contains the server "
                            + "address and the keys that let the router connect. The router "
                            + "does the encrypting, so every phone, TV and laptop on the "
                            + "Wi-Fi is covered, not just this Mac.")

                InfoBox(title: "Where do I get one?",
                        text: "This app does not come with a server and does not connect you "
                            + "to anyone's. A config is the file that ends in .conf. You can "
                            + "get one from a friend who shares their AmneziaWG server, from a "
                            + "VPN provider that supports AmneziaWG, or from a server you run "
                            + "yourself. Importing it here only copies the file to the router "
                            + "— your existing configs stay where they are, and nothing starts "
                            + "until you flip the switch.",
                        icon: "questionmark.circle")

            case .links:
                linksCard

                InfoBox(title: "What is a link?",
                        text: "A single line of text that starts with vless://, vmess://, "
                            + "trojan://, ss:// or hysteria2://. It carries the server "
                            + "address, the port and the password, all in one. Links are "
                            + "what V2Ray, Shadowrocket and most providers hand out — you "
                            + "can copy them from a subscription or a chat message and paste "
                            + "them here. The router turns each one into its own tunnel and "
                            + "sends the whole Wi-Fi through whichever one you pick.")

                InfoBox(title: "Why is there a Test button?",
                        text: "A link can look fine and still be dead — the server moved, "
                            + "the traffic got blocked, or the subscription ran out. Test "
                            + "opens the link on the router and asks a website for a tiny "
                            + "file through it. If it gets an answer you see the delay and "
                            + "the speed; if it does not, the link is marked dead. Testing "
                            + "never changes which link the Wi-Fi is using.",
                        icon: "questionmark.circle")
            }
        }
        .alert("Set this link aside?",
               isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } })) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button("Set aside", role: .destructive) {
                let name = pendingRemoval?.name
                pendingRemoval = nil
                if let name { Task { await model.removeConfig(name) } }
            }
        } message: {
            Text("\(pendingRemoval?.name ?? "This config") is renamed on the router, "
                 + "not deleted, so you can recover it from the router later.")
        }
        .alert("Set this link aside?",
               isPresented: Binding(
                    get: { pendingLinkRemoval != nil },
                    set: { if !$0 { pendingLinkRemoval = nil } })) {
            Button("Cancel", role: .cancel) { pendingLinkRemoval = nil }
            Button("Set aside", role: .destructive) {
                let name = pendingLinkRemoval?.name
                pendingLinkRemoval = nil
                if let name { Task { await model.removeLink(name) } }
            }
        } message: {
            Text("\(pendingLinkRemoval?.label ?? "This link") is moved to a trash "
                 + "folder on the router, never deleted, so you can bring it back.")
        }
        .alert("Restart the tunnel?", isPresented: $confirmRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") { Task { await model.restartTunnel() } }
        } message: {
            Text("Every device on the Wi-Fi will lose its connection for a few seconds "
                 + "while the tunnel comes back. Nothing on the router is changed.")
        }
    }

    // MARK: Engine

    private var engineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("How the router connects").font(.headline)
                Picker("", selection: $model.engine) {
                    ForEach(VPNEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.busy != nil || model.setupRunning)

                Text(model.engine.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.provisioned {
                    Text("The engine installs with setup. Open Router setup to do that once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Tunnel

    private var tunnelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            StatusDot(ok: model.vpnOn)
                            Text(model.vpnOn ? "Tunnel is on" : "Tunnel is off")
                                .font(.title3.weight(.semibold))
                        }
                        Text(tunnelDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.vpnOn },
                        set: { value in
                            Task {
                                if value { await model.turnOn() }
                                else { await model.turnOff() }
                            }
                        }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!model.provisioned || model.busy != nil
                              || model.setupRunning)
                }

                if model.provisioned {
                    Divider()
                    HStack(spacing: 24) {
                        if model.engine == .amnezia {
                            smallStat("Handshake", model.status.handshakeText)
                            smallStat("Traffic", model.status.trafficText)
                        } else {
                            smallStat("Active link", model.activeLinkLabel)
                            smallStat("Engine", !model.sb.running ? "Stopped"
                                      : model.sb.routed ? "Running"
                                      : "Up, not carrying traffic")
                        }
                        smallStat("Exit IP", model.engine == .amnezia
                                  ? model.status.exitIP : model.sb.exitIP)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        Button("Restart") {
                            confirmRestart = true
                        }
                        .disabled(model.busy != nil)
                        Button("Test the tunnel") {
                            Task { await model.testTunnel() }
                        }
                        .disabled(model.busy != nil || !model.vpnOn)
                        Spacer()
                        if model.engine == .amnezia, model.status.bootEnabled {
                            Chip(text: "Starts after a power cut", color: .green)
                        }
                        if model.engine == .links, model.sb.bootEnabled {
                            Chip(text: "Starts after a power cut", color: .green)
                        }
                    }
                } else {
                    Text("The VPN engine is not installed yet. Open Router setup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tunnelDetail: String {
        if model.engine == .amnezia {
            return model.vpnOn
                ? "Using \(model.currentConfig). Traffic leaves through "
                  + "\(model.status.exitIP)."
                : "Traffic is going straight out through the mobile network."
        }
        if model.vpnOn {
            return "Using \(model.activeLinkLabel). Traffic leaves through \(model.sb.exitIP)."
        }
        if model.sb.running {
            return "The engine is up but nothing is being sent through it, so your "
                + "Wi-Fi is still on the mobile network. Press Restart to give it "
                + "another go."
        }
        if model.links.isEmpty {
            return "Add a link below, test it, then switch this on."
        }
        return "Traffic is going straight out through the mobile network."
    }

    private var configsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Configs on the router").font(.headline)
                    Spacer()
                    Button {
                        openPanel()
                    } label: {
                        Label("Add config", systemImage: "plus")
                    }
                    .disabled(!model.provisioned || model.busy != nil)
                }

                if model.configs.isEmpty {
                    Text(model.provisioned
                         ? "No configs yet. Add the .conf file from your VPN server."
                         : "Setup the router first, then add a config.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(model.configs.enumerated()), id: \.element.id) {
                        index, entry in
                        if index > 0 { Divider() }
                        configRow(entry)
                    }
                }
            }
        }
    }

    private func configRow(_ entry: ConfigEntry) -> some View {
        let active = entry.name == model.currentConfig
        return HStack(spacing: 12) {
            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.medium))
                Text(entry.endpoint.isEmpty ? "No server address in this file"
                                            : entry.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if active { Chip(text: "In use", color: .green) }
            Button("Use") {
                Task { await model.useConfig(entry.name) }
            }
            .disabled(active || model.busy != nil)
            Button {
                pendingRemoval = entry
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Set this config aside without deleting it")
            .disabled(model.busy != nil)
        }
        .padding(.vertical, 4)
    }

    // MARK: Links

    private var linksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Links").font(.headline)
                    if model.testingAllLinks {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button {
                        Task { await model.testAllLinks() }
                    } label: {
                        Label("Test all", systemImage: "waveform.path.ecg")
                    }
                    .disabled(model.links.isEmpty || model.busy != nil)
                }

                TextField("Paste a link here — vless://, vmess://, trojan://, ss://, hysteria2://",
                          text: $pasted, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .lineLimit(3...6)

                HStack {
                    Text("One link per line. Paste as many as you like — the router "
                         + "keeps each one as its own tunnel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        let text = pasted
                        pasted = ""
                        Task { await model.importLinks(text) }
                    } label: {
                        Label("Add links", systemImage: "plus")
                    }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || model.busy != nil)
                }

                if !model.sb.installed {
                    Text("The link engine installs with setup. Open Router setup and run "
                         + "it once, then paste links here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if model.links.isEmpty {
                    Text("No links yet. Paste one above and press Add links.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    Divider()
                    ForEach(Array(model.links.enumerated()), id: \.element.id) {
                        index, entry in
                        if index > 0 { Divider() }
                        linkRow(entry)
                    }
                }
            }
        }
    }

    private func linkRow(_ entry: LinkEntry) -> some View {
        let active = entry.name == model.sb.active
        let testing = entry.status == .testing
        return HStack(spacing: 12) {
            Image(systemName: statusIcon(entry.status))
                .foregroundStyle(statusColor(entry.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.label)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Chip(text: entry.kind)
                    if active { Chip(text: "In use", color: .green) }
                }
                Text(entry.status.summary)
                    .font(.caption)
                    .foregroundStyle(statusColor(entry.status))
                Text(entry.server)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(testing ? "Testing…" : "Test") {
                Task { await model.testLink(entry.name) }
            }
            .disabled(model.busy != nil || testing)

            Button("Use") {
                Task { await model.useLink(entry.name) }
            }
            .disabled(active || model.busy != nil)

            Button {
                pendingLinkRemoval = entry
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Move this link to the router's trash folder")
            .disabled(model.busy != nil)
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(_ status: LinkStatus) -> String {
        switch status {
        case .untested: return "circle.dashed"
        case .testing: return "hourglass"
        case .alive: return "checkmark.circle.fill"
        case .dead: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: LinkStatus) -> Color {
        switch status {
        case .untested, .testing: return .secondary
        case .alive: return .green
        case .dead: return .red
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the .conf file from your VPN provider"
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importConfig(from: url) }
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var section: SidebarSection?
    @State private var confirmInstall = false

    var body: some View {
        PageScroll {
            PageHeader(title: "Router setup",
                       subtitle: "One time, about a minute. Safe to repeat.")

            ScopeNote("Setup adds three things to the router: the VPN engine, its "
                      + "start-up service, and an SSH key for this app. It edits nothing "
                      + "else, never flashes the firmware, and a factory reset removes it.")

            if model.provisioned {
                alreadyCard
            } else {
                InfoBox(title: "Before you start",
                        text: "This does not flash the router and does not reboot it. "
                            + "Your internet keeps working the whole time. If anything "
                            + "goes wrong, you can simply run setup again.")
            }

            StepCard(number: 1,
                     title: "Be on the router's Wi-Fi",
                     detail: "The app talks to the router over your own home network; "
                           + "nothing leaves the house during setup. The router lives at "
                           + "192.168.70.1. Join the X28's Wi-Fi, or plug this Mac into "
                           + "one of its LAN ports.",
                     done: model.reach == .reachable) {
                HStack(spacing: 10) {
                    if model.reach == .reachable {
                        Text("The router answered.").font(.callout).foregroundStyle(.green)
                    } else {
                        Text("Waiting for the router.").font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("Check again") { Task { await model.refresh() } }
                        .disabled(model.busy != nil)
                }
            }

            StepCard(number: 2,
                     title: "Type the router's admin password",
                     detail: "Every X28 has a settings page protected by a password. "
                           + "The stock one is usually “admin” — it is printed on the "
                           + "sticker under the router. The app uses it once, to install "
                           + "its own key; after that it never needs the password again. "
                           + "It is stored only on this Mac.",
                     done: model.provisioned) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        SecureField("Admin password", text: $model.password)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Button("Test password") {
                            Task { await model.testLogin() }
                        }
                        .disabled(model.busy != nil || model.reach != .reachable)
                    }
                    if model.reach != .reachable {
                        Text("Connect to the router first.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            StepCard(number: 3,
                     title: "Install the VPN engine",
                     detail: "This copies a small VPN program onto the router and gives "
                           + "it a start-up service, so it comes back by itself after a "
                           + "power cut. To do that, the app briefly opens the router's "
                           + "own setup door, installs its key, and closes the door "
                           + "again — exactly as it was. It does not touch the SIM, the "
                           + "APN, the Wi-Fi settings, or the firmware.",
                     done: model.provisioned,
                     caution: "Keep the router powered during this step. If it is "
                            + "interrupted, run setup again — nothing is left half "
                            + "finished, and the next run replaces whatever is there.") {
                HStack(spacing: 10) {
                    if model.provisioned {
                        Text("Installed.").font(.callout).foregroundStyle(.green)
                        Button("Run setup again") { confirmInstall = true }
                            .buttonStyle(.bordered)
                            .disabled(model.setupRunning || model.reach != .reachable
                                      || model.password.isEmpty)
                        if model.setupRunning {
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Button("Install the VPN engine") { confirmInstall = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.setupRunning || model.reach != .reachable
                                      || model.password.isEmpty)
                        if model.setupRunning {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                logView
            }

            StepCard(number: 4,
                     title: "Add a VPN config",
                     detail: "The engine is installed but idle until it has a server to "
                           + "talk to. A config file (ends in .conf) carries the server "
                           + "address and keys. Add it on the VPN page.",
                     done: !model.configs.isEmpty) {
                Button("Go to VPN configs") { section = .vpn }
                    .disabled(!model.provisioned)
            }

            StepCard(number: 5,
                     title: "Turn it on",
                     detail: "Flip the switch on the Home page, then look at Health. "
                           + "The handshake should say a few seconds ago and an exit "
                           + "address should appear.",
                     done: model.vpnOn) {
                Button("Go to the switch") { section = .home }
                    .disabled(!model.provisioned)
            }
        }
        .alert("Install the VPN engine on this router?",
               isPresented: $confirmInstall) {
            Button("Cancel", role: .cancel) { }
            Button("Install") { Task { await model.runSetup() } }
        } message: {
            Text("The router is at 192.168.70.1. Files are copied over your local "
                 + "network. Nothing is flashed and the router is not rebooted.")
        }
    }

    private var alreadyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("This router is already set up").font(.headline)
                Text("The VPN engine is installed and starts after a power cut. "
                    + "You can run the steps below again at any time — they replace "
                    + "the engine cleanly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.green.opacity(0.08)))
    }

    @ViewBuilder private var logView: some View {
        if model.setupRunning || !model.setupLog.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.setupRunning ? "Working…" : "Setup log")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if !model.setupRunning {
                        Button("Clear") { model.clearSetupLog() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(model.setupLog.enumerated()),
                                    id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 150)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor)))
                    .onChange(of: model.setupLog.count) { _ in
                        guard let last = model.setupLog.indices.last else { return }
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Carrier

struct CarrierView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmCompare = false

    var body: some View {
        PageScroll {
            PageHeader(title: "SIM & carrier",
                       subtitle: "What the router reads from the SIM — and the little "
                            + "that is worth changing.")

            ScopeNote("This page reads the SIM. The only change Optimize can make is a "
                      + "band preference on the router, and it puts that back if the test "
                      + "does not show an improvement.")

            carrierCard
            speedCard
            honestCard
            firmwareCard
        }
        .alert("Compare VPN on and off?",
               isPresented: $confirmCompare) {
            Button("Cancel", role: .cancel) { }
            Button("Start the comparison") { Task { await model.compareSpeed() } }
        } message: {
            Text("The VPN will switch off for about 20 seconds and then be put back "
                 + "the way it was. Devices on the Wi-Fi may hiccup while this happens.")
        }
    }

    private var carrierCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(model.carrier.shortOperator)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Chip(text: model.carrier.networkType,
                         color: model.carrier.networkType.contains("5G") ? .green : .orange)
                    Spacer()
                    SignalBars(level: model.carrier.signalLevel)
                }

                HStack(spacing: 10) {
                    Chip(text: model.carrier.simReady ? "SIM ready" : "No SIM",
                         color: model.carrier.simReady ? .green : .red)
                    Chip(text: model.carrier.dataOn ? "Mobile data on" : "Data off",
                         color: model.carrier.dataOn ? .green : .orange)
                    Spacer()
                }

                Divider()
                InfoRow(label: "Full operator name", value: model.carrier.operatorName)
                InfoRow(label: "Internet address", value: model.carrier.wanIP)
                InfoRow(label: "DNS from the network", value: model.carrier.dns)

                Text(model.carrier.carrierNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var speedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Measure the line").font(.headline)
                        Text("Downloads 10 MB from Cloudflare and times it. "
                             + "It uses about 10 MB of your data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.measuring { ProgressView().controlSize(.small) }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await model.measureSpeed() }
                    } label: {
                        Label("Measure now", systemImage: "speedometer")
                    }
                    .disabled(model.measuring || model.reach != .reachable)

                    Button {
                        confirmCompare = true
                    } label: {
                        Label("Compare VPN on vs off", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(model.measuring || !model.provisioned
                              || model.configs.isEmpty)
                    Spacer()
                }

                if model.samples.isEmpty && !model.measuring {
                    Text("A VPN adds encryption and a detour, so it is often slower "
                         + "than the raw line. Measure both before deciding whether "
                         + "to keep it on for speed-heavy tasks.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.samples) { sample in
                            speedRow(sample)
                        }
                    }
                }
            }
        }
    }

    private func speedRow(_ sample: SpeedSample) -> some View {
        let best = max(model.samples.map { $0.result.mbps }.max() ?? 1, 0.1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sample.label).font(.callout.weight(.medium))
                Spacer()
                Text(String(format: "%.1f Mbit/s  ·  %.1f MB/s",
                            sample.result.mbps, sample.result.megabytesPerSecond))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: sample.result.mbps, total: best)
                .tint(sample.label.contains("VPN") ? Color.accentColor : Color.green)
        }
    }

    private var honestCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("What this app will not change").font(.headline)
                bullet("APN", "The SIM supplies it. Editing it by hand is the "
                       + "usual way people lose mobile data.")
                bullet("Band lock", "It lives on the Radio & bands page, where the app "
                       + "measures before and after instead of guessing.")
                bullet("Network mode", "5G and 4G are negotiated automatically. "
                       + "Forcing one can strand the router on a dead band.")
                Text("The strongest lever on speed is the VPN path itself. If the "
                     + "direct line is faster, the server or its route is the "
                     + "bottleneck — not the SIM.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bullet(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var firmwareCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("This device").font(.headline)
                InfoRow(label: "Model", value: model.carrier.model)
                InfoRow(label: "Firmware", value: model.carrier.firmware)
                InfoRow(label: "Hardware", value: model.carrier.hardware)
                InfoRow(label: "Router temperature", value: model.carrier.temperature)
                InfoRow(label: "Up time", value: model.carrier.uptime)
            }
        }
    }
}

// MARK: - Health

struct HealthView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmRestart = false

    var body: some View {
        PageScroll {
            PageHeader(title: "Health",
                       subtitle: "Press one button and the app tests the whole path, "
                            + "then shows you a pass or fail for each step.")

            ScopeNote("Health only looks. Every check reads the router and changes "
                      + "nothing. Restart tunnel is the one button here that interrupts "
                      + "anything, and it asks first.")

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Run the checks").font(.headline)
                        Spacer()
                        if let passed = model.checksPassed,
                           let total = model.checksTotal {
                            Chip(text: "\(passed) of \(total) passed",
                                 color: passed == total ? .green : .orange)
                        }
                    }

                    Text("This is the same test a person would do by hand: can this Mac "
                         + "reach the router, is the engine installed, is the tunnel up, "
                         + "is traffic actually leaving through it, and do websites see "
                         + "a different address. It takes about ten seconds.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await model.runChecks() }
                    } label: {
                        Label(model.checking ? "Testing…" : "Run the checks",
                              systemImage: "checkmark.shield")
                            .frame(minWidth: 150)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.checking || model.busy != nil)

                    if model.checking {
                        ProgressView().progressViewStyle(.linear)
                    }

                    if !model.checks.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.checks) { item in
                                checkRow(item)
                            }
                        }
                    }
                }
            }

            Card {
                if model.reach == .reachable {
                    VStack(alignment: .leading, spacing: 0) {
                        row(ok: true,
                            title: "Router",
                            value: "Answering at 192.168.70.1",
                            detail: "This is how the app reaches the router.")
                        divider
                        row(ok: model.provisioned,
                            title: "VPN engine",
                            value: model.provisioned
                                ? (model.status.daemonRunning ? "Running" : "Installed, stopped")
                                : "Not installed",
                            detail: "The program on the router that does the encrypting.")
                        divider
                        row(ok: model.vpnOn,
                            title: "Route",
                            value: model.status.routeThroughTunnel
                                ? "Traffic goes through the tunnel" : "Traffic goes direct",
                            detail: "Only traffic from your Wi-Fi devices is redirected; the "
                                  + "router's own traffic keeps its normal path.")
                        divider
                        row(ok: model.status.handshakeEpoch > 0,
                            title: "Handshake",
                            value: model.status.handshakeText,
                            detail: "A fresh handshake means the server is answering. If it "
                                  + "is hours old, the tunnel is up but the server is not.")
                        divider
                        row(ok: model.status.exitIP != "—",
                            title: "Exit address",
                            value: model.status.exitIP,
                            detail: "The address websites see when the VPN is on. It should "
                                  + "be your server's, not your SIM's.")
                        divider
                        row(ok: model.status.bootEnabled,
                            title: "After a power cut",
                            value: model.status.bootEnabled
                                ? "Starts by itself" : "Will not start by itself",
                            detail: "The start-up service brings the tunnel back without "
                                  + "anyone touching the app.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.reach == .checking
                             ? "Asking the router" : "Nothing has been read")
                            .font(.headline)
                        Text(model.reach == .checking
                             ? "192.168.70.1 has not answered yet. The readings take its "
                               + "place once it does."
                             : "The engine, the route, the handshake, the exit address: all "
                               + "of them live on the router behind 192.168.70.1, and this "
                               + "Mac cannot see it. So the app prints none of them rather "
                               + "than guess. Join the X28's Wi-Fi or plug into a LAN port, "
                               + "then press Check again.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                Button {
                    confirmRestart = true
                } label: {
                    Label("Restart tunnel", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!model.provisioned || model.busy != nil)
                Button {
                    Task { await model.testTunnel() }
                } label: {
                    Label("Test traffic", systemImage: "checkmark.shield")
                }
                .disabled(!model.vpnOn || model.busy != nil)
                Button {
                    copyReport()
                } label: {
                    Label("Copy report", systemImage: "doc.on.doc")
                }
                Spacer()
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Health only looks").font(.headline)
                    Text("Every check here reads the router. None of them changes it, and "
                         + "a check is safe to run with the tunnel on. The one action that "
                         + "interrupts anything is Restart tunnel, which stops and starts "
                         + "the tunnel — devices drop for a few seconds, and the router's "
                         + "settings stay as they are.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Text("The full list — what the app changes, what it never touches, and "
                         + "what it cannot do — is under \"What it does\" in the sidebar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .alert("Restart the tunnel?", isPresented: $confirmRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") { Task { await model.restartTunnel() } }
        } message: {
            Text("Every device on the Wi-Fi will lose its connection for a few seconds "
                 + "while the tunnel comes back. Nothing on the router is changed.")
        }
    }

    private var divider: some View {
        Divider().padding(.vertical, 10)
    }

    private func checkRow(_ item: CheckItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(item.ok ? Color.green : Color.red)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(item.ok ? "Pass" : "Fail")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.ok ? Color.green : Color.red)
        }
    }

    private func row(ok: Bool, title: String, value: String,
                     detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StatusDot(ok: ok).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.callout.weight(.semibold))
                    Spacer()
                    Text(value)
                        .font(.callout)
                        .foregroundStyle(ok ? .primary : .secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyReport() {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let report = """
        ZLT X28 report — \(stamp)
        Router: \(model.reachWord)
        Model: \(model.carrier.model), firmware \(model.carrier.firmware)
        SIM: \(model.carrier.shortOperator), \(model.carrier.networkType), signal \(model.carrier.signalLevel)/5
        WAN IP: \(model.carrier.wanIP)
        Provisioned: \(model.provisioned ? "yes" : "no")
        Tunnel: \(model.vpnOn ? "on" : "off"), config \(model.currentConfig)
        Daemon: \(model.status.daemonRunning ? "running" : "stopped")
        Route through tunnel: \(model.status.routeThroughTunnel ? "yes" : "no")
        Boot service: \(model.status.bootEnabled ? "enabled" : "disabled")
        Handshake: \(model.status.handshakeText)
        Traffic: \(model.status.trafficText)
        Exit IP: \(model.status.exitIP)
        Temperature: \(model.carrier.temperature)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        model.notice = "Report copied to the clipboard."
    }
}

// MARK: - Radio

struct RadioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmTune = false
    @State private var confirmOptimize = false
    @State private var confirmPin = false

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Radio & bands",
                subtitle: "The router's mobile link. See which cell it is using, "
                        + "and test whether pinning it to one band is faster.")
            ScopeNote("Only the router's band preference changes here. Wi-Fi stays up "
                      + "while it tests, the SIM is untouched, and Put back undoes a pin.")
            cellsCard
            lockCard
            tuneCard
            honestyCard
        }
        .task { await model.loadBands() }
    }

    private var cellsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What the router can hear").font(.headline)
                        Text("A scan asks the radio which cells it can see. It briefly "
                             + "drops the mobile link; Wi-Fi stays up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.scanningRadio { ProgressView().controlSize(.small) }
                    Button {
                        Task { await model.scanRadio() }
                    } label: {
                        Label("Scan now", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(model.scanningRadio || model.tuningRadio
                              || model.reach != .reachable)
                }

                if model.cells.isEmpty {
                    Text(model.scanningRadio
                         ? "Scanning… this takes about ten seconds."
                         : "No scan yet. Press Scan now to see the tower the router is on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.cells) { cell in cellRow(cell) }
                    }
                    if let date = model.scannedAt {
                        Text("Scanned at \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func cellRow(_ cell: RadioCell) -> some View {
        HStack(spacing: 12) {
            Chip(text: cell.generation,
                 color: cell.generation == "5G" ? .blue : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cell.bandLabel) · \(cell.frequency)")
                    .font(.callout.weight(.medium))
                Text("Cell \(cell.pci) · channel \(cell.earfcn)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(cell.rsrp) dBm").font(.callout.monospacedDigit())
                Text(cell.signalWord).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var lockCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Band lock").font(.headline)
                    Spacer()
                    Chip(text: model.bandSettings.isLocked ? "Pinned" : "Automatic",
                         color: model.bandSettings.isLocked ? .orange : .green)
                }
                Text(model.bandSettings.isLocked
                     ? "The router may only use \(model.bandSettings.summary). If that "
                       + "band gets busy, or you move away from the tower, speed can "
                       + "drop — or the link can go."
                     : "The router is free to use every band the SIM supports. This is "
                       + "the normal, safest setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task { await model.restoreAutomaticBands() }
                    } label: {
                        Label("Use every band", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.bandSettings.isLocked || model.radioBusy != nil
                              || model.tuningRadio)

                    Button { confirmPin = true } label: {
                        Label("Pin to current bands", systemImage: "pin")
                    }
                    .disabled(model.cells.isEmpty || model.bandSettings.isLocked
                              || model.radioBusy != nil || model.tuningRadio)

                    Spacer()
                    if let busy = model.radioBusy {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Pin the router?", isPresented: $confirmPin) {
            Button("Cancel", role: .cancel) {}
            Button("Pin it") { Task { await model.pinToCurrentBands() } }
        } message: {
            Text("The router will only use the bands it is on right now. It reconnects "
                 + "by itself and your Wi-Fi stays up. If that band gets busy or you "
                 + "move, you can lose speed; Use every band undoes it.")
        }
    }

    private var tuneCard: some View {
        let profile = CarrierProfile.of(model.carrier)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Optimize for \(profile.name)").font(.headline)
                        Text("Measures the router's own choice against the bands "
                             + "\(profile.name) actually uses for speed, then keeps "
                             + "the faster one. Takes a few minutes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.tuningRadio { ProgressView().controlSize(.small) }
                }

                HStack(spacing: 10) {
                    Button {
                        confirmOptimize = true
                    } label: {
                        Label("Optimize", systemImage: "wand.and.stars")
                    }
                    .disabled(model.tuningRadio || model.scanningRadio
                              || model.radioBusy != nil || model.reach != .reachable)

                    Button("Simple A/B test") { confirmTune = true }
                        .disabled(model.tuningRadio || model.scanningRadio
                                  || model.reach != .reachable)
                    Spacer()
                }

                if !model.tuneSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.tuneSamples) { sample in tuneRow(sample) }
                    }
                }

                if !model.tuneLog.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.tuneLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.03)))
                }

                if let verdict = model.tuneVerdict {
                    InfoBox(title: "Result", text: verdict,
                            icon: "checkmark.seal")
                }

                if model.tuneLog.isEmpty {
                    Text(profile.fastLane)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(profile.warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Only bands the router can actually hear are tried, and if "
                         + "nothing beats automatic the router is put back on every "
                         + "band. Speed is measured with the VPN off, then the VPN "
                         + "is switched back on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .alert("Optimize the radio?", isPresented: $confirmOptimize) {
            Button("Cancel", role: .cancel) {}
            Button("Optimize") { Task { await model.optimizeCarrier() } }
        } message: {
            Text("The app measures the line with every band allowed, then tries up "
                 + "to three pinned combinations and keeps the fastest. Each change "
                 + "reconnects the mobile link for up to a minute; Wi-Fi stays up. "
                 + "The VPN is paused while measuring and comes back on at the end. "
                 + "About 32 MB of data is used.")
        }
        .alert("Test the bands?", isPresented: $confirmTune) {
            Button("Cancel", role: .cancel) {}
            Button("Run the test") { Task { await model.tuneRadio() } }
        } message: {
            Text("The router reconnects when it changes bands, so the mobile link "
                 + "drops for up to a minute. About 16 MB of data is used. Wi-Fi stays "
                 + "up and the VPN reconnects by itself. If pinning is not faster, the "
                 + "app puts it back on automatic.")
        }
    }

    private func tuneRow(_ sample: SpeedSample) -> some View {
        HStack {
            Text(sample.label).font(.callout.weight(.medium))
            Spacer()
            Text(String(format: "%.1f Mbit/s  ·  %.1f MB/s",
                        sample.result.mbps, sample.result.megabytesPerSecond))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var honestyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("What a band lock can and cannot do", systemImage: "info.circle")
                    .font(.headline)
                point("It cannot create signal",
                      "If only one cell is visible — the usual case here — pinning "
                      + "cannot find a second tower. It can only stop the router "
                      + "moving to a weaker band.")
                point("Stronger is not always faster",
                      "A distant band can be less crowded. That is why the app "
                      + "measures instead of trusting the signal bars.")
                point("It does not lift the VPN ceiling",
                      "Slow international routes are a network problem, not a radio "
                      + "one. Band tuning will not make that tunnel faster.")
                point("Wi-Fi is untouched",
                      "Phones and laptops keep their Wi-Fi connection. Only the "
                      + "router-to-tower link changes.")
            }
        }
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - What it does

/// The canonical answer to "what am I installing?". Every other page states
/// its own boundary in a line; this one holds the whole list, so a person can
/// read the limits before they trust the thing with their only internet line.
struct ScopeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PageScroll {
            PageHeader(title: "What it does",
                       subtitle: "The whole job in one place — and the lines it "
                            + "does not cross.")

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The short version").font(.headline)
                    Text("The VPN runs on the router, not on this Mac. The app is the "
                         + "remote control: it sets the router up once, keeps your "
                         + "connections on it, switches between them, tunes the radio, "
                         + "and tests the whole path when something stops working. "
                         + "Close the app and the tunnel keeps running — the Mac is "
                         + "never part of the path.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What it does").font(.headline)
                    point("Sets the router up once. It copies the VPN engine onto it and "
                          + "adds a start-up service, so the tunnel comes back by itself "
                          + "after a power cut. Running setup again repairs it; it does "
                          + "not duplicate anything.")
                    Divider()
                    point("Runs one tunnel at a time. AmneziaWG (a .conf file) or "
                          + "sing-box (share links) — one engine, never both. The app "
                          + "always says which one is carrying traffic and never swaps "
                          + "behind your back.")
                    Divider()
                    point("Keeps your connections and tells the dead from the alive. "
                          + "Configs and links live on the router. A link test downloads "
                          + "a real file through it, so \"works\" means traffic moved, not "
                          + "that a program started.")
                    Divider()
                    point("Measures the radio. It scans the cells the router can hear, "
                          + "tests whether pinning a band is actually faster, keeps the "
                          + "winner, and puts back what it changed if it cannot show an "
                          + "improvement.")
                    Divider()
                    point("Explains the failure. Health tests the SIM's own line first — "
                          + "with the VPN out of the picture — then the router, the engine, "
                          + "the route, the handshake and the internet, and names the first "
                          + "thing that failed.")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What it never touches").font(.headline)
                    ScopeRow(label: "SIM and plan",
                             value: "Read only — it can show what the SIM reports, but it "
                                  + "cannot activate the SIM, add a package, or change the plan")
                    Divider()
                    ScopeRow(label: "APN and network mode", value: "Never changed")
                    Divider()
                    ScopeRow(label: "Firmware",
                             value: "Never flashed or replaced — setup works with the stock "
                                  + "firmware as it is")
                    Divider()
                    ScopeRow(label: "Wi-Fi name and password", value: "Never changed")
                    Divider()
                    ScopeRow(label: "Router web password",
                             value: "Never changed — setup uses it once to log in")
                    Divider()
                    ScopeRow(label: "This Mac's internet",
                            value: "Never routed through the router and never modified. "
                                 + "The app only uses the local network to reach "
                                 + "192.168.70.1")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What it needs").font(.headline)
                    ScopeRow(label: "Router",
                             value: "A ZLT X28. Firmware 1.5.x is what this was built and "
                                  + "tested on; another version is reported, not guessed at")
                    Divider()
                    ScopeRow(label: "This Mac",
                             value: "macOS 13 or newer, Apple Silicon or Intel. On the "
                                  + "router's Wi-Fi or a LAN cable for setup and readings")
                    Divider()
                    ScopeRow(label: "Password",
                             value: "The router's admin password — its web page, often "
                                  + "\"admin\". This is not the Wi-Fi password")
                    Divider()
                    ScopeRow(label: "A VPN of your own",
                             value: "A .conf from your server or a provider, or share links. "
                                  + "The app does not come with a server and does not "
                                  + "connect you to anyone's")
                    Divider()
                    ScopeRow(label: "First launch",
                            value: "The app is signed ad-hoc, not notarised, so macOS "
                                 + "wants right-click → Open once. After that it opens "
                                 + "normally")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What it cannot do").font(.headline)
                    point("Create signal. Where the SIM has no usable line there is "
                          + "nothing for the tunnel to carry, and no setting here "
                          + "changes that. Health will name it.")
                    Divider()
                    point("Make a slow line fast. Band locking picks the best of what the "
                          + "carrier is already giving you. It does not add capacity.")
                    Divider()
                    point("Lift a carrier wall. If the line only reaches the carrier's own "
                          + "sites — a walled garden — the problem is the SIM's data "
                          + "package or its identity check, not the router and not the "
                          + "VPN. Switching the tunnel on will not change it.")
                    Divider()
                    point("Import OpenVPN files. A config must be a WireGuard or "
                          + "AmneziaWG .conf. OpenVPN profiles are refused.")
                    Divider()
                    point("Run both engines at once. It is AmneziaWG or links, one at a "
                          + "time, and the app says which.")
                    Divider()
                    point("Survive a factory reset. A reset erases the engine, the "
                          + "start-up service and every config. Run setup again.")
                    Divider()
                    point("Reach the router from outside the house. Everything goes over "
                          + "the local network at 192.168.70.1. There is no remote "
                          + "control.")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What it writes, and where").font(.headline)
                    ScopeRow(label: "On the router",
                             value: "The VPN engine, its start-up service, an SSH key for "
                                  + "this app, configs in /etc/amneziawg/, links under "
                                  + "/data/zltx28/")
                    Divider()
                    ScopeRow(label: "On this Mac",
                             value: "An SSH key in Application Support, and the remembered "
                                  + "list of what is installed. Nothing else")
                    Divider()
                    ScopeRow(label: "Anywhere else", value: "Nothing")
                    Divider()
                    Text("ZLT X28 \(model.appVersion) · Made by Morad")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            InfoBox(title: "Removing is setting aside",
                    text: "Taking a config or a link off the list renames it on the router "
                        + "rather than deleting it, so it can be brought back. Nothing in "
                        + "this app removes a file outright.",
                    icon: "arrow.uturn.backward.circle")
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared pieces

struct PageScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 26)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct InfoBox: View {
    let title: String
    let text: String
    var icon: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.07)))
    }
}

/// One muted line at the top of a page: what this page can change, and what it
/// leaves alone. Quieter than an InfoBox on purpose — it is a boundary marker,
/// not a lesson.
struct ScopeNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }
}

/// Label above value, for long sentences that would choke a trailing label.
struct ScopeRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.callout.weight(.medium))
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

struct StatusDot: View {
    let ok: Bool

    var body: some View {
        Circle()
            .fill(ok ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 8, height: 8)
    }
}

struct Chip: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct SignalBars: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...5, id: \.self) { step in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(step <= level ? Color.accentColor
                                        : Color.secondary.opacity(0.25))
                    .frame(width: 5, height: CGFloat(5 + step * 3))
            }
        }
        .accessibilityLabel("Signal \(level) of 5")
    }
}

struct NoticeToast: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    var done: Bool = false
    var caution: String?
    private let content: Content

    init(number: Int, title: String, detail: String, done: Bool = false,
         caution: String? = nil, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.detail = detail
        self.done = done
        self.caution = caution
        self.content = content()
    }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(done ? Color.green.opacity(0.18)
                                   : Color.secondary.opacity(0.12))
                        .frame(width: 30, height: 30)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caution {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            Text(caution)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.09)))
                    }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
