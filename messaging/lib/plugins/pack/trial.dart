/// Trying a pack without real texts (Matt, 2026-11-20: "a developer setting for users to be able to manually upload
/// plugins for development testing"): one text run through it as the app would run it, the lints a developer and the
/// reviewer read, and the sample texts every pack is tried on.
library;

import '../plugin.dart';
import '../registry.dart';
import 'manifest.dart';

/// What [tryPack] found for one text.
class PackTrial {
  const PackTrial({required this.seen, this.tags = const {}, this.section, this.row, this.actions = const {}, this.incoming = const [], this.shadowedBy, required this.took});
  final bool seen;                          // packSees held for these facts
  final Map<String, String?> tags;          // the pack's own tag names (no x<id>. prefix) → detail
  final String? section;                    // an own section key, or null
  final RowLook? row;
  final Map<String, List<String>> actions;  // slot name → labels offered there ('row' for end, word, tap)
  final List<String> incoming;              // 'markread' and/or 'mute' that would be asked for

  /// Where a built-in that is on in [tryPack]'s `beside` takes these facts first (A.8.3), as
  /// `<plugin name> › <section label>` ('Kinds of text › Payment reminders'); null where none does, or where no `store`
  /// was given.
  final String? shadowedBy;
  final Duration took;
}

/// [pack] run on one text as the app would run it: a fresh PackPlugin in a registry of its own, switched on, with
/// [prefs] over the settings' defaults (every toggle on where [switchesOn]); the facts are thread 1, from [from], not a
/// contact, not a group, not encrypted, `outgoing: false`, one sender, unread, the text as given (so A.9 holds).
/// [beside] (default PluginRegistry.instance) with the person's choices in [store] says what would take it first.
PackTrial tryPack(PluginPack pack, {required String text, String from = '72975', Map<String, String> prefs = const {}, bool switchesOn = false, PluginRegistry? beside, PluginStore? store}) => throw UnimplementedError(_later);

/// One of the texts every pack is tried on ("Try the samples").
class PackSample {
  const PackSample(this.id, this.text, {this.from = '72975'});
  final String id, text, from;
}

/// A.15's corpus, exactly: bills, receipts and parcels, and texts no such pack should touch (a sign-in code, a friend's
/// question, an appointment, a prize scam, a political text).
const List<PackSample> packSamples = [
  PackSample('s01', 'Your bill is ready. Amount due: \$45.20 by 3 Dec. Pay at example.com/pay'),
  PackSample('s02', 'EnergyCo: your statement is ready to view online.'),
  PackSample('s03', 'Thank you for your payment of £30.00. It may take 2 days to show.'),
  PackSample('s04', 'Payment of €12,50 received. Ref 88213.'),
  PackSample('s05', 'Reminder: minimum payment due on your card.'),
  PackSample('s06', 'Your council tax is due next week.'),
  PackSample('s07', 'Your parcel has shipped! Tracking number: 1Z999AA10123456784'),
  PackSample('s08', 'Your order is out for delivery today.'),
  PackSample('s09', 'We tried to deliver your parcel. Missed delivery, rebook at example.com'),
  PackSample('s10', 'Good news, your order has been dispatched.'),
  PackSample('s11', 'Your new blue parcel has shipped. Tracking no. JD014600006295117'),
  PackSample('s12', 'Your code is 482913. Don’t share it with anyone.'),
  PackSample('s13', 'Are we still on for dinner on Friday?'),
  PackSample('s14', 'Your appointment is on March 5th at 3pm. Reply C to cancel.'),
  PackSample('s15', 'Congratulations! You have won a \$500 gift card. Claim now: http://prize.example/win'),
  PackSample('s16', 'Vote YES on Measure 12 this Tuesday. Paid for by Friends of the Park.'),
];

/// What a developer and the reviewer should look at again: warnings only (broad_phrase, description_link, unused_tag,
/// opens_links).
List<PackIssue> lintPack(PluginPack pack) => throw UnimplementedError(_later);

const String _later = 'Trying and linting a pack come with the Marketplace\'s runtime (lib/plugins/pack/trial.dart).';
