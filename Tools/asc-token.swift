// Prints a 20-minute App Store Connect API token (ES256 JWT) to stdout.
// Reads ASC_KEY_ID and ASC_ISSUER_ID from the environment and the private key from
// ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8, the same place altool uses.
// The key itself never leaves this process.
import CryptoKit
import Foundation

let environment = ProcessInfo.processInfo.environment
guard let keyID = environment["ASC_KEY_ID"], let issuer = environment["ASC_ISSUER_ID"] else {
    FileHandle.standardError.write(Data("Set ASC_KEY_ID and ASC_ISSUER_ID.\n".utf8))
    exit(1)
}

let keyPath = NSString(string: "~/.appstoreconnect/private_keys/AuthKey_\(keyID).p8").expandingTildeInPath
let key = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOfFile: keyPath, encoding: .utf8))

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let now = Int(Date().timeIntervalSince1970)
let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
let claims = try JSONSerialization.data(withJSONObject: [
    "iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1",
] as [String: Any])
let signingInput = base64URL(header) + "." + base64URL(claims)
let signature = try key.signature(for: Data(signingInput.utf8))
print(signingInput + "." + base64URL(signature.rawRepresentation))
