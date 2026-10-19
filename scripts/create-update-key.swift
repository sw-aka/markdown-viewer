import CryptoKit
import Foundation

// Sparkle 2.10 accepts the base64-encoded 32-byte Ed25519 private seed.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let privateURL = root.appending(path: ".private/SparkleSigningKey.txt")
let publicURL = root.appending(path: "Config/UpdateSigning.xcconfig")
guard !FileManager.default.fileExists(atPath: privateURL.path),
      !FileManager.default.fileExists(atPath: publicURL.path) else {
    fatalError("A signing key already exists. Do not rotate update keys accidentally.")
}
let key = Curve25519.Signing.PrivateKey()
try FileManager.default.createDirectory(at: privateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: publicURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try key.rawRepresentation.base64EncodedString().write(to: privateURL, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
let config = "// Public verification key. The private signing seed is never committed.\nUPDATE_PUBLIC_KEY = \(key.publicKey.rawRepresentation.base64EncodedString())\n"
try config.write(to: publicURL, atomically: true, encoding: .utf8)
print("Created a private signing seed in .private and a public verification configuration in Config.")
