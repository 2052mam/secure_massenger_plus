import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Password-based message encryption (Telegram spoiler-like locked messages).
///
/// - Text: AES-256-CBC with PBKDF2-style key (sha256(password+salt) x iterations).
///   Stored format: `ENC1:<base64 salt>:<base64 iv>:<base64 ciphertext>`
/// - Media bytes: same scheme over raw bytes, base64-wrapped for transport.
/// The server only ever sees ciphertext; without the password nothing renders.
class EncryptionService {
  static const String prefix = 'ENC1';
  static const int _iterations = 12000;

  static Uint8List _deriveKey(String password, Uint8List salt) {
    var key = Uint8List.fromList(utf8.encode(password) + salt);
    for (var i = 0; i < _iterations; i++) {
      key = Uint8List.fromList(sha256.convert(key + salt).bytes);
    }
    return Uint8List.fromList(sha256.convert(key).bytes); // 32 bytes
  }

  static Uint8List _randomBytes(int len) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(len, (_) => r.nextInt(256)));
  }

  static bool isEncryptedPayload(String? content) =>
      content != null && content.startsWith('$prefix:');

  /// Encrypt UTF-8 text with [password]. Returns the storable payload.
  static String encryptText(String plaintext, String password) {
    final salt = _randomBytes(16);
    final key = _deriveKey(password, salt);
    final iv = enc.IV(_randomBytes(16));
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    final ct = encrypter.encrypt(plaintext, iv: iv);
    return '$prefix:${base64Encode(salt)}:${base64Encode(iv.bytes)}:${ct.base64}';
  }

  /// Decrypt a payload produced by [encryptText]. Throws on wrong password.
  static String decryptText(String payload, String password) {
    final parts = payload.split(':');
    if (parts.length != 4 || parts[0] != prefix) {
      throw const FormatException('Not an encrypted payload');
    }
    final salt = base64Decode(parts[1]);
    final iv = enc.IV(base64Decode(parts[2]));
    final key = _deriveKey(password, Uint8List.fromList(salt));
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    return encrypter.decrypt64(parts[3], iv: iv);
  }

  /// Encrypt raw media bytes with [password]. Returns bytes to upload.
  /// Wire format: `SME1` + salt(16) + iv(16) + ciphertext.
  static Uint8List encryptBytes(Uint8List plain, String password) {
    final salt = _randomBytes(16);
    final key = _deriveKey(password, salt);
    final ivBytes = _randomBytes(16);
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    final ct = encrypter.encryptBytes(plain, iv: enc.IV(ivBytes));
    final out = BytesBuilder();
    out.add(utf8.encode('SME1'));
    out.add(salt);
    out.add(ivBytes);
    out.add(ct.bytes);
    return out.toBytes();
  }

  static bool isEncryptedBytes(Uint8List bytes) =>
      bytes.length > 36 &&
      bytes[0] == 0x53 && bytes[1] == 0x4D && bytes[2] == 0x45 && bytes[3] == 0x31;

  /// Decrypt bytes produced by [encryptBytes]. Throws on wrong password.
  static Uint8List decryptBytes(Uint8List encrypted, String password) {
    if (!isEncryptedBytes(encrypted)) {
      throw const FormatException('Not encrypted media');
    }
    final salt = encrypted.sublist(4, 20);
    final iv = enc.IV(encrypted.sublist(20, 36));
    final ct = encrypted.sublist(36);
    final key = _deriveKey(password, salt);
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    return Uint8List.fromList(encrypter.decryptBytes(enc.Encrypted(ct), iv: iv));
  }
}
