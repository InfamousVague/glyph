/// Which language a fenced block is in, and who reads it. Ports the two halves of how the web app finds a
/// fence's parser: `getCodeParser` of @codemirror/lang-markdown 6.5 (what comes before the first space of the info
/// string) and `LanguageDescription.matchLanguageName` of @codemirror/language 6.12 over the list of
/// @codemirror/language-data 6.5 (`language_names.g.dart`).
///
/// The pack knows 146 languages. The ones read here are the Lezer grammars the pack loads for the languages
/// people write most (`grammars/`), and its older line-by-line modes for the rest of them (`stream/`). A language
/// the pack knows and nothing here reads is still a language: its block is drawn in the code's own ink with no
/// token coloured, as the web draws a block whose language is still loading, and not in the one colour of a
/// block with no language at all.
library;

import 'grammars/cpp.dart';
import 'grammars/css.dart';
import 'grammars/go.dart';
import 'grammars/html.dart';
import 'grammars/java.dart';
import 'grammars/javascript.dart';
import 'grammars/json.dart';
import 'grammars/php.dart';
import 'grammars/python.dart';
import 'grammars/rust.dart';
import 'grammars/sql.dart';
import 'grammars/sql.g.dart' show sqlDialects;
import 'grammars/xml.dart';
import 'grammars/yaml.dart';
import 'language_names.g.dart';
import 'lr_language.dart';
import 'nesting.dart';
import 'stream/clike.dart' as clike;
import 'stream/modes.dart';
import 'stream/stream_language.dart';
import 'work.dart';

final RegExp _word = RegExp(r'\w');
final RegExp _notSpace = RegExp(r'\S*');

/// JavaScript's `/\w/.test(name[i])`. Past either end `name[i]` is `undefined`, which `test` reads as the word
/// "undefined": a word character. So a short name at the very start or end of what was written never matches.
bool _isWordAt(String name, int i) => i < 0 || i >= name.length || _word.hasMatch(name[i]);

final Map<String, String?> _resolved = <String, String?>{};

/// The pack's name for the language a fence's info string asks for (`js` is `JavaScript`), or null: no info
/// string, or nothing the pack knows.
///
/// `matchLanguageName(languages, name, true)`: the first language one of whose names is exactly what was
/// written; failing that, the first one of whose names is found inside it, a name of one or two letters only
/// where no letter or digit stands either side of it.
String? languageNameOf(String info) {
  if (_resolved.containsKey(info)) return _resolved[info];
  String? found;
  // Strip anything after whitespace.
  final name = (_notSpace.matchAsPrefix(info)?.group(0) ?? '').toLowerCase();
  if (name.isNotEmpty) {
    outer:
    for (final (language, alias) in languageNames) {
      for (final a in alias) {
        if (a == name) {
          found = language;
          break outer;
        }
      }
    }
    if (found == null) {
      fuzzy:
      for (final (language, alias) in languageNames) {
        for (final a in alias) {
          final at = name.indexOf(a);
          if (at > -1 && (a.length > 2 || !_isWordAt(name, at - 1) && !_isWordAt(name, at + a.length))) {
            found = language;
            break fuzzy;
          }
        }
      }
    }
  }
  if (_resolved.length > 500) _resolved.clear();
  return _resolved[info] = found;
}

final LrLanguage _javascript = LrLanguage('JavaScript', () => javascriptParser);
final LrLanguage _typescript = LrLanguage('TypeScript', () => typescriptParser);
final LrLanguage _jsx = LrLanguage('JSX', () => jsxParser);
final LrLanguage _tsx = LrLanguage('TSX', () => tsxParser);
final LrLanguage _css = LrLanguage('CSS', () => cssParser);

final HtmlNesting _htmlNesting = HtmlNesting(
  javascript: _javascript,
  typescript: _typescript,
  jsx: _jsx,
  tsx: _tsx,
  json: LrLanguage('JavaScript', () => javascriptParser.configure(top: 'SingleExpression')),
  css: _css,
  styles: LrLanguage('CSS', () => cssStylesParser),
);

/// The HTML of a tag or a block in a line of a note: `html({matchClosingTags: false})`, which is what
/// @codemirror/lang-markdown reads `HTMLBlock`, `HTMLTag` and `CommentBlock` with, and what a PHP file's text is.
final LrLanguage htmlInMarkdown = LrLanguage('HTML', () => htmlNoMatchParser, mounter: _htmlNesting.mount);

/// The readers, by the pack's name for the language.
final Map<String, CodeLanguage> _languages = <String, CodeLanguage>{
  'JavaScript': _javascript,
  'TypeScript': _typescript,
  'JSX': _jsx,
  'TSX': _tsx,
  'JSON': LrLanguage('JSON', () => jsonParser),
  'CSS': _css,
  'HTML': LrLanguage('HTML', () => htmlParser, mounter: _htmlNesting.mount),
  'Python': LrLanguage('Python', () => pythonParser),
  'Rust': LrLanguage('Rust', () => rustParser),
  'Go': LrLanguage('Go', () => goParser),
  'Java': LrLanguage('Java', () => javaParser),
  // The pack reads C with the C++ grammar: both load `cpp()`.
  'C': LrLanguage('C', () => cppParser),
  'C++': LrLanguage('C++', () => cppParser),
  'PHP': LrLanguage('PHP', () => phpParser, mounter: phpMounter(htmlInMarkdown)),
  'XML': LrLanguage('XML', () => xmlParser),
  'YAML': LrLanguage('YAML', () => yamlParser),
  // SQL, and the seven dialects the pack names: one grammar, each dialect's own words and quoting.
  for (final dialect in sqlDialects.keys) dialect: LrLanguage(dialect, () => sqlParser(dialect)),
  // The pack's older modes (@codemirror/legacy-modes), for the languages it has no grammar for.
  'C#': StreamLanguage<clike.ClikeState>('C#', clike.csharp),
  'Kotlin': StreamLanguage<clike.ClikeState>('Kotlin', clike.kotlin),
  'Dart': StreamLanguage<clike.ClikeState>('Dart', clike.dart),
  'Scala': StreamLanguage<clike.ClikeState>('Scala', clike.scala),
  'Objective-C': StreamLanguage<clike.ClikeState>('Objective-C', clike.objectiveC),
  'Swift': StreamLanguage<SwiftState>('Swift', Swift.new),
  'Ruby': StreamLanguage<RubyState>('Ruby', Ruby.new),
  'Shell': StreamLanguage<ShellState>('Shell', Shell.new),
  'TOML': StreamLanguage<TomlState>('TOML', Toml.new),
  'diff': StreamLanguage<bool>('diff', Diff.new),
  'Lua': StreamLanguage<LuaState>('Lua', Lua.new),
  'Properties files': StreamLanguage<PropertiesState>('Properties files', Properties.new),
};

/// Who reads the language the pack calls `name`, or null where nothing here does.
CodeLanguage? languageNamed(String name) => _languages[name];

/// The pack's names of the languages read here.
Iterable<String> get readLanguages => _languages.keys;
