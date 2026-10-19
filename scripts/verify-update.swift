import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
      let rawKey = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fatalError("Expected public key, signature, and archive path.")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
guard key.isValidSignature(signature, for: data) else {
    fputs("Update signature does not match the application's public key.\n", stderr)
    exit(1)
}
print("Update signature verified against the application's public key.")
