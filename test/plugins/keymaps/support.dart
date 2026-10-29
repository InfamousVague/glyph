/// What the Keyboard modes plugin's Vim tests share: keys written as a string, each character a key and `<Esc>` and
/// its kin one key each.
List<String> keyNames(String keys) {
  final names = <String>[];
  var i = 0;
  while (i < keys.length) {
    if (keys[i] == '<') {
      final close = keys.indexOf('>', i);
      if (close > i + 1 && !keys.substring(i + 1, close).contains('<')) {
        names.add(keys.substring(i, close + 1));
        i = close + 1;
        continue;
      }
    }
    final rune = keys.runes.elementAt(keys.substring(0, i).runes.length);
    final char = String.fromCharCode(rune);
    names.add(char);
    i += char.length;
  }
  return names;
}
