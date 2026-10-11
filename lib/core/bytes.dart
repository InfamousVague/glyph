/// Bytes written out as text. A port of `src/app/core/bytes.ts`, with the two functions of
/// `src/app/core/sync/crypto.ts` that are only spelling: `toBase64Url` and `fromBase64Url`.
///
/// Standard base64 is what the Rust core reads when bytes cross the bridge as a string; hex is how a digest, or a
/// login half, is written down; URL-safe base64 with no padding is the sync wire's (docs/SYNC.md).
///
/// What differs: on the web the URL-safe pair lives with the wire's crypto, where the MCP server imports it; here the
/// crypto is the Rust core's (lib/account/crypto_api.dart) and the spelling needs none of it, so it is with the other
/// two. Pure: `dart:convert` and nothing else.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Standard, padded base64 (`toBase64`).
String toBase64(List<int> bytes) => base64.encode(bytes);

/// Two lower-case hex digits a byte (`toHex`).
String toHex(List<int> bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    out.write((byte & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// URL-safe base64 with no padding (`toBase64Url`): standard base64 with its two symbols swapped and the `=` cut.
String toBase64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// The bytes back out of URL-safe base64, padded or not (`fromBase64Url`). Throws [FormatException] for text that is
/// not base64, where the page's `atob` throws its own error.
Uint8List fromBase64Url(String text) {
  final standard = text.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
  if (standard.length % 4 == 1) throw const FormatException('That is not base64.');
  return base64.decode(standard.padRight(standard.length + (4 - standard.length % 4) % 4, '='));
}
