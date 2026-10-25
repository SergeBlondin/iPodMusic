import SwiftUI
import UIKit
import AuthenticationServices

/// Guided, touch-friendly setup for Spotify / YouTube, styled like the iPod LCD.
/// Everything can be finished on the iPhone: no Xcode, no rebuild.
struct SourceSetupView: View {
    let kind: MusicSourceKind
    @Environment(Navigator.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var idText = ""
    @State private var idMessage: (String, Bool)? = nil     // text, isError
    @State private var testMessage: (String, Bool)? = nil
    @State private var busy = false
    @State private var copied: String? = nil
    @State private var refresh = 0

    private var provider: MusicLibraryProvider { nav.hub.library(for: kind)! }
    private var guide: SetupGuide { SetupGuide.for(kind) }

    var body: some View {
        let _ = refresh
        VStack(spacing: 0) {
            titleBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                        StepCard(number: i + 1, step: step, copied: $copied, open: { openURL($0) }, copy: copy)
                    }
                    clientIDCard(number: guide.steps.count + 1)
                    signInCard(number: guide.steps.count + 2)
                    testCard(number: guide.steps.count + 3)
                    resetCard
                    ForEach(guide.notes, id: \.self) { n in
                        Text(n).font(.system(size: 13)).foregroundStyle(lcdInk.opacity(0.75))
                    }
                }
                .padding(16)
            }
        }
        .background(SetupBackground().ignoresSafeArea())
        .foregroundStyle(lcdInk)
        .onAppear { idText = ClientIDStore.saved(kind) ?? "" }
    }

    // MARK: Pieces

    private var titleBar: some View {
        ZStack {
            Text(guide.title).font(.chicago(22))
            HStack {
                Spacer()
                Button("Done") { dismiss() }.font(.chicago(18)).foregroundStyle(lcdInk)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(LinearGradient(colors: [Color(hex: 0xDCE7F7), Color(hex: 0xB9C9DE)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Rectangle().fill(lcdInk.opacity(0.5)).frame(height: 1.5) }
    }

    private var status: (String, Bool) {
        if provider.setupProblem != nil { return ("Not set up yet", false) }
        if !provider.isSignedIn { return ("Client ID saved · not signed in", false) }
        return ("Connected ✓", true)
    }

    private var statusCard: some View {
        let (text, ok) = status
        return HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed").font(.system(size: 22, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.chicago(19))
                Text(guide.subtitle).font(.system(size: 13)).opacity(0.75)
            }
            Spacer()
        }
        .card(highlight: ok)
    }

    private func clientIDCard(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StepHeader(number: number, title: "Paste the Client ID")
            Text(guide.idHint).font(.system(size: 14))
            HStack(spacing: 8) {
                TextField(guide.idPlaceholder, text: $idText)
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lcdInk.opacity(0.4)))
                Button { idText = UIPasteboard.general.string ?? ""; save() } label: { Text("Paste") }
                    .buttonStyle(IPodButtonStyle())
            }
            Button("Save Client ID") { save() }.buttonStyle(IPodButtonStyle(primary: true))
            if let (m, err) = idMessage { SetupFeedback(text: m, error: err) }
        }
        .card()
    }

    private func signInCard(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StepHeader(number: number, title: "Sign in")
            Text(guide.signInHint).font(.system(size: 14))
            Button(provider.isSignedIn ? "Signed In ✓ (Sign In Again)" : "Sign In to \(kind.label)") {
                run { try await provider.signIn(); return "Signed in." }
            }
            .buttonStyle(IPodButtonStyle(primary: !provider.isSignedIn))
            .disabled(provider.setupProblem != nil || busy)
        }
        .card()
    }

    private func testCard(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StepHeader(number: number, title: "Test")
            Text("Fetches one of your playlists to check everything works.").font(.system(size: 14))
            Button(busy ? "Working…" : "Run Test") {
                run { try await provider.testConnection() }
            }
            .buttonStyle(IPodButtonStyle())
            .disabled(!provider.isSignedIn || busy)
            if let (m, err) = testMessage { SetupFeedback(text: m, error: err) }
        }
        .card()
    }

    private var resetCard: some View {
        HStack(spacing: 10) {
            Button("Disconnect") {
                provider.signOut(); nav.hub.revision += 1
                testMessage = ("Signed out. Your Client ID is kept.", false); refresh += 1
            }
            .buttonStyle(IPodButtonStyle())
            .disabled(!provider.isSignedIn)
            Button("Reset") {
                provider.signOut()
                ClientIDStore.save(nil, for: kind)
                idText = ""; idMessage = nil
                testMessage = ("Reset: Client ID removed and signed out.", false)
                nav.hub.revision += 1; refresh += 1
            }
            .buttonStyle(IPodButtonStyle(destructive: true))
        }
    }

    // MARK: Actions

    private func save() {
        guard let id = ClientIDStore.validate(idText, for: kind) else {
            idMessage = (guide.idInvalid, true); return
        }
        let changed = ClientIDStore.saved(kind) != id
        if changed { provider.signOut() }
        ClientIDStore.save(id, for: kind)
        idText = id
        idMessage = ("Saved ✓  Next: Sign In.", false)
        nav.hub.revision += 1; refresh += 1
    }

    private func run(_ work: @escaping () async throws -> String) {
        busy = true
        Task {
            do { testMessage = (try await work(), false) }
            catch { testMessage = (Self.explain(error, kind: kind), true) }
            busy = false; nav.hub.revision += 1; refresh += 1
        }
    }

    private func copy(_ label: String, _ value: String) {
        UIPasteboard.general.string = value
        copied = label
        Task { try? await Task.sleep(for: .seconds(1.5)); if copied == label { copied = nil } }
    }

    static func explain(_ e: Error, kind: MusicSourceKind) -> String {
        if case SourceError.http(let code, let msg) = e {
            switch code {
            case 401: return "401: sign-in expired or wrong Client ID. Tap Sign In again."
            case 403:
                return kind == .spotify
                    ? "403: Spotify refused. Add your account under User Management (needs Premium). \(msg)"
                    : "403: YouTube refused. Enable YouTube Data API v3 and add yourself as a test user. \(msg)"
            case 429: return "429: too many requests. Try again in a minute."
            default: return "Error \(code). \(msg)"
            }
        }
        let ns = e as NSError
        if ns.domain == ASWebAuthenticationSessionErrorDomain, ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return "Sign-in cancelled."
        }
        return e.localizedDescription
    }
}

