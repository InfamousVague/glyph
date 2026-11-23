/// A Ghost account's screens (lib/account; Matt, 2026-11-17: "We need to have a way to login to existing accounts. We
/// might need to add password based authentication as well as SMS verification for verified numbers"; "I like your
/// recommendation let's do it for now"; "i also want accounts to be generated based on ethereum type addresses with a
/// recovery seed we can back up"): making one (a password, then the recovery words written down and confirmed), signing
/// in to one (username and password, with the texted code where its number is verified; or the recovery words), and on
/// a signed-in device its address, a new password, the words again, and the devices signed in.
library;

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/account.dart';
import '../account/account_crypto.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../desktop/own_calls.dart' show DeskOwnCalls;
import '../kit/semantic_colors.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart' show Me, tidyHandle;
import '../sms.dart';
import 'common.dart';
import 'computers.dart' show PairButton;

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

/// A password is at least this long: the backup's password copy can be tried offline by anyone who gets it, and only
/// Argon2id's cost and the password's length stand in the way.
const minPassword = 10;

/// The address cut short for a row: 0x1234…abcd.
String shortAddress(String a) => a.length < 14 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

/// Settings › Me's Account section: the address and what can be done with it, or the two ways in.
Widget accountSection(BuildContext context) => ListenableBuilder(listenable: Account.instance, builder: (context, _) => _accountSection(context));

/// The account the phone this computer is paired with is signed in to, as it last said; null anywhere else.
({String address, String username})? phoneAccountHere() {
  final calls = Sms.calls;
  return calls is DeskOwnCalls ? calls.phoneAccount : null;
}

Widget _accountSection(BuildContext context) {
  final account = Account.instance;
  final address = account.address;
  if (address == null) {
    // A computer paired with a phone, with the phone's identity (Matt, 2026-11-18: "On my fold vs on my desktop, both
    // with the same number linked but it seems i'm not logged in on desktop"): signing in to the phone's own account
    // keeps it the same you, and is offered first, by name, where the phone has said which it is.
    final paired = Sms.paired;
    final phones = paired ? phoneAccountHere() : null;
    return PaneSection(
        title: 'Account',
        description: Text(paired
            ? 'Sign in to the account your phone is in, so this computer is the same you as your phone, or make one for who you are now.'
            : 'Keep who you are on Ghost Messaging, your friends and circles, and sign in with them on another device.'),
        footer: account.removedHere ? const Text('This device was signed out of your account from another device.') : null,
        children: [
          if (phones != null)
            SettingRow(
              icon: _icon(Lucide.smartphone),
              label: 'Sign in to your Ghost account',
              hint: Text(phones.username.isEmpty ? 'The account your phone is in, ${shortAddress(phones.address)}' : '@${phones.username}, the account your phone is in'),
              onPress: () => push(context, (_) => SignInScreen(username: phones.username)),
            ),
          SettingRow(
            icon: _icon(Lucide.userPlus),
            label: 'Create an account',
            hint: Text(paired ? 'Keeps who you are now, the same you as your phone' : 'A password and 12 recovery words'),
            onPress: () => push(context, (_) => const CreateAccountScreen()),
          ),
          if (phones == null || phones.username.isEmpty)
            SettingRow(icon: _icon(Lucide.keyRound), label: paired ? 'Sign in to your Ghost account' : 'Sign in to an account', hint: const Text('With your username and password, or your recovery words'), onPress: () => push(context, (_) => const SignInScreen()))
          else
            SettingRow(icon: _icon(Lucide.keyRound), label: 'Sign in to another account', hint: const Text('With your username and password, or your recovery words'), onPress: () => push(context, (_) => const SignInScreen())),
        ],
      );
  }
  return PaneSection(
      title: 'Account',
      children: [
        SettingRow(
          icon: _icon(Lucide.shieldCheck),
          label: 'Address',
          hint: Text(shortAddress(address)),
          control: _CopyButton(text: address),
        ),
        SettingRow(icon: _icon(Lucide.lock), label: 'Change password', onPress: () => push(context, (_) => const ChangePasswordScreen())),
        SettingRow(icon: _icon(Lucide.eye), label: 'Show recovery words', hint: const Text('After your password'), onPress: () => push(context, (_) => const ShowWordsScreen())),
        SettingRow(icon: _icon(Lucide.laptop), label: 'Signed in on these devices', onPress: () => push(context, (_) => const DevicesScreen())),
        SettingRow(
          icon: _icon(Lucide.logOut),
          label: 'Sign out of this device',
          onPress: () => showChoices(context, title: 'Sign out of this device? It becomes someone new here: your friends and circles stay with your account, and come back when you sign in again.', choices: [
            Choice('Sign out', Lucide.logOut, () async {
              final again = await Account.instance.signOut();
              if (!again && context.mounted) await push<void>(context, (_) => const RestartScreen());
            }, danger: true),
          ]),
        ),
      ],
    );
}

