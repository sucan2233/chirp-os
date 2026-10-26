#!/usr/bin/env swift
// Independent Ed25519 update authentication; no Apple certificate is involved.
import CryptoKit
import Darwin
import Foundation

struct SigningError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func validateVersion(_ version: String) throws {
    let pattern = #"^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$"#
    guard version.range(of: pattern, options: .regularExpression) != nil,
          version != "0.0.0", !version.contains("\n"), !version.contains("\r") else {
        throw SigningError("Invalid version: expected X.Y.Z (major <= 9999; minor/patch <= 99)")
    }
}

func loadBase64(_ path: String, count: Int) throws -> Data {
    let text = try String(contentsOfFile: path, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: text), data.count == count,
          data.base64EncodedString() == text else {
        throw SigningError("Invalid base64 key/signature file: \(path) (expected \(count) bytes)")
    }
    return data
}

func matchingKey(_ privatePath: String, _ publicPath: String) throws -> Curve25519.Signing.PrivateKey {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: loadBase64(privatePath, count: 32))
    let publicData = try loadBase64(publicPath, count: 32)
    guard key.publicKey.rawRepresentation == publicData else {
        throw SigningError("Private key does not match the tracked update public key")
    }
    return key
}

// O_EXCL makes the no-overwrite contract apply even to dangling symlinks and races.
func createExclusive(_ path: String, _ data: Data, mode: mode_t) throws {
    let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
    guard descriptor >= 0 else { throw SigningError("Cannot create key file (must not exist): \(path)") }
    do {
        guard fchmod(descriptor, mode) == 0 else { throw SigningError("Cannot set key permissions") }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw SigningError("Cannot write key file") }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw SigningError("Cannot flush key file") }
    } catch {
        Darwin.close(descriptor)
        Darwin.unlink(path)
        throw error
    }
    Darwin.close(descriptor)
}

func initialize(_ privatePath: String, _ publicPath: String) throws {
    let key = Curve25519.Signing.PrivateKey()
    let privateData = Data((key.rawRepresentation.base64EncodedString() + "\n").utf8)
    let publicData = Data((key.publicKey.rawRepresentation.base64EncodedString() + "\n").utf8)
    try createExclusive(privatePath, privateData, mode: 0o600)
    do {
        try createExclusive(publicPath, publicData, mode: 0o644)
    } catch {
        Darwin.unlink(privatePath)
        throw error
    }
    print("Created private key file (0600): \(privatePath)")
    print("Created public key file: \(publicPath)")
}

func payload(_ archive: String, _ version: String) throws -> (data: Data, bytes: UInt64, hash: String) {
    try validateVersion(version)
    let url = URL(fileURLWithPath: archive)
    let name = url.lastPathComponent
    guard !name.isEmpty, !name.contains("\n"), !name.contains("\r") else {
        throw SigningError("Archive name cannot contain line breaks")
    }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw SigningError("Archive must be a regular file")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var sha = SHA256()
    var bytes: UInt64 = 0
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
        sha.update(data: chunk)
        bytes += UInt64(chunk.count)
    }
    let hash = sha.finalize().map { String(format: "%02x", $0) }.joined()
    let canonical = "ChirpOS Pro Update v1\n\(version)\n\(name)\n\(bytes)\n\(hash)\n"
    return (Data(canonical.utf8), bytes, hash)
}

let usage = """
Usage:
  swift scripts/pro-update-sign.swift init PRIVATE_PATH PUBLIC_PATH
  swift scripts/pro-update-sign.swift check-key PRIVATE_PATH PUBLIC_PATH
  swift scripts/pro-update-sign.swift sign ARCHIVE VERSION PRIVATE_PATH PUBLIC_PATH
  swift scripts/pro-update-sign.swift verify ARCHIVE VERSION PUBLIC_PATH
Keys are canonical base64 raw 32-byte Ed25519 keys; signatures are base64 raw 64 bytes.
Parent directories must exist. init never overwrites either path. sign writes ARCHIVE.sig.
"""

do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "init" where args.count == 3:
        try initialize(args[1], args[2])
    case "check-key" where args.count == 3:
        _ = try matchingKey(args[1], args[2])
        print("Update key pair matches")
    case "sign" where args.count == 5:
        let key = try matchingKey(args[3], args[4])
        let message = try payload(args[1], args[2])
        let signature = try key.signature(for: message.data)
        try Data((signature.base64EncodedString() + "\n").utf8)
            .write(to: URL(fileURLWithPath: args[1] + ".sig"), options: .atomic)
        print("Signed \(URL(fileURLWithPath: args[1]).lastPathComponent): \(message.bytes) bytes; sha256:\(message.hash)")
    case "verify" where args.count == 4:
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: loadBase64(args[3], count: 32))
        let message = try payload(args[1], args[2])
        let signature = try loadBase64(args[1] + ".sig", count: 64)
        guard key.isValidSignature(signature, for: message.data) else {
            throw SigningError("Update signature verification failed (version, filename, bytes, hash, or key mismatch)")
        }
        print("Verified \(URL(fileURLWithPath: args[1]).lastPathComponent): \(message.bytes) bytes; sha256:\(message.hash)")
    default:
        throw SigningError(usage)
    }
} catch {
    // Never print key contents or the underlying CryptoKit error payload.
    let message = (error as? SigningError)?.description ?? "Update signing operation failed; check paths and key files"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
