/// Words in the order the page puts them. The web's query core sorts and compares with `String.localeCompare`
/// (`core/query/values.ts` `textOrder`, `core/query/run.ts` `sorted`, `book/tickets.ts` `peopleIn`), which is the
/// browser's collation; Dart has none, so this is that order written down for what a note is made of.
///
/// Not a port of a web file: it stands in for ICU. What it keeps, measured against Node's `Intl.Collator` in the
/// device's English (tool/query_fixtures.mjs writes the pairs, test/query/fixtures_test.dart holds this to them):
///
/// - spaces, then punctuation and signs in the collation's own order (`_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # %
///   ` ^ + < = > | ~`), then currency, then figures, then letters;
/// - letters by the alphabet first, an accent only where the letters are the same, and case only where the accents
///   are too, the small letter first (`a`, `A`, `á`, `b`);
/// - `ß`, `æ` and `œ` as the two letters they stand for;
/// - with [numeric], a run of figures by the number it writes, so `GHO-9` is before `GHO-10` and `02` is `2`;
/// - with [base], only the alphabet's order: `Résumé` and `resume` are the same word.
///
/// What it does not: scripts other than Latin are in their code points' order after it, not their own alphabets';
/// a language's own rules (Swedish `å` after `z`) are not read, since the page asks the device's language and this
/// app has no table for one.
library;

/// Spaces and control characters that are spaces, in order.
const String _spaces = '\t\n\u000b\u000c\r\u0085\u2028\u2029 \u00a0';

/// Punctuation and signs, in the collation's order.
const String _signs =
    '_-‐‑‒–—,;:!¡?¿.…·\'"«»()[]{}§¶@*/\\&#%‰†‡•′″`^°©®←→+±÷×<=≠>¬|¦~√∞≤≥';

/// Quotes a phone types for the keyboard's: each the same sign as the straight one, told apart only as case is.
const Map<String, String> _curly = {"'": '‘’‚', '"': '“”„'};

const String _currency = r'¢$£¥€';

/// Letters with a mark over or under them, and the letter each is at the alphabet's level.
const String _marked =
    'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿĀāĂăĄąĆćĈĉĊċČčĎďĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžƠơƯưǍǎǏǐǑǒǓǔǕǖǗǘǙǚǛǜǞǟǠǡǦǧǨǩǪǫǬǭǰǴǵǸǹǺǻȀȁȂȃȄȅȆȇȈȉȊȋȌȍȎȏȐȑȒȓȔȕȖȗȘșȚțȞȟȦȧȨȩȪȫȬȭȮȯȰȱȲȳḀḁḂḃḄḅḆḇḈḉḊḋḌḍḎḏḐḑḒḓḔḕḖḗḘḙḚḛḜḝḞḟḠḡḢḣḤḥḦḧḨḩḪḫḬḭḮḯḰḱḲḳḴḵḶḷḸḹḺḻḼḽḾḿṀṁṂṃṄṅṆṇṈṉṊṋṌṍṎṏṐṑṒṓṔṕṖṗṘṙṚṛṜṝṞṟṠṡṢṣṤṥṦṧṨṩṪṫṬṭṮṯṰṱṲṳṴṵṶṷṸṹṺṻṼṽṾṿẀẁẂẃẄẅẆẇẈẉẊẋẌẍẎẏẐẑẒẓẔẕẖẗẘẙẠạẢảẤấẦầẨẩẪẫẬậẮắẰằẲẳẴẵẶặẸẹẺẻẼẽẾếỀềỂểỄễỆệỈỉỊịỌọỎỏỐốỒồỔổỖỗỘộỚớỜờỞởỠỡỢợỤụỦủỨứỪừỬửỮữỰựỲỳỴỵỶỷỸỹ';
const String _unmarked =
    'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyyAaAaAaCcCcCcCcDdEeEeEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLlNnNnNnOoOoOoRrRrRrSsSsSsSsTtTtUuUuUuUuUuUuWwYyYZzZzZzOoUuAaIiOoUuUuUuUuUuAaAaGgKkOoOojGgNnAaAaAaEeEeIiIiOoOoRrRrUuUuSsTtHhAaEeOoOoOoOoYyAaBbBbBbCcDdDdDdDdDdEeEeEeEeEeFfGgHhHhHhHhHhIiIiKkKkKkLlLlLlLlMmMmMmNnNnNnNnOoOoOoOoPpPpRrRrRrRrSsSsSsSsSsTtTtTtTtUuUuUuUuUuVvVvWwWwWwWwWwXxXxYyZzZzZzhtwyAaAaAaAaAaAaAaAaAaAaAaAaEeEeEeEeEeEeEeEeIiIiOoOoOoOoOoOoOoOoOoOoOoOoUuUuUuUuUuUuUuYyYyYyYy';

/// Letters that are another letter with a stroke, or two letters written as one.
const Map<String, String> _also = {
  'ß': 'ss', 'ẞ': 'SS', 'æ': 'ae', 'Æ': 'AE', 'œ': 'oe', 'Œ': 'OE', 'ø': 'o', 'Ø': 'O', 'đ': 'd', 'Đ': 'D', 'ð': 'd', 'Ð': 'D', 'ł': 'l', 'Ł': 'L', 'ı': 'i', 'ª': 'a', 'º': 'o', //
};

