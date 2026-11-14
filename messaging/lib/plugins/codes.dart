/// Codes: sign-in codes in a section of their own (Matt, 2026-11-14: "separating OTPs into their own section").
///
/// A text is a code where the notification's "Copy 482913" button would say it is: [signInCode] is that finder
/// (android/.../Notifier.kt, `otp`) written again here with the same two rules, so the list, the notification and
/// what Ghost Keyboard is offered agree on what a code is. A conversation whose newest text is a code, from one
/// number that is not in the phone's contacts, leaves the main list for the Codes section: the newest first, the
/// code drawn large, and a tap (or the button at the row's end) copies it. A contact's "the door code is 4417"
/// stays where it is; its long press can move it. Nothing leaves the phone, and nothing is kept: the code is read
/// off the conversation's last words each time.
library;

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import 'companies.dart';
import 'company_marks.g.dart';
import 'plugin.dart';

// A word of its own: "pin" is in "shipping", "shopping" and "opinion", and "code" in "barcode".
final RegExp _codeWord = RegExp(r'(?<![A-Za-z0-9_])(?:(?:code|passcode|password|pin|otp|one[- ]time|2fa|login|log in|sign in|security)(?![A-Za-z0-9_])|verif)', caseSensitive: false);
final RegExp _codeDigits = RegExp(r'(?<![\w.,/-])(\d{3}[- ]\d{3}|\d{4,8})(?![\w/-]|[.,]\d)');
final RegExp _notDigit = RegExp(r'\D');

/// The sign-in code in [text], if it reads like one: 4 to 8 digits (or 123-456) in a text of 400 characters at
/// most that speaks of a code. Notifier.otp's rules, to the letter: a change to one is a change to both, and
/// test/plugin_codes_test.dart holds this one to the cases the Kotlin tests hold that one to.
String? signInCode(String text) {
  if (text.length > 400 || !_codeWord.hasMatch(text)) return null;
  return _codeDigits.firstMatch(text)?.group(0)!.replaceAll(_notDigit, '');
}

class CodesPlugin extends GhostPlugin {
  const CodesPlugin();

  /// The tag a text with a code is given; its detail is the code.
  static const tag = 'code';

  /// The section's id.
  static const section = 'codes';

  @override
  String get id => 'codes';

  @override
  String get name => 'Codes';

  @override
  String get description => 'Sign-in codes get a section of their own, newest first. Tap one to copy it.';

  @override
  LucideIcon get icon => Lucide.keyRound;

  PluginAction _copy(String code, int thread) => PluginAction(
        label: 'Copy $code',
        icon: Lucide.copy,
        run: (host) async {
          host.copy(code, say: 'Copied $code');
          // Copied is as good as read.
          if (host.prefs.flag('read')) await host.markRead(thread);
        },
      );

  @override
  List<Classifier> get classifiers => [
        (facts) {
          final code = signInCode(facts.text);
          return code == null ? const [] : [Tag(tag, code)];
        },
      ];

  @override
  List<ListSection> get sections => [
        ListSection(
          id: section,
          label: 'Codes',
          icon: Lucide.keyRound,
          // One number, not a contact: a friend's "the door code is 4417" is a conversation, not a code.
          takes: (facts, tags, prefs) => tags.has(tag) && !facts.contact && !facts.group,
          row: (facts, tags, prefs) {
            final code = tags.detail(tag);
            // Filed here by hand, and its last words are not a code: drawn as the main list draws it.
            if (code == null) return null;
            final copy = _copy(code, facts.thread);
            // Who it is from is in its words, not its number (companies.dart; Matt: "have the codes section try
            // to parse the company that's sending the code and show their company logo as the code profile
            // picture"): a company the app knows gets its name and its own face (its mark from an open pack of
            // brand icons where the pack has one, tool/company_marks.py; else its letter), and any other the name
            // its text gives itself.
            final company = prefs.flag('company') ? companyIn(facts.text) : null;
            final named = company?.name ?? (prefs.flag('company') ? senderNameIn(facts.text) : null);
            return RowLook(
              value: code,
              end: copy,
              tap: copy,
              title: named,
              face: company == null ? null : RowFace(name: company.name, color: company.color, domain: company.domain, mark: companyMarks[company.domain]),
            );
          },
        ),
      ];

  @override
  List<SlotFill> get slots => [
        // A conversation's long press in the list: copy its code, and move it between Codes and the main list.
        Slots.conversationMenu.fill((place, prefs) {
          final code = place.tags.detail(tag);
          final thread = place.facts.thread;
          return [
            if (code != null) _copy(code, thread),
            if (place.section == section)
              PluginAction(label: 'Keep in Messages', icon: Lucide.messageSquare, run: (host) => host.move(thread, null))
            else if (code != null && place.section == null)
              PluginAction(label: 'Move to Codes', icon: Lucide.keyRound, run: (host) => host.move(thread, section)),
          ];
        }),
        // A message's long press in a conversation.
        Slots.messageMenu.fill((place, prefs) {
          final code = place.facts.outgoing == true ? null : place.tags.detail(tag);
          return [if (code != null) PluginAction(label: 'Copy $code', icon: Lucide.copy, run: (host) => host.copy(code, say: 'Copied $code'))];
        }),
      ];

  @override
  List<PluginSetting> get settings => const [
        PluginSetting.toggle(key: 'read', label: 'Mark as read when copied', hint: 'Copying a code from the list also marks its conversation as read.', icon: Lucide.checkCheck),
        PluginSetting.toggle(key: 'company', label: 'Show who a code is from', hint: 'A code is named by the company its text is from (Coinbase, Discover) where the text says, in place of its number.', icon: Lucide.store),
        PluginSetting.note(
          label: 'What counts as a code',
          hint: 'Four to eight digits in a text that speaks of a code, a PIN, a password or signing in, from a number that is not in your contacts. The same texts get a Copy button on their notification.',
          icon: Lucide.info,
        ),
      ];
}
