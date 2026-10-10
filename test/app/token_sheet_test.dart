// The app's token sheet as Dart (lib/app/token_sheet.g.dart, written by tool/token_sheet.dart): the app's start
// reads and parses no CSS, so what it is handed has to be exactly what reading the stylesheets answers.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:ghost_md/app/token_sheet.g.dart';
import 'package:glacier/glacier.dart';

import '../../tool/token_sheet.dart' as tool;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the tool reads the stylesheets the engine does, in its order', () {
    expect(tool.sheets, [glacierTokensAsset, ...appStyleSheets]);
  });

  test('the file is what the tool makes of the stylesheets as they are now', () {
    expect(
      File(tool.target).readAsStringSync() == tool.generate(),
      isTrue,
      reason: 'a stylesheet changed and ${tool.target} did not: dart run tool/token_sheet.dart',
    );
  });

  test('is the sheet reading the stylesheets answers, rule for rule', () async {
    final read = await loadTokenSheet(more: appStyleSheets);
    final kept = appTokenSheet();
    expect(kept.rules.length, read.rules.length);
    String said(TokenCondition c) => '${c.isClass ? '.' : ''}${c.key}=${c.value}${c.negated ? ' not' : ''}';
    for (var i = 0; i < read.rules.length; i += 1) {
      final a = read.rules[i], b = kept.rules[i];
      final where = 'rule $i';
      expect((b.specificity, b.order, b.reducedMotion), (a.specificity, a.order, a.reducedMotion), reason: where);
      expect([for (final c in b.conditions) said(c)], [for (final c in a.conditions) said(c)], reason: where);
      expect(b.subject == null ? null : [for (final c in b.subject!) said(c)], a.subject == null ? null : [for (final c in a.subject!) said(c)], reason: where);
      // The same properties with the same words, in the order they were declared.
      expect(b.declarations.entries.map((e) => '${e.key}: ${e.value}').toList(), a.declarations.entries.map((e) => '${e.key}: ${e.value}').toList(), reason: where);
    }
  });

  test('is a sheet of its own each time, which can be added to', () {
    final one = appTokenSheet(), two = appTokenSheet();
    final rules = one.rules.length;
    one.rules.add(const TokenRule(conditions: [], declarations: {'--x': '1'}, specificity: 0, order: 9999));
    expect(one.rules.length, rules + 1);
    expect(two.rules.length, rules);
  });
}