// Where each class starts at the alphabet's level. A run of figures read as a number is `_figures`, how many
// figures, then each.
const int _signsAt = 100;
const int _otherSignsAt = 1000;
const int _currencyAt = 0x200000;
const int _figures = 0x200100;
const int _otherFiguresAt = 0x200200;
const int _lettersAt = 0x400000;
const int _otherLettersAt = 0x400100;

final Map<int, List<(int, int, int)>> _known = () {
  final known = <int, List<(int, int, int)>>{};
  for (var i = 0; i < _spaces.length; i += 1) {
    known[_spaces.codeUnitAt(i)] = [(1 + i, 0, 0)];
  }
  final signs = _signs.runes.toList();
  for (var i = 0; i < signs.length; i += 1) {
    known[signs[i]] = [(_signsAt + i, 0, 0)];
  }
  for (final MapEntry(key: straight, value: others) in _curly.entries) {
    final at = known[straight.codeUnitAt(0)]!.first.$1;
    final curly = others.runes.toList();
    for (var i = 0; i < curly.length; i += 1) {
      known[curly[i]] = [(at, 0, 1 + i)];
    }
  }
  final currency = _currency.runes.toList();
  for (var i = 0; i < currency.length; i += 1) {
    known[currency[i]] = [(_currencyAt + i, 0, 0)];
  }
  for (var d = 0; d < 10; d += 1) {
    known[0x30 + d] = [(_figures + 1 + d, 0, 0)];
  }
  (int, int, int) letter(int unit, int mark) {
    final upper = unit >= 0x41 && unit <= 0x5a;
    return (_lettersAt + (upper ? unit - 0x41 : unit - 0x61), mark, upper ? 1 : 0);
  }

  for (var c = 0; c < 26; c += 1) {
    known[0x61 + c] = [letter(0x61 + c, 0)];
    known[0x41 + c] = [letter(0x41 + c, 0)];
  }
  final marked = _marked.runes.toList();
  for (var i = 0; i < marked.length; i += 1) {
    // The mark is the same whichever case wears it, so `é` and `É` differ by case alone.
    known[marked[i]] = [letter(_unmarked.codeUnitAt(i), String.fromCharCode(marked[i]).toLowerCase().runes.first)];
  }
  for (final MapEntry(key: written, value: letters) in _also.entries) {
    final mark = written.toLowerCase().runes.first;
    known[written.runes.first] = [for (final unit in letters.codeUnits) letter(unit, mark)];
  }
  return known;
}();

final RegExp _letter = RegExp(r'^\p{L}$', unicode: true);
final RegExp _number = RegExp(r'^\p{N}$', unicode: true);
final RegExp _mark = RegExp(r'^\p{M}$', unicode: true);

/// One character as the collation weighs it: the alphabet's place, then its mark, then its case; none for a
/// control character, which has no weight. A mark on its own weighs only as a mark.
List<(int, int, int)> _weights(int rune) {
  final known = _known[rune];
  if (known != null) return known;
  if (rune < 0x20 || rune == 0x7f) return const [];
  final char = String.fromCharCode(rune);
  if (_mark.hasMatch(char)) return [(0, rune, 0)];
  if (_letter.hasMatch(char)) return [(_otherLettersAt + rune, 0, 0)];
  if (_number.hasMatch(char)) return [(_otherFiguresAt + rune, 0, 0)];
  return [(_otherSignsAt + rune, 0, 0)];
}

/// [text] as the three lists it is compared by: the alphabet's, the marks', the cases'.
(List<int>, List<int>, List<int>) _keys(String text, bool numeric) {
  final first = <int>[], second = <int>[], third = <int>[];
  final runes = text.runes.toList();
  for (var at = 0; at < runes.length; at += 1) {
    final rune = runes[at];
    if (numeric && rune >= 0x30 && rune <= 0x39) {
      var end = at;
      while (end < runes.length && runes[end] >= 0x30 && runes[end] <= 0x39) {
        end += 1;
      }
      var from = at;
      while (from < end - 1 && runes[from] == 0x30) {
        from += 1;
      }
      first
        ..add(_figures)
        ..add(end - from)
        ..addAll([for (var i = from; i < end; i += 1) runes[i] - 0x30]);
      second.add(0);
      third.add(0);
      at = end - 1;
      continue;
    }
    for (final (a, b, c) in _weights(rune)) {
      if (a != 0) first.add(a);
      second.add(b);
      third.add(c);
    }
  }
  return (first, second, third);
}

int _order(List<int> one, List<int> two) {
  final most = one.length < two.length ? one.length : two.length;
  for (var i = 0; i < most; i += 1) {
    if (one[i] != two[i]) return one[i] < two[i] ? -1 : 1;
  }
  return one.length == two.length ? 0 : (one.length < two.length ? -1 : 1);
}

/// [one] against [two] as the page's `one.localeCompare(two, undefined, {numeric, sensitivity})` orders them: -1, 0
/// or 1. [base] is `sensitivity: 'base'`, where case and accents do not tell two words apart.
int localeCompare(String one, String two, {bool numeric = false, bool base = false}) {
  if (one == two) return 0;
  final a = _keys(one, numeric), b = _keys(two, numeric);
  final first = _order(a.$1, b.$1);
  if (first != 0 || base) return first;
  final second = _order(a.$2, b.$2);
  return second != 0 ? second : _order(a.$3, b.$3);
}
