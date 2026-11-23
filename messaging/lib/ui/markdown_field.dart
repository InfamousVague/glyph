import 'package:flutter/widgets.dart';

import '../links.dart';
import '../message_format.dart';
import '../mentions.dart';

/// The composer's words with their formatting markers dimmed as they are typed (GMFB-35, lib/message_format.dart): the
/// "**" of **bold** and the "> " of a quote fainter than the words, so what will be drawn formatted shows without the
/// field drawing anything else. The words are the words: nothing is put in or taken out, and they go as written.
///
/// MentionController (lib/ui/mention_field.dart) is one, with its mentions drawn in theirs.
class MarkdownController extends TextEditingController {
  MarkdownController({super.text});

  /// Whether the markers are dimmed now: not where the words go somewhere that shows them as written (a text). Always
  /// where null.
  bool Function()? dims;

  /// The mentions drawn in [mentionLook] among the words; none here.
  List<Mention> get drawnMentions => const [];
  TextStyle? get mentionLook => null;

  /// [before] and [after] put round the selection (Bold, Italic, Code in the selection's menu), the selection kept on
  /// the same words; at a cursor, the two with the cursor between them.
  void wrapSelection(String before, [String? after]) {
    final close = after ?? before;
    final s = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    final words = text.substring(s.start, s.end);
    value = TextEditingValue(
      text: text.replaceRange(s.start, s.end, '$before$words$close'),
      selection: s.isCollapsed ? TextSelection.collapsed(offset: s.start + before.length) : TextSelection(baseOffset: s.start + before.length, extentOffset: s.start + before.length + words.length),
    );
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final words = text;
    final look = mentionLook;
    final mentions = look == null ? const <Mention>[] : Mention.checked(drawnMentions, words);
    final dim = dims?.call() ?? true;
    final format = dim ? MessageFormat.parse(words, keep: [for (final m in mentions) (m.start, m.end)], links: [for (final l in MessageLink.find(words)) (l.start, l.end)]) : null;
    final marks = [for (final r in format?.runs ?? const <FormatRun>[]) if (r.marker || r.bar) r];
    if (marks.isEmpty && mentions.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final ink = style?.color ?? const Color(0xFF000000);
    final faint = TextStyle(color: ink.withValues(alpha: 0.4));
    // The word being composed on a phone's keyboard keeps its underline.
    final composing = withComposing && value.isComposingRangeValid ? value.composing : null;
    final cuts = <int>{
      0,
      words.length,
      for (final r in marks) ...[r.start, r.end],
      for (final m in mentions) ...[m.start, m.end],
      if (composing != null) ...[composing.start, composing.end],
    }.where((c) => c >= 0 && c <= words.length).toList()
      ..sort();
    final spans = <InlineSpan>[];
    var ri = 0, mi = 0;
    for (var c = 0; c + 1 < cuts.length; c++) {
      final a = cuts[c], b = cuts[c + 1];
      if (b <= a) continue;
      while (ri < marks.length && marks[ri].end <= a) {
        ri++;
      }
      while (mi < mentions.length && mentions[mi].end <= a) {
        mi++;
      }
      TextStyle? s;
      if (ri < marks.length && marks[ri].start <= a) s = faint;
      if (mi < mentions.length && mentions[mi].start <= a) s = look;
      if (composing != null && a >= composing.start && b <= composing.end) {
        s = (s ?? const TextStyle()).merge(const TextStyle(decoration: TextDecoration.underline));
      }
      spans.add(TextSpan(text: words.substring(a, b), style: s));
    }
    return TextSpan(style: style, children: spans);
  }
}
