/// A DEBUG BUILD'S ONLY: the App Store's pictures without a third party's name or mark (2026-10-19). Apple refused
/// iOS 2.2.1 under 4.1(a) for metadata that "resembles Claude", and Matt: "Mention AI and stuff but don't include
/// specific brands, for the claude integrations show a generic AI icon for the submission". So for the pictures the
/// app's Claude is drawn as a generic assistant: a plain sparkle in grey in place of the mark and its orange, and
/// "Assistant" or "AI" where the app writes Claude's name.
///
/// On only in a debug build made with --dart-define=GHOST_STORE_NEUTRAL=true (and const, so a release, where
/// [kDebugMode] is false, compiles none of it in). Not for main: it lives on the store-pictures branches.
library;

import 'package:flutter/foundation.dart';

/// Whether this build draws the app's Claude as a generic assistant.
const bool storeNeutral = kDebugMode && bool.fromEnvironment('GHOST_STORE_NEUTRAL');

/// [words] with Claude's name (and Anthropic's, and MCP's) put generically, in a store-neutral build; as they are
/// otherwise.
String neutral(String words) {
  if (!storeNeutral) return words;
  if (words == 'Claude') return 'Assistant';
  var s = words
      .replaceAll('Claude’s own app', 'your AI assistant’s own app')
      .replaceAll("Claude's own app", "your AI assistant's own app")
      .replaceAll('Ask Claude', 'Ask AI')
      .replaceAll('Anthropic API key', 'API key')
      .replaceAll('Anthropic', 'your AI provider')
      .replaceAll('MCP server', 'connector')
      .replaceAll('MCP', 'connector');
  if (s.startsWith('Claude ')) s = 'The assistant ${s.substring(7)}';
  return s.replaceAll('Claude', 'the assistant');
}
