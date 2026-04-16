import Foundation

/// Utilities for extracting content from Gmail message payloads.
public enum MessageParser {
    // MARK: - Headers

    /// Returns the value of the first header matching `name`
    /// (case-insensitive) from the top-level payload.
    public static func extractHeader(
        _ name: String,
        from message: GmailMessage
    ) -> String? {
        message.payload?.headers?.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    // MARK: - Body

    /// Walks the MIME tree and returns the decoded body text.
    ///
    /// When `preferHTML` is true the method looks for `text/html`
    /// first and falls back to `text/plain`. The reverse applies
    /// when `preferHTML` is false.
    public static func extractBody(
        from message: GmailMessage,
        preferHTML: Bool = false
    ) -> String? {
        guard let payload = message.payload else { return nil }

        let preferred = preferHTML ? "text/html" : "text/plain"
        let fallback = preferHTML ? "text/plain" : "text/html"

        // Try the preferred MIME type first, then the fallback.
        if let data = findBodyData(
            in: payload,
            mimeType: preferred
        ) {
            return data
        }
        return findBodyData(in: payload, mimeType: fallback)
    }

    // MARK: - Contacts

    /// Parses the `From` header into an `EmailContact`.
    public static func extractSender(
        from message: GmailMessage
    ) -> EmailContact? {
        guard let from = extractHeader("From", from: message) else {
            return nil
        }
        return parseContact(from)
    }

    /// Parses a comma-separated address header (To, CC, BCC) into
    /// an array of contacts.
    public static func extractRecipients(
        from message: GmailMessage,
        header: String = "To"
    ) -> [EmailContact] {
        guard let value = extractHeader(header, from: message) else {
            return []
        }
        return splitAddressList(value).compactMap { parseContact($0) }
    }

    // MARK: - Base64url

    /// Decodes a base64url-encoded string (RFC 4648 §5) to `Data`.
    ///
    /// Gmail encodes body data with the URL-safe alphabet and omits
    /// padding characters.
    public static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Restore padding.
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }

    // MARK: - Private Helpers

    /// Recursively searches the MIME tree for a part matching
    /// `mimeType` and returns its decoded body string.
    private static func findBodyData(
        in payload: MessagePayload,
        mimeType: String
    ) -> String? {
        // Leaf node with matching type.
        if payload.mimeType?.lowercased() == mimeType.lowercased(),
           let encoded = payload.body?.data,
           let decoded = base64URLDecode(encoded)
        {
            return String(data: decoded, encoding: .utf8)
        }

        // Recurse into child parts.
        if let parts = payload.parts {
            for part in parts {
                if let result = findBodyData(
                    in: part,
                    mimeType: mimeType
                ) {
                    return result
                }
            }
        }

        return nil
    }

    /// Parses a single RFC 5322 mailbox string into an
    /// `EmailContact`.
    ///
    /// Handles formats like:
    /// - `user@example.com`
    /// - `"Jane Doe" <user@example.com>`
    /// - `Jane Doe <user@example.com>`
    private static func parseContact(_ raw: String) -> EmailContact? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Look for the angle-bracket form: Name <email>.
        if let openAngle = trimmed.lastIndex(of: "<"),
           let closeAngle = trimmed.lastIndex(of: ">"),
           openAngle < closeAngle
        {
            let email = String(
                trimmed[trimmed.index(after: openAngle) ..< closeAngle]
            ).trimmingCharacters(in: .whitespaces)

            var name = String(trimmed[trimmed.startIndex ..< openAngle])
                .trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes from the display name.
            if name.hasPrefix("\""), name.hasSuffix("\""),
               name.count >= 2
            {
                name = String(name.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
            }

            return EmailContact(
                name: name.isEmpty ? nil : name,
                email: email
            )
        }

        // Plain email address.
        return EmailContact(name: nil, email: trimmed)
    }

    /// Splits a comma-separated list of addresses while respecting
    /// quoted strings that may contain commas.
    private static func splitAddressList(
        _ value: String
    ) -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false
        var angleDepth = 0

        for char in value {
            switch char {
            case "\"":
                inQuotes.toggle()
                current.append(char)
            case "<" where !inQuotes:
                angleDepth += 1
                current.append(char)
            case ">" where !inQuotes:
                angleDepth = max(0, angleDepth - 1)
                current.append(char)
            case "," where !inQuotes && angleDepth == 0:
                let trimmed = current.trimmingCharacters(
                    in: .whitespaces
                )
                if !trimmed.isEmpty { results.append(trimmed) }
                current = ""
            default:
                current.append(char)
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { results.append(trimmed) }

        return results
    }
}
