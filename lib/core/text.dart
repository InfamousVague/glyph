/// The small things done to a string all over the app, done one way. A port of `src/app/core/text.ts`, one to one.
///
/// Spoken words arrive in lower case and are written as a person would write them, so a title, a list item or a
/// plugin's name is capitalised where it is shown, and a tip read aloud after "Hey Ghost," goes the other way. Words
/// a person said, or a key they chose, are searched for inside a pattern, which means escaping them first.
///
/// Deliberately only the first letter: "iPhone" and "API" keep their own spelling after the first character,
/// because what came after it is what the person said. A leaf with no imports, so anything may use it.
///
/// What differs: nothing. [escapeRegExp] escapes the web's own set of characters rather than calling Dart's
/// `RegExp.escape`, so a pattern built here is the pattern the web builds.
library;

/// [text] with its first character in upper case and the rest as written: "milk" -> "Milk".
String capitalise(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// [text] with its first character in lower case and the rest as written: "Add milk" -> "add milk".
String lowerFirst(String text) => text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

final RegExp _syntax = RegExp(r'[.*+?^${}()|[\]\\]');

/// [text] with every character a RegExp reads as syntax escaped, so a pattern built around it matches it literally.
String escapeRegExp(String text) => text.replaceAllMapped(_syntax, (m) => '\\${m.group(0)}');
