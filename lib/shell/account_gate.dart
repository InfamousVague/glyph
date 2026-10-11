import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/ui_state.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../settings/kit/settings_kit.dart' show SettingsWord;
import '../settings/panes/account_pane.dart' show SignInFlow;
import '../settings/panes/settings_host.dart' show SettingsWayIn;
import '../sheet/css.dart';

/// The key the gate's "seen" is kept under on this device (`glyph-account-gate-seen`).
const String accountGateSeenKey = 'glyph-account-gate-seen';

/// Whether the way into an account is the first thing on screen. A port of `src/app/shell/useAccountGate.ts`
/// (Matt: "move the login / signup flow to the first thing that happens when you open the app"). It comes up by
/// itself, before the walkthrough, on an open that is signed out - once: signing in, making an account or choosing
/// to use the app without one marks it seen, and after that the way in is Settings › Account, as before.
///
/// Not for a person already signed in, nor one who chose Local only (nothing would sync, so asking would only be in
/// the way), nor an open by the side key, who is already mid-sentence.
///
/// What differs from the web original: it is an object made once as the app starts, with the [AccountServices]
/// (whose account must already have read what this device kept: `Account.restore`) and the device's memory, where
/// the page's is a hook reading its modules. With no services there is no account to sign in to, and the gate
/// stays shut. Storage that cannot be read counts as seen: asking on every open would be worse than never asking.
class AccountGateState extends ChangeNotifier {
  AccountGateState({required AccountServices? services, bool launchedByKey = false, Stored? kept, PreferencesStore? prefs})
      // No storage: asking on every open would be worse than never asking.
      : _seen = (kept ?? services?.kept ?? stored).flag(accountGateSeenKey, value: '1', unreadable: true) {
    _open = services != null && !_seen.isMarked && !launchedByKey && !services.signedIn && !(prefs ?? services.prefs).value.localOnly;
  }

  final StoredFlag _seen;
  late bool _open;

  bool get open => _open;

  /// Closed and seen: signed in, or going on without an account.
  void close() {
    _seen.mark();
    if (!_open) return;
    _open = false;
    notifyListeners();
  }
}

/// The first screen on open, while signed out. A port of `src/app/shell/AccountGate.tsx` with
/// AccountGate.module.css: the way into an account - sign in, make one, or recover one - over everything, as one
/// plain card that asks you to sign in or sign up ([SignInFlow], whose form is the Account page's own, so the
/// checks and the recovery codes are the same in both places).
///
/// An account is not needed: notes live on the device either way, so the last line goes on without one, and the
/// way in stays in Settings › Account.
///
/// What differs from the web original: the strip that drags the Mac's window (`data-tauri-drag-region`) is the
/// desktop shell's to add (stage 10).
class AccountGate extends StatelessWidget {
  const AccountGate({super.key, required this.services, this.onWayIn, required this.onDone});

  final AccountServices? services;

  /// A way in of the page's own, where there are no [services].
  final SettingsWayIn? onWayIn;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final column = t.lenOf('26rem');
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Sign in to Ghost.md',
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            key: const ValueKey('account-gate-scroll'),
            child: ConstrainedBox(
              // `.column { min-block-size: 100% }`: the card in the middle of the screen until it is taller than it.
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: column),
                  child: Padding(
                    // `padding-inline: var(--app-gutter-start) var(--app-gutter-end);
                    //  padding-block: calc(var(--app-inset-top) + var(--glacier-space-12)) var(--glacier-space-12)`
                    padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), t.len('app-inset-top') + t.space(12), t.len('app-gutter-end'), t.space(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SignInFlow(services: services, onWayIn: onWayIn, onIn: onDone),
                        // `gap: var(--glacier-space-3)` and the word's own `margin-block-start: var(--glacier-space-2)`.
                        SizedBox(height: t.space(3) + t.space(2)),
                        Align(
                          child: DefaultTextStyle(
                            style: pageText(t, t.lenOf('1rem'), color: t.color('glacier-text')),
                            child: SettingsWord(key: const ValueKey('account-gate-skip'), onPressed: onDone, child: const Text('Use without an account')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