/// The copy mark at the end of the Address row: puts the whole address on the clipboard and says so.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => GlacierPressable(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: text));
          toast(context, 'Address copied');
        },
        semanticLabel: 'Copy address',
        builder: (context, state) => Padding(padding: EdgeInsets.all(context.tokens.space(2)), child: _icon(Lucide.copy)),
      );
}

/// The page every account screen is drawn on: a titled page, its sections, and the button at the end.
class _AccountPage extends StatelessWidget {
  const _AccountPage({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GhostPage(
      title: title,
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: children,
        ),
      ),
    );
  }
}

/// A text field as a settings row: never corrected or capitalised, dotted out when [secret], and with the autofill
/// hint that lets a password manager fill it.
Widget _field(TextEditingController c, String placeholder, String label, {bool secret = false, ValueChanged<String>? onSubmitted, TextInputType? keyboard, String? autofill}) => SettingRowBox(
      child: GlacierInput(
        controller: c,
        placeholder: placeholder,
        ariaLabel: label,
        type: secret ? GlacierInputType.password : GlacierInputType.text,
        autoCorrect: false,
        autoCapitalize: TextCapitalization.none,
        inputMode: keyboard,
        autoComplete: autofill,
        size: GlacierFieldSize.md,
        onSubmitted: onSubmitted,
      ),
    );

/// What went wrong, in the danger colour, for a section's footer; nothing where there is no problem.
Widget _problemText(BuildContext context, String? problem) => problem == null ? const SizedBox.shrink() : Text(problem, style: TextStyle(color: context.tokens.danger));

Widget _gap(BuildContext context, [int n = 6]) => SizedBox(height: context.tokens.space(n));

/// The twelve words, numbered, as many to a row as fit whole (two on a phone, three or four on a wider window), in the
/// mono face so l and 1 are not confused. A word is never cut short: a word half shown is a word copied wrong.
class RecoveryWordsGrid extends StatelessWidget {
  const RecoveryWordsGrid({super.key, required this.words});
  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      final across = (box.maxWidth / t.lenOf('9rem')).floor().clamp(2, 4);
      final gap = t.space(2);
      final width = (box.maxWidth - gap * (across - 1)) / across;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < words.length; i++)
            Container(
              width: width,
              padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
              decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('md')), border: Border.all(color: t.color('app-rule'))),
              child: Row(children: [
                SizedBox(width: t.lenOf('1.6rem'), child: Text('${i + 1}', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-2'), mono: true))),
                Expanded(child: Text(words[i], style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'), mono: true), overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
      );
    });
  }
}

/// An address whole, in the mono face, in groups of ten so it can be read out and compared: 0x, then two lines.
class AddressBlock extends StatelessWidget {
  const AddressBlock({super.key, required this.address});
  final String address;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hex = address.startsWith('0x') ? address.substring(2) : address;
    final groups = [for (var i = 0; i < hex.length; i += 10) hex.substring(i, min(i + 10, hex.length))];
    final style = pageText(t, t.fontSize('lg'), weight: 'medium', color: t.color('app-ink'), mono: true, height: 1.5);
    return Semantics(
      label: 'Address $address',
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('0x ', style: style.copyWith(color: t.color('app-ink-2'))),
          Expanded(child: Text([for (var i = 0; i < groups.length; i += 2) groups.skip(i).take(2).join(' ')].join('\n'), style: style)),
        ]),
      ),
    );
  }
}

