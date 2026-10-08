/// What a take (capture/take.dart) asks of whoever runs it, and what it tells them; and what the chip at the foot of
/// the recorder says, which the live reader (live_route.dart) tells it too. A port of `src/app/capture/takeHost.ts`.
///
/// The take has no screen: its host shows and does. The recorder runs one over the real notes, and a test of the
/// take passes one that does nothing until told (test/capture/support/take_host.dart). The chip and the card after
/// Done are the host's to draw from what arrives here; the notes are the host's to change when the card is tapped.
///
/// What differs: the shapes. `RouteView` is a sealed class with one subclass per `phase` ([RouteViewHearing],
/// [RouteViewDone], [RouteViewCommand], [RouteViewSaid], [RouteViewWaiting], [RouteViewAdded], [RouteViewMoved],
/// [RouteViewMissed], [RouteViewTookBack]), and null where the web's union has null. A take-back's `outcome` -
/// `'gone'` or an object with one of `sent`, `placed`, `changed`, `replaced` - is a sealed [TookBackOutcome].
/// `Haptic` is an enum. `TakeHost` is an interface to implement, generic in any note (see take_types.dart). The web's
/// `hostThrough` is a `Proxy` over a React ref; here the ref is a [TakeHostRef] and the host it answers forwards
/// each member to whatever the ref holds at the moment of the call.
library;

import 'command.dart' show Placement;
import 'offers.dart' show Offer;

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What the chip at the foot of the recorder says (`RouteView`, less its null).
sealed class RouteView {
  const RouteView();

  /// The web's `phase`: `hearing`, `done`, `command`, `said`, `waiting`, `added`, `moved`, `missed` or `tookBack`.
  String get phase;
}

/// A command held for its note's name: the name heard so far.
final class RouteViewHearing extends RouteView {
  const RouteViewHearing({required this.name});

  final String name;

  @override
  String get phase => 'hearing';

  @override
  bool operator ==(Object other) => other is RouteViewHearing && other.name == name;

  @override
  int get hashCode => Object.hash(phase, name);

  @override
  String toString() => '{phase: hearing, name: $name}';
}

/// `phase: 'done'`.
final class RouteViewDone extends RouteView {
  const RouteViewDone({required this.text});

  final String text;

  @override
  String get phase => 'done';

  @override
  bool operator ==(Object other) => other is RouteViewDone && other.text == text;

  @override
  int get hashCode => Object.hash(phase, text);

  @override
  String toString() => '{phase: done, text: $text}';
}

/// The keyword heard, and the words of the command after it so far.
final class RouteViewCommand extends RouteView {
  const RouteViewCommand({required this.words});

  final String words;

  @override
  String get phase => 'command';

  @override
  bool operator ==(Object other) => other is RouteViewCommand && other.words == words;

  @override
  int get hashCode => Object.hash(phase, words);

  @override
  String toString() => '{phase: command, words: $words}';
}

/// `phase: 'said'`.
final class RouteViewSaid extends RouteView {
  const RouteViewSaid({required this.text});

  final String text;

  @override
  String get phase => 'said';

  @override
  bool operator ==(Object other) => other is RouteViewSaid && other.text == text;

  @override
  int get hashCode => Object.hash(phase, text);

  @override
  String toString() => '{phase: said, text: $text}';
}

/// A note named with nothing said for it yet: what is said next goes there.
final class RouteViewWaiting extends RouteView {
  const RouteViewWaiting({required this.title});

  final String title;

  @override
  String get phase => 'waiting';

  @override
  bool operator ==(Object other) => other is RouteViewWaiting && other.title == title;

  @override
  int get hashCode => Object.hash(phase, title);

  @override
  String toString() => '{phase: waiting, title: $title}';
}

/// Words landed in another note's list; [insert] is the live reader's one-shot, which its Not this note takes out
/// again.
final class RouteViewAdded extends RouteView {
  const RouteViewAdded({required this.title, required this.body, required this.added, this.insert});

  final String title;
  final String body;
  final List<String> added;
  final int? insert;

  @override
  String get phase => 'added';

  @override
  bool operator ==(Object other) =>
      other is RouteViewAdded && other.title == title && other.body == body && _sameList(other.added, added) && other.insert == insert;

  @override
  int get hashCode => Object.hash(phase, title, body, Object.hashAll(added), insert);

  @override
  String toString() => '{phase: added, title: $title, body: $body, added: $added${insert == null ? '' : ', insert: $insert'}}';
}

/// The words went to a note, and carry on there; [spot] says where in it ("under Electrical").
final class RouteViewMoved extends RouteView {
  const RouteViewMoved({required this.title, this.spot});

  final String title;
  final String? spot;

  @override
  String get phase => 'moved';

  @override
  bool operator ==(Object other) => other is RouteViewMoved && other.title == title && other.spot == spot;

  @override
  int get hashCode => Object.hash(phase, title, spot);

