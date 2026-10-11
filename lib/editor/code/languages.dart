/// Which language a fenced block is in, and who reads it. Ports the two halves of how the web app finds a
/// fence's parser: `getCodeParser` of @codemirror/lang-markdown 6.5 (what comes before the first space of the info
/// string) and `LanguageDescription.matchLanguageName` of @codemirror/language 6.12 over the list of
/// @codemirror/language-data 6.5 (`language_names.g.dart`).
///
/// The pack knows 143 languages, and 142 are read here: the Lezer grammars the pack loads (`grammars/`), and its
/// older line-by-line modes for the rest (`stream/`), a dozen ported to Dart by hand and the others run from
/// their own JavaScript (`stream/js_mode.dart`). The one not read is Angular Template, which no fence can ask
/// for: its only name has a space in it, and an info string is read up to its first space. A language the pack
/// knows and nothing here reads is still a language: its block is drawn in the code's own ink with no token
/// coloured, as the web draws a block whose language is still loading, and not in the one colour of a block
/// with no language at all.
library;

import 'grammars/cpp.dart';
import 'grammars/css.dart';
import 'grammars/go.dart';
import 'grammars/html.dart';
import 'grammars/java.dart';
import 'grammars/jinja.dart';
import 'grammars/javascript.dart';
import 'grammars/json.dart';
import 'grammars/less.dart';
import 'grammars/liquid.dart';
import 'grammars/php.dart';
import 'grammars/python.dart';
import 'grammars/rust.dart';
import 'grammars/sass.dart';
import 'grammars/sql.dart';
import 'grammars/sql.g.dart' show sqlDialects;
import 'grammars/vue.dart';
import 'grammars/wast.dart';
import 'grammars/xml.dart';
import 'grammars/yaml.dart';
import 'language_names.g.dart';
import 'lr_language.dart';
import 'markdown_language.dart';
import 'nesting.dart';
import 'stream/clike.dart' as clike;
import 'stream/js/js.dart' show wholeJavaScript;
import 'stream/js_mode.dart';
import 'stream/modes.dart';
import 'stream/modes.g.dart';
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
final LrLanguage _html = LrLanguage('HTML', () => htmlParser, mounter: _htmlNesting.mount);

/// `javascriptLanguage.parser.configure({top: 'SingleExpression'})`: what stands between a Vue page's `{{` and
/// `}}`, and in the quotes of its `@click` and `:class`.
final LrLanguage _expression = LrLanguage('JavaScript', () => javascriptParser.configure(top: 'SingleExpression'));

final Map<String, CodeLanguage> _languages = <String, CodeLanguage>{
  'JavaScript': _javascript,
  'TypeScript': _typescript,
  'JSX': _jsx,
  'TSX': _tsx,
  'JSON': LrLanguage('JSON', () => jsonParser),
  'CSS': _css,
  'HTML': _html,
  // A template: its tags by a grammar of their own, the page between them HTML.
  'Liquid': LrLanguage('Liquid', () => liquidParser, mounter: templateMounter(_html)),
  'Jinja': LrLanguage('Jinja', () => jinjaParser, mounter: templateMounter(_html)),
  // A Vue file: HTML whose tags may close themselves, its text and its `@`, `:` and `v-` attributes Vue's own.
  'Vue': LrLanguage(
    'Vue',
    () => htmlParser.configure(dialect: 'selfClosing'),
    mounter: vueMounter(
      _htmlNesting,
      LrLanguage('Vue', () => vueTextParser, mounter: nodeMounter('InterpolationContent', _expression)),
      LrLanguage('Vue', () => vueAttributeParser, mounter: nodeMounter('AttributeScript', _expression)),
    ),
  ),
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
  'WebAssembly': LrLanguage('WebAssembly', () => wastParser),
  'LESS': LrLanguage('LESS', () => lessParser),
  'SCSS': LrLanguage('SCSS', () => scssParser),
  'Sass': LrLanguage('Sass', () => sassParser),
  // Read by the note's own parser, as CommonMark (markdown_language.dart).
  'Markdown': MarkdownCodeLanguage(htmlInMarkdown),
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
  // The rest of the older modes, each run from its own JavaScript (stream/js_mode.dart): what CodeMirror's
  // `token` function says of a line is what is coloured.
  for (final (language, file, name, call) in legacyModes)
    if (!_portedByHand.contains(language))
      language: StreamLanguage<Object?>(language, () {
        wholeJavaScript ??= _wholeJavaScript;
        return loadJsMode(language, file, name, call: call);
      }),
};

/// The older modes ported to Dart by hand, above: the commonest, read at Dart's speed.
const Set<String> _portedByHand = <String>{'C#', 'Kotlin', 'Dart', 'Scala', 'Objective-C', 'Swift', 'Ruby', 'Shell', 'TOML', 'diff', 'Lua', 'Properties files'};

/// Pug's mode asks JavaScript itself (`Function('', 'var x =' + value)`) whether an attribute's value has ended.
/// Here the grammar JavaScript is coloured by is asked: whole where it reads the code without an error.
bool _wholeJavaScript(String code) {
  final work = _javascript.start(code) as LrWork..work(code.length, Budget.none());
  for (final at = work.cursor(); at.pos > 0; at.next()) {
    if (at.size >= 0 && at.id == 0) return false;
  }
  return true;
}

/// Who reads the language the pack calls `name`, or null where nothing here does.
CodeLanguage? languageNamed(String name) => _languages[name];

/// The pack's names of the languages read here.
Iterable<String> get readLanguages => _languages.keys;
