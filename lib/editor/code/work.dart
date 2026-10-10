/// What the editor asks of a language to colour a block of code, whatever reads it: a Lezer grammar
/// (`lr_language.dart`) or one of CodeMirror's older line-by-line modes (`stream/stream_language.dart`).
///
/// A [CodeLanguage] starts a [CodeWork] on a block's text. The work is done in pieces: [CodeWork.work] reads on
/// until the lines asked for are read or its [Budget] is spent, and [CodeWork.spans] gives the classes of what is
/// read so far. So a long block is coloured from its first visible line within a frame, and the rest in the
/// pauses after (`code_highlight.dart`), which is what CodeMirror does with its parse: twenty milliseconds as a
/// change is applied, then slices while the page is idle (@codemirror/language `Work.Apply`, `Work.Slice`).
///
/// When a block's text changes, [CodeLanguage.resume] takes up the old work where the two texts still agree,
/// rather than reading the block again from its first line.
library;

/// Where a run of classes is sent: from, to, and the classes, space between them.
typedef SpanSink = void Function(int from, int to, String cls);

/// The work done, counted, for a test to hold the editor to: a block is read when its own text changes, and
/// then only from where it changed.
abstract final class CodeStats {
  /// Blocks read from their first character.
  static int started = 0;

  /// Blocks taken up again from where their text changed.
  static int resumed = 0;

  /// The characters read, all told.
  static int read = 0;

  /// The times an older mode would not move along its line, and was stepped past a character.
  static int stuck = 0;

  static void reset() => started = resumed = read = stuck = 0;
}

/// How long a piece of work may take. `null` microseconds is as long as it needs.
class Budget {
  Budget(this.microseconds) : _watch = microseconds == null ? null : (Stopwatch()..start());

  /// No limit: for a test, and for a block short enough not to need one.
  Budget.none() : microseconds = null, _watch = null;

  final int? microseconds;
  final Stopwatch? _watch;

  bool get spent => _watch != null && _watch.elapsedMicroseconds >= microseconds!;
}

/// A language the editor can colour.
abstract class CodeLanguage {
  const CodeLanguage(this.name);

  /// The language's name in the language pack: `JavaScript`, `C++`.
  final String name;

  /// Work on `code`, from its start, nothing read yet.
  CodeWork start(String code);

  /// Work on `code`, standing on what `old` read of an earlier text of the same block where the two agree.
  CodeWork resume(CodeWork old, String code) => start(code);
}

/// The reading of one block of code, as far as it has got.
abstract class CodeWork {
  CodeLanguage get language;

  /// The block's text.
  String get code;

  /// The code before this position is read.
  int get parsedTo;

  /// Whether all of the block is read, and everything in it that is another language's.
  bool get done;

  /// Reads on until the code before `upTo` is read, the end is reached, or `budget` is spent.
  void work(int upTo, Budget budget);

  /// The classes of the code between `from` and `to`, as far as it is read: one call for each run with a class,
  /// in order. `inherited` is the class the block starts with.
  /// Where the block holds another language's code (a script in a page), that is read as it is met, within
  /// `budget` when one is given; what was left unread shows in [done].
  void spans(int from, int to, SpanSink sink, {String inherited = '', Budget? budget});
}