  @override
  String toString() => '{phase: moved, title: $title${spot == null ? '' : ', spot: $spot'}}';
}

/// `phase: 'missed'`.
final class RouteViewMissed extends RouteView {
  const RouteViewMissed({required this.title});

  final String title;

  @override
  String get phase => 'missed';

  @override
  bool operator ==(Object other) => other is RouteViewMissed && other.title == title;

  @override
  int get hashCode => Object.hash(phase, title);

  @override
  String toString() => '{phase: missed, title: $title}';
}

/// What a take-back came to: gone, or where the words went instead or what they became.
sealed class TookBackOutcome {
  const TookBackOutcome();
}

/// The web's `'gone'`.
final class TookBackGone extends TookBackOutcome {
  const TookBackGone();

  @override
  bool operator ==(Object other) => other is TookBackGone;

  @override
  int get hashCode => 'gone'.hashCode;

  @override
  String toString() => 'gone';
}

/// The web's `{ sent }`: sent to a note.
final class TookBackSent extends TookBackOutcome {
  const TookBackSent({required this.sent});

  final String sent;

  @override
  bool operator ==(Object other) => other is TookBackSent && other.sent == sent;

  @override
  int get hashCode => Object.hash('sent', sent);

  @override
  String toString() => '{sent: $sent}';
}

/// The web's `{ placed }`: put in this note's list.
final class TookBackPlaced extends TookBackOutcome {
  const TookBackPlaced({required this.placed});

  final String placed;

  @override
  bool operator ==(Object other) => other is TookBackPlaced && other.placed == placed;

  @override
  int get hashCode => Object.hash('placed', placed);

  @override
  String toString() => '{placed: $placed}';
}

/// The web's `{ changed }`: one word changed.
final class TookBackChanged extends TookBackOutcome {
  const TookBackChanged({required this.changed});

  final String changed;

  @override
  bool operator ==(Object other) => other is TookBackChanged && other.changed == changed;

  @override
  int get hashCode => Object.hash('changed', changed);

  @override
  String toString() => '{changed: $changed}';
}

/// The web's `{ replaced }`: replaced by the sentence said again.
final class TookBackReplaced extends TookBackOutcome {
  const TookBackReplaced({required this.replaced});

  final String replaced;

  @override
  bool operator ==(Object other) => other is TookBackReplaced && other.replaced == replaced;

  @override
  int get hashCode => Object.hash('replaced', replaced);

  @override
  String toString() => '{replaced: $replaced}';
}

/// The last thing said, taken back (live_route.dart `takeBack`): what went, where it went instead or what it became
/// (sent to a note, put in this note's list, one word changed, or replaced by the sentence said again), and the
/// take-back's id for its Undo; none when there is nothing to put back (a command cancelled).
final class RouteViewTookBack extends RouteView {
  const RouteViewTookBack({required this.said, required this.outcome, this.undo});

  final String said;
  final TookBackOutcome outcome;
  final int? undo;

  @override
  String get phase => 'tookBack';

  @override
  bool operator ==(Object other) => other is RouteViewTookBack && other.said == said && other.outcome == outcome && other.undo == undo;

  @override
  int get hashCode => Object.hash(phase, said, outcome, undo);

  @override
  String toString() => '{phase: tookBack, said: $said, outcome: $outcome${undo == null ? '' : ', undo: $undo'}}';
}

/// The feel a take asks for (`Haptic`).
enum Haptic { light, selection, success, warning }

/// What the take asks of whoever runs it.
abstract interface class TakeHost<N extends Object> {
  void route(RouteView? view);
  void offer(Offer<N>? offer);
  void haptic(Haptic kind);

  /// The take's words changed.
  void changed();

  /// Add, tapped on a place offer: the words into that note.
  void addItems(N note, String spoken, Placement placement);
}

/// What holds the host of the moment: the web's `{ readonly current: TakeHost<N> }`, a React ref.
class TakeHostRef<N extends Object> {
  TakeHostRef(this.current);

  TakeHost<N> current;
}

/// A host that is always the one [ref] holds now.
///
/// The recorder makes its take once, but its host is new with every render, because each render's functions see that
/// render's state. So the take is given this instead, which looks each member up on the ref at the moment the take
/// uses it: a method is always the newest render's.
TakeHost<N> hostThrough<N extends Object>(TakeHostRef<N> ref) => _HostThrough<N>(ref);

class _HostThrough<N extends Object> implements TakeHost<N> {
  _HostThrough(this._ref);

  final TakeHostRef<N> _ref;

  @override
  void route(RouteView? view) => _ref.current.route(view);

  @override
  void offer(Offer<N>? offer) => _ref.current.offer(offer);

  @override
  void haptic(Haptic kind) => _ref.current.haptic(kind);

  @override
  void changed() => _ref.current.changed();

  @override
  void addItems(N note, String spoken, Placement placement) => _ref.current.addItems(note, spoken, placement);
}