// MARK: - Guide content

struct SetupStep {
    var title: String
    var detail: String
    var links: [(String, URL)] = []
    var copies: [(String, String)] = []
}

struct SetupGuide {
    var title: String
    var subtitle: String
    var steps: [SetupStep]
    var idHint: String
    var idPlaceholder: String
    var idInvalid: String
    var signInHint: String
    var notes: [String]

    static func `for`(_ k: MusicSourceKind) -> SetupGuide { k == .youtubeMusic ? youtube : spotify }

    static let bundleID = "com.sergebl.iPodMusic"
    static let teamID = "X647WK46TN"

    static let spotify = SetupGuide(
        title: "Set Up Spotify",
        subtitle: "Needs Spotify Premium and the Spotify app.",
        steps: [
            SetupStep(title: "Create a Spotify app",
                      detail: "Log in, then fill the form: any name and description, the Redirect URI below, and under “Which API/SDKs” tick iOS and Web API. Accept the terms and Save.",
                      links: [("Open Spotify Dashboard", URL(string: "https://developer.spotify.com/dashboard/create")!)],
                      copies: [("App name", "iPod"), ("Redirect URI", SpotifyService.redirectURI)]),
            SetupStep(title: "Add the iOS bundle ID",
                      detail: "In the new app: Settings ▸ Edit ▸ iOS app bundles. Add this bundle ID and Save.",
                      links: [("Open My Apps", URL(string: "https://developer.spotify.com/dashboard")!)],
                      copies: [("Bundle ID", bundleID)]),
            SetupStep(title: "Add yourself as a user",
                      detail: "Settings ▸ User Management: add the name and email of your Spotify (Premium) account. Development apps only work for listed users.",
                      copies: []),
            SetupStep(title: "Copy the Client ID",
                      detail: "Settings ▸ Basic Information ▸ Client ID. Copy it, come back here, then tap Paste.",
                      copies: []),
        ],
        idHint: "32 letters and digits from Basic Information.",
        idPlaceholder: "e.g. 1a2b3c… (32 characters)",
        idInvalid: "That isn't a Spotify Client ID. It should be exactly 32 characters, 0–9 and a–f.",
        signInHint: "Opens Spotify's login page. Approve access to your library and playback.",
        notes: ["Your Client ID is stored only on this iPhone. There's no client secret: sign-in uses PKCE.",
                "Spotify shows songs only for playlists you own or collaborate on."])

