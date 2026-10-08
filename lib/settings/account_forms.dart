import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'kit/settings_kit.dart';
import 'kit/settings_type.dart';

/// `.setk-form` (settings.css): a form's fields in a column a `--glacier-space-2` apart, in a row's padding; the
/// account's and the organizations' pages share it. [bare] is the form inside the sign-in card
/// (`.setk-signIn .setk-form { padding: 0 }`).
class SettingsForm extends StatelessWidget {
  const SettingsForm({super.key, required this.children, this.bare = false});
  final List<Widget> children;
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.all(bare ? 0 : t.space(3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: t.space(2)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// `.setk-form__problem`: what went wrong, or (`role="status"`) what went right, under a form's fields.
class FormProblem extends StatelessWidget {
  const FormProblem(this.words, {super.key});
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(liveRegion: true, child: Text(words, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink'))));
  }
}

/// `.app-word.setk-form__submit`: a form's word, at the start of its line, or ([stretch], the sign-in card's) across
/// it. Null [onPressed] is the disabled button.
class FormSubmit extends StatelessWidget {
  const FormSubmit(this.words, {super.key, this.wordKey, required this.onPressed, this.stretch = false});
  final String words;

  /// The word's own key: its box is the button's, where this widget's is the line it stands in.
  final Key? wordKey;
  final VoidCallback? onPressed;
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final word = DefaultTextStyle(style: pageText(t, t.lenOf('1rem')), child: SettingsWord(key: wordKey, onPressed: onPressed, child: Text(words)));
    return Align(alignment: stretch ? Alignment.center : AlignmentDirectional.centerStart, child: word);
  }
}

/// `.swatch` (OrganizationsPane.module.css): the seven hues in a card's own padding.
class CardSwatch extends StatelessWidget {
  const CardSwatch({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.all(context.tokens.space(3)), child: child);
}
