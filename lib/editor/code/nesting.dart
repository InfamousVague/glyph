/// One language inside another: the script, the style and the `style=""` of an HTML page, and the HTML around a
/// PHP file's `<?php … ?>`. Ports `configureNesting` of @lezer/html 1.3.13 with the lists @codemirror/lang-html
/// 6 gives it (`defaultNesting`, `defaultAttrs`), and the `parseMixed` of @codemirror/lang-php.
///
/// What differs: Lezer mounts the inner language's tree on the node as the outer parse ends; here a node is asked
/// about as the highlighter reaches it (`lezer/highlight.dart`), and the inner language reads its stretch then
/// (`lr_language.dart`).
library;

import 'grammars/html.g.dart';
import 'lezer/highlight.dart' show Mount;
import 'lezer/lr.dart';
import 'lr_language.dart';
import 'work.dart';

typedef _H = HtmlTerms;

/// The languages a page's nodes are handed to.
class HtmlNesting {
  const HtmlNesting({required this.javascript, required this.typescript, required this.jsx, required this.tsx, required this.json, required this.css, required this.styles});

  final CodeLanguage javascript, typescript, jsx, tsx;

  /// `javascriptLanguage.parser.configure({top: 'SingleExpression'})`: what a script of JSON is read as.
  final CodeLanguage json;
  final CodeLanguage css;

  /// `cssLanguage.parser.configure({top: 'Styles'})`: the declarations of a `style` attribute.
  final CodeLanguage styles;

  /// `getAttrs`: the attributes of the open tag `tag` is on, the first of a name winning as read from the end
  /// (the last, in the page's order, as an object's property set twice).
  Map<String, String> _attrs(LrWork work, RecordCursor tag) {
    final attrs = <String, String>{};
    final code = work.code;
    work.eachChild(tag, (child) {
      if (child.id != _H.Attribute) return true;
      String? name, value;
      work.eachChild(child, (part) {
        // `getChild` takes the first of a kind: read last first, the last one read is it.
        if (part.id == _H.AttributeName) {
          name = code.substring(part.start, part.end);
        } else if (part.id == _H.AttributeValue) {
          value = part.end - 1 >= part.start + 1 ? code.substring(part.start + 1, part.end - 1) : '';
        } else if (part.id == _H.UnquotedAttributeValue) {
          // `att.getChild(AttributeValue) || att.getChild(UnquotedAttributeValue)`: a quoted one comes first.
          value ??= code.substring(part.start, part.end);
        }
        return true;
      });
      if (name != null) attrs.putIfAbsent(name!, () => value ?? '');
      return true;
    });
    return attrs;
  }

  static final RegExp _jsonType = RegExp(r'^(importmap|speculationrules|application\/(.+\+)?json)$', caseSensitive: false);
  static final RegExp _scriptType = RegExp(r'^(?:text|application)\/(?:x-)?(?:java|ecma)script$|^module$|^$', caseSensitive: false);
  static final RegExp _styleType = RegExp(r'^(text\/)?(x-)?(stylesheet|css)$', caseSensitive: false);

  /// `defaultNesting`'s rows for `<script>`, in their order.
  CodeLanguage? _script(Map<String, String> attrs) {
    final type = attrs['type'], lang = attrs['lang'];
    if (type == 'text/typescript' || lang == 'ts') return typescript;
    if (type == 'text/babel' || type == 'text/jsx') return jsx;
    if (type == 'text/typescript-jsx') return tsx;
    // `regexp.test(undefined)` reads the word "undefined", which neither pattern matches.
    if (type != null && _jsonType.hasMatch(type)) return json;
    if (type == null || type.isEmpty || _scriptType.hasMatch(type)) return javascript;
    return null;
  }

  /// `defaultNesting`'s row for `<style>`.
  CodeLanguage? _style(Map<String, String> attrs) {
    final type = attrs['type'], lang = attrs['lang'];
    final langOk = lang == null || lang.isEmpty || lang == 'css';
    final typeOk = type == null || type.isEmpty || _styleType.hasMatch(type);
    return langOk && typeOk ? css : null;
  }

  /// `"beforeunload copy cut … unload".split(' ').map(n => 'on' + n)` (@codemirror/lang-html `eventAttributes`).
  static final Set<String> _eventAttributes = <String>{
    for (final name in 'beforeunload copy cut dragstart dragover dragleave dragenter dragend drag paste focus blur change click load mousedown mouseenter mouseleave mouseup keydown keyup resize scroll unload'.split(' ')) 'on$name',
  };

  /// The mount on a node of a page, if it is another language's.
  Mount<CodeLanguage>? mount(LrWork work, int id, int start, int end, RecordCursor? cursor) {
    if (cursor == null) return null;
    if (id == _H.ScriptText || id == _H.StyleText) {
      // `node.node.parent.firstChild`: the open tag is the node before this one in its element.
      final open = cursor.fork()..moveTo(cursor.pos - cursor.size);
      final attrs = open.size >= 0 && open.id == _H.OpenTag ? _attrs(work, open) : const <String, String>{};
      final language = id == _H.ScriptText ? _script(attrs) : _style(attrs);
      return language == null ? null : Mount<CodeLanguage>(language);
    }
    if (id == _H.Attribute) {
      // The first child is the name, the last the value.
      RecordCursor? first, last;
      work.eachChild(cursor, (child) {
        last ??= child.fork();
        first = child.fork();
        return true;
      });
      if (first == null || last == null) return null;
      final name = work.code.substring(first!.start, first!.end);
      final CodeLanguage language;
      if (name == 'style') {
        language = styles;
      } else if (_eventAttributes.contains(name)) {
        language = javascript;
      } else {
        return null;
      }
      final value = last!;
      if (value.id == _H.AttributeValue) {
        final from = value.start + 1;
        // `value.lastChild`: an error node there is a quote never closed.
        var unclosed = false;
        work.eachChild(value, (child) {
          unclosed = child.id == 0;
          return false;
        });
        final to = value.end - (unclosed ? 0 : 1);
        if (to > from) return Mount<CodeLanguage>(language, <int>[from, to]);
      } else if (value.id == _H.UnquotedAttributeValue) {
        return Mount<CodeLanguage>(language, <int>[value.start, value.end]);
      }
    }
    return null;
  }
}

/// `parseMixed(node => node.type.isTop ? {parser: html, overlay: node => node.name == 'Text'} : null)`: the text
/// of a PHP file outside its `<?php … ?>` is one HTML page, in pieces.
Mounter phpMounter(CodeLanguage html) =>
    (work, id, start, end, cursor) {
      if (cursor != null) return null;
      final text = work.parser.term('Text');
      final ranges = work.memo<List<int>>(() {
        final found = <int>[];
        _eachNode(work, work.cursor(), 0, (node) {
          if (node.id == text && node.end > node.start) {
            found
              ..add(node.end)
              ..add(node.start);
          }
        });
        return found.reversed.toList();
      });
      return ranges.isEmpty ? null : Mount<CodeLanguage>(html, ranges);
    };

/// Every named node of the record before `at`, back to `until`, last first.
void _eachNode(LrWork work, RecordCursor at, int until, void Function(RecordCursor node) each) {
  while (at.pos > until) {
    if (at.size >= 0 && at.id < work.parser.minRepeatTerm) each(at);
    at.next();
  }
}