/// A word to tap, in confirming the words: pressed ones are greyed and can't be pressed again.
class _WordChip extends StatelessWidget {
  const _WordChip({required this.word, required this.onPressed, this.used = false});
  final String word;
  final VoidCallback? onPressed;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: used ? null : onPressed,
      semanticLabel: word,
      builder: (context, state) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: used ? 0.3 : 1,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
          decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('full')), border: Border.all(color: t.color('app-rule'))),
          child: Text(word, style: pageText(t, t.fontSize('md'), color: t.color('app-ink'), mono: true)),
        ),
      ),
    );
  }
}

// --- making an account -------------------------------------------------------------------------------------------------

/// The pages of making an account, in the order they are walked.
enum CreateStep { password, words, confirm, working, done }

/// Making an account: a password, the words to write down, the words confirmed (tapped in order, or three of them
/// typed), then the backup sealed and kept, and the address shown.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, this.step = CreateStep.password, this.draft, this.typed = false, this.made = false});

  /// Where it starts, and with which words: for the pictures (test/account_shots.dart).
  final CreateStep step;
  final AccountDraft? draft;
  final bool typed;

  /// The account is made already, from the first page's username and password (lib/standalone/welcome.dart): its
  /// words shown and checked, and the screen closed after.
  final bool made;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  late CreateStep _step = widget.step;
  late final AccountDraft _draft = widget.draft ?? Account.instance.draft();
  late bool _typed = widget.typed;
  // The words in a mixed order to tap from, and the places in [_shuffled] tapped so far, in the order tapped.
  late final List<String> _shuffled = [..._draft.words]..shuffle(Random());
  final List<int> _tapped = [];
  // For the typed check: three places among the twelve, in rising order, and a field for each.
  late final List<int> _asked = (List.generate(12, (i) => i)..shuffle(Random())).take(3).toList()..sort();
  late final _three = [for (var i = 0; i < 3; i++) TextEditingController()];
  String? _problem;
  // What making the account answered: the app has to start again to become the account.
  bool _restart = false;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    for (final c in _three) {
      c.dispose();
    }
    super.dispose();
  }

  /// From the password page to the words: only with a password long enough, typed the same twice.
  void _toWords() {
    if (_password.text.length < minPassword) return setState(() => _problem = 'A password is at least $minPassword characters.');
    if (_password.text != _again.text) return setState(() => _problem = 'The two passwords are not the same.');
    setState(() {
      _problem = null;
      _step = CreateStep.words;
    });
  }

  /// The words are shown to be written down: the three asked for typed right, or all twelve tapped in order.
  bool get _confirmed {
    if (_typed) return [for (var i = 0; i < 3; i++) _three[i].text.trim().toLowerCase() == _draft.words[_asked[i]]].every((ok) => ok);
    return _tapped.length == 12 && [for (var i = 0; i < 12; i++) _shuffled[_tapped[i]] == _draft.words[i]].every((ok) => ok);
  }

  /// A word tapped: kept if it is the next of the twelve, and otherwise said to be wrong and not counted.
  void _tap(int i) {
    setState(() {
      _problem = null;
      _tapped.add(i);
      final n = _tapped.length;
      if (_shuffled[i] != _draft.words[n - 1]) {
        _problem = 'Word $n isn\'t ${_shuffled[i]}. Start again from there.';
        _tapped.removeLast();
      }
    });
  }

  /// The check passed by (Matt, 2026-11-20: "add a button to skip verifying the seed phrase"): the words can be seen
  /// again any time in Settings › Me, after the password.
  void _skipCheck() => widget.made ? Navigator.of(context).pop() : _make(checked: false);

  /// Makes the account from the draft and the password, then shows its address; a failure goes back to the check
  /// with what went wrong. Where the account is made already this only closes the screen.
  Future<void> _make({bool checked = true}) async {
    if (widget.made) return Navigator.of(context).pop();
    if (checked && !_confirmed) return setState(() => _problem = _typed ? 'Those aren\'t the words in those places. Look at what you wrote down.' : 'Tap all twelve in order.');
    setState(() {
      _problem = null;
      _step = CreateStep.working;
    });
    try {
      _restart = await Account.instance.create(_draft, _password.text);
      if (mounted) setState(() => _step = CreateStep.done);
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = CreateStep.confirm;
          _problem = e is AccountError ? e.message : 'The account could not be made just now. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final words = _draft.words;
    switch (_step) {
      case CreateStep.password:
        return _AccountPage(title: 'Create an account', children: [
          PaneSection(
            title: 'Choose a password',
            description: const Text('With your username and this password you can sign in on another device. Make it long: anyone who got hold of your backup could try passwords against it.'),
            footer: _problem == null ? Text('At least $minPassword characters.') : _problemText(context, _problem),
            children: [
              _field(_password, 'Password', 'Password', secret: true, autofill: 'new-password'),
              _field(_again, 'The same again', 'The same password again', secret: true, autofill: 'new-password', onSubmitted: (_) => _toWords()),
            ],
          ),
          _gap(context, 8),
          PairButton(label: 'Next', icon: Lucide.arrowRight, onPressed: _toWords),
        ]);
      case CreateStep.words:
        return _AccountPage(title: 'Your recovery words', children: [
          PaneSection(
            title: 'Write these down',
            description: const Text('On paper, in this order, and keep it somewhere safe. These 12 words are your account: with them you can sign in without your password, and nobody can give them back to you if they are lost.'),
            children: [Padding(padding: EdgeInsets.all(t.space(3)), child: RecoveryWordsGrid(words: words))],
          ),
          _gap(context),
          SettingsCallout(icon: _icon(Lucide.shieldCheck), child: const Text('Never type them into a website or tell them to anyone. Ghost Messaging will never ask for them except here, to sign in.')),
          _gap(context, 8),
          PairButton(label: 'I\'ve written them down', icon: Lucide.arrowRight, onPressed: () => setState(() => _step = CreateStep.confirm)),
        ]);
      case CreateStep.confirm:
        return _AccountPage(title: 'Check your words', children: [
          if (!_typed)
            PaneSection(
              title: 'Tap them in order',
              footer: _problem == null ? Text('${_tapped.length} of 12') : _problemText(context, _problem),
              children: [
                Padding(
                  padding: EdgeInsets.all(t.space(3)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    RecoveryWordsGrid(words: [for (var i = 0; i < 12; i++) i < _tapped.length ? _shuffled[_tapped[i]] : '']),
                    _gap(context, 4),
                    Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
                      for (var i = 0; i < _shuffled.length; i++) _WordChip(word: _shuffled[i], used: _tapped.contains(i), onPressed: () => _tap(i)),
                    ]),
                  ]),
                ),
              ],
            )
          else
            PaneSection(
              title: 'Type three of them',
              footer: _problemText(context, _problem),
              children: [for (var i = 0; i < 3; i++) _field(_three[i], 'Word ${_asked[i] + 1}', 'Word ${_asked[i] + 1}')],
            ),
          _gap(context, 3),
          PaneSection(children: [
            SettingRow(
              icon: _icon(_typed ? Lucide.pencil : Lucide.pencilLine),
              label: _typed ? 'Tap all twelve instead' : 'Type three of them instead',
              onPress: () => setState(() {
                _typed = !_typed;
                _problem = null;
              }),
            ),
            SettingRow(icon: _icon(Lucide.rotateCcw), label: 'See the words again', onPress: () => setState(() => _step = CreateStep.words)),
            SettingRow(
              key: const ValueKey('skip-word-check'),
              icon: _icon(Lucide.chevronRight),
              label: 'Skip this check',
              hint: const Text('See your words again any time in Settings › Me'),
              onPress: _skipCheck,
            ),
          ]),
          _gap(context, 8),
          PairButton(label: widget.made ? 'Done' : 'Create my account', icon: Lucide.check, onPressed: _confirmed ? _make : null),
        ]);
      case CreateStep.working:
        return _AccountPage(title: 'Create an account', children: [
          _gap(context, 10),
          Center(child: Text('Sealing your backup…', style: pageText(t, t.fontSize('lg'), weight: 'medium', color: t.color('app-ink')))),
          _gap(context, 2),
          Center(child: Text('Your password is stretched on this device first; it takes a moment.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2')))),
        ]);
      case CreateStep.done:
        return _AccountPage(title: 'Your account', children: [
          PaneSection(
            title: 'Your account is ready',
            description: const Text('This is its address. It is yours alone, and it is the same in any wallet that takes your recovery words.'),
            children: [
              Padding(padding: EdgeInsets.all(t.space(4)), child: AddressBlock(address: _draft.address)),
              SettingRow(icon: _icon(Lucide.copy), label: 'Copy address', onPress: () {
                Clipboard.setData(ClipboardData(text: _draft.address));
                toast(context, 'Address copied');
              }),
            ],
          ),
          _gap(context, 8),
          PairButton(
            label: _restart ? 'Start Ghost Messaging as your account' : 'Done',
            icon: _restart ? Lucide.rotateCcw : Lucide.check,
            onPressed: () async {
              if (!_restart) return Navigator.of(context).pop();
              final again = await Account.instance.restart();
              if (!again && context.mounted) await push<void>(context, (_) => const RestartScreen());
            },
          ),
        ]);
    }
  }
}

