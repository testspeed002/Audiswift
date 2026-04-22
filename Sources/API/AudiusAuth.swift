import Foundation
import AppKit
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Keychain helper

enum Keychain {
    static let service = "com.openaudio.audiswift"

    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        // Delete any existing item first
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
#if DEBUG
            print("[Keychain] Failed to save '\(key)': \(status)")
#endif
        }
    }

    static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Presentation context

class WebAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - AudiusAuth

class AudiusAuth: NSObject, ObservableObject {
    static let shared = AudiusAuth()

    @Published var isSignedIn: Bool = false
    @Published var currentUser: User?

    func getAccessToken() -> String? {
        return Keychain.load(forKey: KeychainKey.accessToken)
    }

    // Read clientId from the same bundle key as apiKey — fallback to empty
    private var clientId: String {
        Bundle.main.object(forInfoDictionaryKey: "AudiusAPIKey") as? String ?? ""
    }
    private let redirectUri = "audiswift://callback"

    // PKCE state — stored temporarily during the auth flow
    private var pendingCodeVerifier: String?
    private var pendingState: String?

    private var authSession: ASWebAuthenticationSession?
    private let presentationContextProvider = WebAuthPresentationContextProvider()

    enum KeychainKey {
        static let accessToken  = "audius_access_token"
        static let refreshToken = "audius_refresh_token"
    }

    private override init() {
        super.init()
        // Migrate any legacy UserDefaults token into Keychain then delete it
        if let legacyToken = UserDefaults.standard.string(forKey: "audius_access_token") {
            Keychain.save(legacyToken, forKey: KeychainKey.accessToken)
            UserDefaults.standard.removeObject(forKey: "audius_access_token")
        }
        loadStoredCredentials()
    }

    private func loadStoredCredentials() {
        guard let _ = Keychain.load(forKey: KeychainKey.accessToken) else { return }
        isSignedIn = true
        Task { await fetchCurrentUser() }
    }

    // MARK: - PKCE helpers

    private func generateRandomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        var b64 = Data(digest).base64EncodedString()
        b64 = b64.replacingOccurrences(of: "+", with: "-")
               .replacingOccurrences(of: "/", with: "_")
               .replacingOccurrences(of: "=", with: "")
        return b64
    }

    // MARK: - Sign in

    func signIn() {
        let codeVerifier = generateRandomString(length: 64)
        let state        = generateRandomString(length: 32)
        pendingCodeVerifier = codeVerifier
        pendingState        = state

        var components = URLComponents(string: "https://api.audius.co/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type",          value: "code"),
            URLQueryItem(name: "api_key",                value: clientId),
            URLQueryItem(name: "redirect_uri",           value: redirectUri),
            URLQueryItem(name: "scope",                  value: "read"),
            URLQueryItem(name: "state",                  value: state),
            URLQueryItem(name: "code_challenge",         value: generateCodeChallenge(from: codeVerifier)),
            URLQueryItem(name: "code_challenge_method",  value: "S256")
        ]
        guard let url = components.url else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "audiswift") { [weak self] callbackURL, error in
            guard let self else { return }
            if let error = error {
#if DEBUG
                print("[Auth] Session error: \(error)")
#endif
                self.pendingCodeVerifier = nil
                self.pendingState = nil
                return
            }
            guard let callbackURL else { return }
            self.handleCallback(url: callbackURL)
        }
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = false
        session.start()
        authSession = session
    }

    // MARK: - Callback handling (with CSRF state check)

    private func handleCallback(url: URL) {
        var params: [String: String] = [:]

        // Audius may return params as query string or fragment
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems?.forEach { params[$0.name] = $0.value ?? "" }
        components?.fragment?.split(separator: "&").forEach { part in
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { params[String(pair[0])] = String(pair[1]) }
        }

        // ── CSRF: verify state ──
        guard let returnedState = params["state"],
              returnedState == pendingState else {
#if DEBUG
            print("[Auth] State mismatch — possible CSRF. Aborting.")
#endif
            pendingCodeVerifier = nil
            pendingState = nil
            return
        }

        guard let code = params["code"] else {
#if DEBUG
            print("[Auth] No authorization code in callback.")
#endif
            return
        }

        Task { await completeSignIn(with: code) }
    }

    // MARK: - Token exchange

    func completeSignIn(with code: String) async {
        guard let url = URL(string: "https://api.audius.co/v1/oauth/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code,
            "code_verifier": pendingCodeVerifier ?? "",
            "client_id":     clientId,
            "redirect_uri":  redirectUri
        ]

        // Clear pending PKCE values regardless of outcome
        pendingCodeVerifier = nil
        pendingState = nil

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
#if DEBUG
                print("[Auth] Token exchange failed (\(http.statusCode)): \(String(data: data, encoding: .utf8) ?? "")")
#endif
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
#if DEBUG
                print("[Auth] Unexpected token response")
#endif
                return
            }

            // Save tokens securely
            Keychain.save(token, forKey: KeychainKey.accessToken)
            if let refresh = json["refresh_token"] as? String {
                Keychain.save(refresh, forKey: KeychainKey.refreshToken)
            }

            await MainActor.run {
                self.isSignedIn  = true
            }
            await fetchCurrentUser()
        } catch {
#if DEBUG
            print("[Auth] Token exchange error: \(error)")
#endif
        }
    }

    // MARK: - Token refresh

    func refreshAccessToken() async -> Bool {
        guard let refreshToken = Keychain.load(forKey: KeychainKey.refreshToken),
              let url = URL(string: "https://api.audius.co/v1/oauth/token") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     clientId
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return false }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["access_token"] as? String else { return false }

            Keychain.save(newToken, forKey: KeychainKey.accessToken)
            if let newRefresh = json["refresh_token"] as? String {
                Keychain.save(newRefresh, forKey: KeychainKey.refreshToken)
            }
            await MainActor.run {
                // Tokens are updated in Keychain, just need to notify observers if needed
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Current user

    func fetchCurrentUser() async {
        do {
            let user = try await AudiusAPI.getMe()
            await MainActor.run { self.currentUser = user }
        } catch {
#if DEBUG
            print("[Auth] Failed to fetch current user: \(error)")
#endif
        }
    }

    // MARK: - Sign out

    @MainActor
    func signOut() {
        // Best-effort server-side revocation
        if let refresh = Keychain.load(forKey: KeychainKey.refreshToken) {
            Task {
                guard let url = URL(string: "https://api.audius.co/v1/oauth/revoke") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: [
                    "token": refresh, "client_id": clientId
                ])
                _ = try? await URLSession.shared.data(for: req)
            }
        }
        Keychain.delete(forKey: KeychainKey.accessToken)
        Keychain.delete(forKey: KeychainKey.refreshToken)
        currentUser = nil
        isSignedIn  = false

        // Clear user data to prevent data leaks after sign-out
        PlaybackHistory.shared.clear()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "lastTrackID")
        defaults.removeObject(forKey: "lastPlaybackTime")
        defaults.removeObject(forKey: "lastContextIDs")
        defaults.removeObject(forKey: "lastContextIndex")
    }

    // MARK: - Manual token (dev/testing)

    func setManualToken(_ token: String) {
        Keychain.save(token, forKey: KeychainKey.accessToken)
        isSignedIn  = true
        Task { await fetchCurrentUser() }
    }
}
