import Foundation
import Observation
import Security
import CoderAPI

// MARK: - AccountManager

/// Manages Coder and Gmail account credentials.
///
/// Tokens are persisted in the macOS Keychain using
/// ``Security/SecItemAdd`` and friends. Observable properties
/// let SwiftUI views react to authentication state changes.
@Observable
@MainActor
final class AccountManager {

    // MARK: - Observable state

    /// The base URL of the Coder deployment (e.g.
    /// ``https://coder.example.com``).
    var coderBaseURL: URL?

    /// Whether a valid Coder session token is stored.
    var coderAuthenticated = false

    /// Whether valid Gmail OAuth tokens are stored.
    var gmailAuthenticated = false

    /// The Gmail address of the authenticated user, if known.
    var gmailEmail: String?

    /// Model configurations fetched from the Coder deployment.
    var availableModels: [ChatModel] = []

    /// The user-selected model configuration, or `nil` for the
    /// deployment default.
    var selectedModelConfigID: UUID?

    /// The Coder organization used for chat sessions.
    var organizationID: UUID?

    // MARK: - Constants

    private static let serviceName = "com.codermail.credentials"
    private static let coderTokenKey = "coder_session_token"
    private static let coderURLKey = "coder_base_url"
    private static let gmailAccessKey = "gmail_access_token"
    private static let gmailRefreshKey = "gmail_refresh_token"
    private static let gmailEmailKey = "gmail_email"

    // MARK: - Coder Token

    /// Persist a Coder session token in the Keychain and mark the
    /// account as authenticated.
    func saveCoderToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { return }
        try save(key: Self.coderTokenKey, data: data)
        coderAuthenticated = true
    }

    /// Load the stored Coder session token, or `nil` when none
    /// exists.
    func loadCoderToken() throws -> String? {
        guard let data = try load(key: Self.coderTokenKey) else {
            coderAuthenticated = false
            return nil
        }
        let token = String(data: data, encoding: .utf8)
        coderAuthenticated = token != nil
        return token
    }

    /// Persist the Coder base URL alongside the token.
    func saveCoderBaseURL(_ url: URL) throws {
        guard
            let data = url.absoluteString.data(using: .utf8)
        else {
            return
        }
        try save(key: Self.coderURLKey, data: data)
        coderBaseURL = url
    }

    /// Load the stored Coder base URL.
    func loadCoderBaseURL() throws -> URL? {
        guard let data = try load(key: Self.coderURLKey),
            let str = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let url = URL(string: str)
        coderBaseURL = url
        return url
    }

    // MARK: - Gmail Tokens

    /// Store both the OAuth access and refresh tokens.
    func saveGmailTokens(
        access: String,
        refresh: String
    ) throws {
        guard let accessData = access.data(using: .utf8),
            let refreshData = refresh.data(using: .utf8)
        else {
            return
        }
        try save(key: Self.gmailAccessKey, data: accessData)
        try save(key: Self.gmailRefreshKey, data: refreshData)
        gmailAuthenticated = true
    }

    /// Load the stored Gmail OAuth tokens, or `nil` when none
    /// exist.
    func loadGmailTokens() throws
        -> (access: String, refresh: String)?
    {
        guard
            let accessData = try load(key: Self.gmailAccessKey),
            let refreshData = try load(key: Self.gmailRefreshKey),
            let access = String(
                data: accessData, encoding: .utf8
            ),
            let refresh = String(
                data: refreshData, encoding: .utf8
            )
        else {
            gmailAuthenticated = false
            return nil
        }
        gmailAuthenticated = true
        return (access, refresh)
    }

    /// Persist the Gmail address for display purposes.
    func saveGmailEmail(_ email: String) throws {
        guard let data = email.data(using: .utf8) else { return }
        try save(key: Self.gmailEmailKey, data: data)
        gmailEmail = email
    }

    /// Load the stored Gmail email address.
    func loadGmailEmail() throws -> String? {
        guard let data = try load(key: Self.gmailEmailKey),
            let email = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        gmailEmail = email
        return email
    }

    // MARK: - Clear

    /// Remove all stored credentials and reset observable state.
    func clearAll() throws {
        delete(key: Self.coderTokenKey)
        delete(key: Self.coderURLKey)
        delete(key: Self.gmailAccessKey)
        delete(key: Self.gmailRefreshKey)
        delete(key: Self.gmailEmailKey)

        coderBaseURL = nil
        coderAuthenticated = false
        gmailAuthenticated = false
        gmailEmail = nil
        availableModels = []
        selectedModelConfigID = nil
        organizationID = nil
    }

    // MARK: - Keychain Helpers

    private func save(key: String, data: Data) throws {
        // Remove an existing item first so SecItemAdd does not
        // return errSecDuplicateItem.
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccountManagerError.keychainWrite(status)
        }
    }

    private func load(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(
            query as CFDictionary, &result
        )

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AccountManagerError.keychainRead(status)
        }

        return result as? Data
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

/// Errors produced by ``AccountManager`` Keychain operations.
enum AccountManagerError: Error, LocalizedError {
    case keychainWrite(OSStatus)
    case keychainRead(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainWrite(let status):
            return "Keychain write failed (OSStatus \(status))."
        case .keychainRead(let status):
            return "Keychain read failed (OSStatus \(status))."
        }
    }
}
