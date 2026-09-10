import Foundation

enum Redaction {
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            #"Bearer\s+[A-Za-z0-9._~+/=-]+"#,
            #""?(access|refresh)_token"?\s*[:=]\s*"?[^"\s,&}]+"?"#,
            #"client_secret["']?\s*[:=]\s*["']?[^"'\s,&}]+"#,
            #"X-Amz-Signature=[0-9a-fA-F]+"#,
            #"X-Amz-Credential=[^&\s]+"#,
            #"appsecret_proof=[0-9a-fA-F]+"#,
            #"(sau|ut)=[A-Za-z0-9_~+=.-]+"#,
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    static func redact(_ input: String) -> String {
        var output = input
        for pattern in patterns {
            let range = NSRange(output.startIndex..., in: output)
            output = pattern.stringByReplacingMatches(in: output, range: range, withTemplate: "[redacted]")
        }
        return output
    }
}
