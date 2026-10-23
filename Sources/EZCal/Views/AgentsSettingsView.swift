import SwiftUI
import AppKit

/// Settings → Agents: switch for the local MCP server (issue #69), its address, token and copy-paste setup.
struct AgentsSettingsView: View {
    @AppStorage("mcpEnabled") private var enabled = false
    @AppStorage("mcpReadOnly") private var readOnly = false
    @AppStorage("mcpPort") private var port = MCPServer.defaultPort
    @State private var server = MCPServer.shared
    @State private var token = MCPServer.token()
    @State private var showToken = false
    @State private var copied: String?

    private var url: String { "http://127.0.0.1:\(MCPServer.port)/mcp" }
    private var claudeCodeCommand: String {
        "claude mcp add --transport http ezcal \(url) --header \"Authorization: Bearer \(token)\""
    }

    private var claudeDesktopConfig: String {
        MCPStdioBridge.claudeDesktopConfig(executable: Bundle.main.executablePath ?? "/Applications/EZCal.app/Contents/MacOS/EZCal")
    }

    var body: some View {
        Form {
            Section("Agent access (MCP)") {
                Toggle("Let AI agents use my calendar", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in server.sync() }
                Toggle("Read-only (agents can look, not change anything)", isOn: $readOnly)
                    .disabled(!enabled)
                LabeledContent("Status") { Text(statusText).foregroundStyle(statusColor) }
                Text("Starts a server on this Mac only (127.0.0.1) that agents such as Claude Code and Claude Desktop can use to list, create, change and delete events on your Google and Apple calendars. EZCal must be running. Every request needs the access token below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if enabled {
                Section("Connect") {
                    LabeledContent("Address") {
                        HStack {
                            Text(url).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            copyButton("Copy", url)
                        }
                    }
                    LabeledContent("Port") {
                        TextField("", value: $port, format: .number.grouping(.never))
                            .frame(width: 70).multilineTextAlignment(.trailing)
                            .onSubmit { server.restart() }
                    }
                    LabeledContent("Access token") {
                        HStack {
                            Text(showToken ? token : String(repeating: "•", count: 16))
                                .font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                            copyButton("Copy", token)
                            Button("Regenerate") { token = MCPServer.regenerateToken(); copied = nil }
                        }
                    }
                    LabeledContent("Claude Code") { copyButton("Copy setup command", claudeCodeCommand) }
                    LabeledContent("Claude Desktop") { copyButton("Copy config", claudeDesktopConfig) }
                    Text("Claude Desktop: paste the config into the mcpServers section of claude_desktop_config.json (Claude → Settings → Developer → Edit Config) and restart it. It launches EZCal itself as a bridge, so it needs no Node and no token in the file. Regenerating the token disconnects HTTP agents (Claude Code) until you update them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copyButton(_ title: String, _ value: String) -> some View {
        Button(copied == value ? "Copied" : title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = value
        }
    }

    private var statusText: String {
        switch server.status {
        case .off: return enabled ? "Starting…" : "Off"
        case .starting: return "Starting…"
        case .running(let p): return "Running on 127.0.0.1:\(p)"
        case .failed(let m): return "Couldn't start: \(m)"
        }
    }
    private var statusColor: Color {
        switch server.status {
        case .running: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