// --- signing in --------------------------------------------------------------------------------------------------------

/// Signing in on this device: username and password (and the code texted to the account's number, where it has a
/// verified one), or the recovery words. What is found replaces this install's identity and the app starts again.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.words = false, this.needsCode = false, this.needsPassword = false, this.username = ''});

  /// The username typed in to start with: the phone's account's, on a computer paired with it.
  final String username;

  /// Starting on the words' tab, or at the texted code, or at a new password: for the pictures.
  final bool words;
  final bool needsCode;
  final bool needsPassword;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late bool _words = widget.words;
  late final _username = TextEditingController(text: widget.username);
  final _password = TextEditingController();
  final _number = TextEditingController();
  final _code = TextEditingController();
  final _typedWords = TextEditingController();
  // The account has a verified number, so a texted code is asked for too; and whether one has been sent yet.
  late bool _needsCode = widget.needsCode;
  bool _sent = false;
  // An account opened by its words with no backup on the server: held here while a new password is chosen.
  AccountRestore? _restored;
  late bool _needsPassword = widget.needsPassword;
  final _newPassword = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_username, _password, _number, _code, _typedWords, _newPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Runs one step of signing in with the buttons off: what it throws is shown as the problem, and an account that
  /// wants a texted code opens the number's section instead.
  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await work();
    } on AccountNeedsCode {
      if (mounted) setState(() => _needsCode = true);
    } catch (e) {
      if (mounted) setState(() => _problem = e is AccountError ? e.message : 'That did not work. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Username and password, with the number and its code once they have been asked for.
  Future<void> _withPassword() => _run(() async {
        final name = tidyHandle(_username.text);
        if (!Me.goodUsername(name)) throw AccountError('That isn\'t a username.');
        if (_password.text.isEmpty) throw AccountError('Type your password.');
        if (_needsCode && _code.text.trim().isEmpty) throw AccountError('Type the code from the text.');
        final restore = await Account.instance.signInWithPassword(name, _password.text, number: _needsCode ? _number.text : null, code: _needsCode ? _code.text.trim() : null);
        await _finish(restore);
      });

  /// Asks for a code to be texted to the number typed.
  Future<void> _text() => _run(() async {
        await Account.instance.textCode(tidyHandle(_username.text), _number.text);
        if (mounted) setState(() => _sent = true);
      });

  /// The recovery words: each checked against the word list before anything is asked of the server. An account with
  /// no backup kept goes on to choosing a password, so one is kept again.
  Future<void> _withWords() => _run(() async {
        final words = AccountCrypto.tidyWords(_typedWords.text);
        final strange = words.where((w) => !AccountCrypto.isWord(w)).toList();
        if (strange.isNotEmpty) throw AccountError('"${strange.first}" isn\'t one of the recovery words. Check its spelling.');
        if (words.length != 12 && words.length != 24) throw AccountError('That is ${words.length} words. There are 12.');
        final restore = await Account.instance.signInWithWords(words);
        if (!restore.backedUp) {
          setState(() {
            _restored = restore;
            _needsPassword = true;
          });
          return;
        }
        await _finish(restore);
      });

  Future<void> _withNewPassword() => _run(() async {
        if (_newPassword.text.length < minPassword) throw AccountError('A password is at least $minPassword characters.');
        await _finish(_restored!, password: _newPassword.text);
      });

  /// Makes this device the account found, and starts the app again (or shows how to, where it can't itself).
  Future<void> _finish(AccountRestore restore, {String? password}) async {
    // On a computer paired with a phone this computer is the phone's identity; an account with another one splits
    // them, to everyone who writes, into two people (Matt, 2026-11-18: "messages from desktop are coming through
    // differently than messages on mobile even though they're both me"). Asked first.
    if (Sms.paired && await Account.instance.wouldChangeIdentity(restore)) {
      if (!mounted) return;
      final phones = phoneAccountHere();
      var go = false;
      await showChoices(
        context,
        title: phones != null && phones.address.toLowerCase() != restore.address.toLowerCase()
            ? 'This isn\'t the account your phone is in. Signed in to it, this computer and your phone are different people to your friends: messages from each come from someone else.'
            : 'This account is someone other than your phone. Signed in to it, this computer and your phone are different people to your friends: messages from each come from someone else.',
        choices: [Choice('Sign in anyway', Lucide.keyRound, () => go = true, danger: true)],
      );
      if (!go) return;
    }
    final again = await Account.instance.finish(restore, password: password);
    if (!again && mounted) await Navigator.of(context).pushReplacement(PageRouteBuilder<void>(pageBuilder: (_, _, _) => const RestartScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;
    final tabs = Padding(
      padding: EdgeInsets.only(bottom: context.tokens.space(4)),
      child: GlacierSegmentedControl(
        fullWidth: true,
        value: _words ? 'words' : 'password',
        ariaLabel: 'How to sign in',
        onValueChange: (v) => setState(() {
          _words = v == 'words';
          _problem = null;
        }),
        options: const [
          GlacierSegmentedOption(value: 'password', label: Text('Username')),
          GlacierSegmentedOption(value: 'words', label: Text('Recovery words')),
        ],
      ),
    );
    final warning = SettingsCallout(
      icon: _icon(Lucide.smartphone),
      child: const Text('Signing in makes this device your account. Anything on it from before, as someone else, is replaced, and the app starts again.'),
    );
    if (_needsPassword) {
      return _AccountPage(title: 'Sign in', children: [
        PaneSection(
          title: 'Choose a password',
          description: const Text('Your words opened your account, but no backup of it was found on the server. Choose a password to keep one again, so you can sign in with your username next time.'),
          footer: _problemText(context, _problem),
          children: [_field(_newPassword, 'New password', 'New password', secret: true, autofill: 'new-password', onSubmitted: (_) => _withNewPassword())],
        ),
        _gap(context, 8),
        PairButton(label: busy ? 'Signing in…' : 'Sign in', icon: Lucide.arrowRight, onPressed: busy ? null : _withNewPassword),
      ]);
    }
    if (_words) {
      return _AccountPage(title: 'Sign in', children: [
        tabs,
        PaneSection(
          title: 'Your recovery words',
          description: const Text('The 12 words you wrote down, in order, with spaces between. No password or code is needed.'),
          footer: _problemText(context, _problem),
          children: [
            SettingRowBox(
              child: GlacierInput(controller: _typedWords, placeholder: 'word word word …', ariaLabel: 'Recovery words', autoCorrect: false, spellCheck: false, autoCapitalize: TextCapitalization.none, size: GlacierFieldSize.md, onSubmitted: (_) => _withWords()),
            ),
          ],
        ),
        _gap(context),
        warning,
        _gap(context, 8),
        PairButton(label: busy ? 'Opening your account…' : 'Sign in', icon: Lucide.arrowRight, onPressed: busy ? null : _withWords),
      ]);
    }
    return _AccountPage(title: 'Sign in', children: [
      tabs,
      PaneSection(
        title: 'Your account',
        footer: _needsCode ? null : _problemText(context, _problem),
        children: [
          _field(_username, 'username', 'Username', autofill: 'username'),
          _field(_password, 'Password', 'Password', secret: true, autofill: 'current-password', onSubmitted: (_) => _withPassword()),
        ],
      ),
      if (_needsCode) ...[
        _gap(context),
        PaneSection(
          title: 'Your number',
          description: const Text('This account has a verified number. Type it, and a code is texted to it to show it\'s you.'),
          footer: _problemText(context, _problem),
          children: [
            _field(_number, '+1 555 010 0199', 'Phone number', keyboard: TextInputType.phone, autofill: 'tel'),
            SettingRow(icon: _icon(Lucide.messageSquare), label: _sent ? 'Text me another code' : 'Text me a code', disabled: busy, onPress: _text),
            if (_sent) _field(_code, 'Code', 'Code from the text', keyboard: TextInputType.number, autofill: 'one-time-code', onSubmitted: (_) => _withPassword()),
          ],
        ),
      ],
      _gap(context),
      warning,
      _gap(context, 8),
      PairButton(label: busy ? 'Signing in…' : 'Sign in', icon: Lucide.arrowRight, onPressed: busy || (_needsCode && !_sent) ? null : _withPassword),
    ]);
  }
}

/// Shown where the app cannot start itself again (an iPhone): the person closes it and opens it again.
class RestartScreen extends StatelessWidget {
  const RestartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(t.space(8)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _icon(Lucide.rotateCcw),
            _gap(context, 4),
            Text('Open Ghost Messaging again', textAlign: TextAlign.center, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink'))),
            _gap(context, 2),
            Text('Swipe it away from the app switcher and open it again to finish. Until then it stays offline, so nothing is sent as the device you were before.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45)),
          ]),
        ),
      ),
    );
  }
}