    static let youtube = SetupGuide(
        title: "Set Up YouTube",
        subtitle: "Uses the official YouTube Data API with your Google account.",
        steps: [
            SetupStep(title: "Create a Google Cloud project",
                      detail: "Sign in with your Google account and create a project (any name). Make sure it's selected at the top of the console for the next steps.",
                      links: [("Create Project", URL(string: "https://console.cloud.google.com/projectcreate")!)],
                      copies: [("Project name", "iPod Music")]),
            SetupStep(title: "Enable YouTube Data API v3",
                      detail: "Tap Enable on the API page.",
                      links: [("Open YouTube Data API", URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!)]),
            SetupStep(title: "Set up the consent screen",
                      detail: "Google Auth Platform ▸ Get started: app name “iPod”, your email, Audience External. Then in Audience, add your Gmail as a Test user. In Data Access, add the YouTube read-only scope below.",
                      links: [("Open Branding", URL(string: "https://console.cloud.google.com/auth/branding")!),
                              ("Open Audience (test users)", URL(string: "https://console.cloud.google.com/auth/audience")!),
                              ("Open Data Access (scopes)", URL(string: "https://console.cloud.google.com/auth/scopes")!)],
                      copies: [("App name", "iPod"), ("Scope", "https://www.googleapis.com/auth/youtube.readonly")]),
            SetupStep(title: "Create an iOS OAuth client",
                      detail: "Clients ▸ Create client ▸ Application type iOS. Enter the bundle ID and Team ID below and tap Create. No redirect URI is needed.",
                      links: [("Create OAuth Client", URL(string: "https://console.cloud.google.com/auth/clients/create")!)],
                      copies: [("Bundle ID", bundleID), ("Team ID", teamID)]),
            SetupStep(title: "Copy the Client ID",
                      detail: "Copy the Client ID Google shows (it ends in .apps.googleusercontent.com), come back here, then tap Paste.",
                      copies: []),
        ],
        idHint: "Looks like 1234567890-abc123….apps.googleusercontent.com",
        idPlaceholder: "…apps.googleusercontent.com",
        idInvalid: "That isn't a Google iOS Client ID. It should look like 1234567890-abc….apps.googleusercontent.com.",
        signInHint: "Opens Google sign-in. If Google warns the app isn't verified, tap Continue (it's your own app in testing).",
        notes: ["While the Google project is in Testing, Google asks you to sign in again about every 7 days.",
                "YouTube plays only while its video is on screen (YouTube's rules). “Open in YT Music” hands off to the YouTube Music app."])
}

// MARK: - Styling

private struct StepHeader: View {
    let number: Int
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)").font(.chicago(16)).foregroundStyle(Color(hex: 0xDCE7F7))
                .frame(width: 26, height: 26).background(Circle().fill(lcdInk))
            Text(title).font(.chicago(19))
        }
    }
}

private struct StepCard: View {
    let number: Int
    let step: SetupStep
    @Binding var copied: String?
    let open: (URL) -> Void
    let copy: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepHeader(number: number, title: step.title)
            Text(step.detail).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            ForEach(step.copies, id: \.0) { label, value in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label).font(.system(size: 11, weight: .semibold)).opacity(0.7)
                        Text(value).font(.system(size: 13, design: .monospaced)).lineLimit(2).minimumScaleFactor(0.7)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 4)
                    Button(copied == label ? "Copied ✓" : "Copy") { copy(label, value) }
                        .buttonStyle(IPodButtonStyle(compact: true))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.6)))
            }
            ForEach(step.links, id: \.0) { title, url in
                Button { open(url) } label: { Label(title, systemImage: "arrow.up.forward.app") }
                    .buttonStyle(IPodButtonStyle(primary: true))
            }
        }
        .card()
    }
}

private struct SetupFeedback: View {
    let text: String
    let error: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(error ? Color(red: 0.62, green: 0.1, blue: 0.1) : Color(red: 0.1, green: 0.4, blue: 0.15))
    }
}

struct IPodButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.chicago(compact ? 15 : 17))
            .padding(.horizontal, compact ? 12 : 14).padding(.vertical, compact ? 6 : 10)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(primary || c.isPressed ? Color(hex: 0xDCE7F7) : (destructive ? Color(red: 0.6, green: 0.1, blue: 0.1) : lcdInk))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(primary || c.isPressed
                          ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x5A6E8C), Color(hex: 0x3B4A63)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.7)))
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(lcdInk.opacity(0.45), lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
    }
}

private struct SetupBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0xA9BCD3), Color(hex: 0xC9D7EA), Color(hex: 0xDCE7F7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private extension View {
    func card(highlight: Bool = false) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(highlight ? 0.55 : 0.35)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(lcdInk.opacity(0.35), lineWidth: 1))
    }
}
