/// Lower-cased with curly quotes made straight, for matching words (Ghost Keyboard's settings_search.dart `fold`).
String fold(String text) => text.toLowerCase().replaceAll(RegExp('[‘’]'), "'").replaceAll(RegExp('[“”]'), '"');