// --- on a signed-in device -----------------------------------------------------------------------------------------------

/// The recovery words again, after the password.
class ShowWordsScreen extends StatefulWidget {
  const ShowWordsScreen({super.key, this.words});
  final List<String>? words;

  @override
  State<ShowWordsScreen> createState() => _ShowWordsScreenState();
}

class _ShowWordsScreenState extends State<ShowWordsScreen> {
  final _password = TextEditingController();
  late List<String>? _words = widget.words;
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final words = await Account.instance.revealWords(_password.text);
      if (mounted) setState(() => _words = words);
    } catch (e) {
      if (mounted) setState(() => _problem = e is AccountError ? e.message : 'That did not work.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    if (words != null) {
      return _AccountPage(title: 'Recovery words', children: [
        PaneSection(
          title: 'Your recovery words',
          description: const Text('Make sure nobody can see your screen. Write them down in this order.'),
          children: [Padding(padding: EdgeInsets.all(context.tokens.space(3)), child: RecoveryWordsGrid(words: words))],
        ),
      ]);
    }
    return _AccountPage(title: 'Recovery words', children: [
      PaneSection(
        title: 'Your password first',
        footer: _problemText(context, _problem),
        children: [_field(_password, 'Password', 'Password', secret: true, autofill: 'current-password', onSubmitted: (_) => _open())],
      ),
      _gap(context, 8),
      PairButton(label: _busy ? 'Opening…' : 'Show my words', icon: Lucide.eye, onPressed: _busy ? null : _open),
    ]);
  }
}

/// A new password, after the one now: the backup is sealed again with it and the recovery words stay as they are.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_next.text.length < minPassword) return setState(() => _problem = 'A password is at least $minPassword characters.');
    if (_next.text != _again.text) return setState(() => _problem = 'The two new passwords are not the same.');
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await Account.instance.changePassword(_old.text, _next.text);
      if (mounted) {
        toast(context, 'Password changed');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _problem = e is AccountError ? e.message : 'That did not work.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AccountPage(title: 'Change password', children: [
        PaneSection(
          title: 'Your password now',
          children: [_field(_old, 'Password', 'Password now', secret: true, autofill: 'current-password')],
        ),
        _gap(context),
        PaneSection(
          title: 'A new one',
          description: const Text('Your backup is sealed again with it. Your recovery words stay the same.'),
          footer: _problemText(context, _problem),
          children: [
            _field(_next, 'New password', 'New password', secret: true, autofill: 'new-password'),
            _field(_again, 'The same again', 'The new password again', secret: true, autofill: 'new-password', onSubmitted: (_) => _change()),
          ],
        ),
        _gap(context, 8),
        PairButton(label: _busy ? 'Sealing…' : 'Change password', icon: Lucide.lock, onPressed: _busy ? null : _change),
      ]);
}

/// The devices signed in to the account, this one first; any other can be removed.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.devices});

  /// The list to start from, for the pictures; otherwise it is asked of the relay.
  final List<AccountDevice>? devices;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late List<AccountDevice>? _list = widget.devices;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (_list == null) _load(Account.instance.devices);
  }

  /// Shows the list [ask] answers with: the account's devices as asked for, or as left after removing one.
  Future<void> _load(Future<List<AccountDevice>> Function() ask) async {
    try {
      final list = await ask();
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) setState(() => _problem = e is AccountError ? e.message : 'The list could not be read.');
    }
  }

  static LucideIcon _iconOf(String platform) => platform == 'android' || platform == 'ios' ? Lucide.smartphone : Lucide.laptop;

  @override
  Widget build(BuildContext context) {
    final list = [...?_list]..sort((a, b) => a.here == b.here ? 0 : (a.here ? -1 : 1));
    return _AccountPage(title: 'Devices', children: [
      PaneSection(
        title: 'Signed in on these devices',
        description: const Text('Each one is your account. Remove one you no longer have: it is signed out the next time it connects.'),
        footer: _problem != null ? _problemText(context, _problem) : _list == null ? const Text('Asking the relay server…') : null,
        children: [
          for (final d in list)
            SettingRow(
              icon: _icon(_iconOf(d.platform)),
              label: d.name.isEmpty ? 'A device' : d.name,
              hint: Text(d.here ? 'This device' : 'Last seen ${d.seen}'),
              onPress: d.here
                  ? null
                  : () => showChoices(context, title: 'Remove ${d.name.isEmpty ? 'this device' : d.name} from your account?', choices: [
                        Choice('Remove', Lucide.trash2, () => _load(() => Account.instance.removeDevice(d.id)), danger: true),
                      ]),
            ),
        ],
      ),
      _gap(context),
      // Every device signed in is connected at once since the hub keeps each of a name's devices (relay/lib/hub.dart).
      const SettingsCallout(child: Text('Every device signed in is connected as your account at once, and each gets what is sent to you.')),
    ]);
  }
}
