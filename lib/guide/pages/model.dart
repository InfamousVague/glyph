/// Which model the AI runs, asked up front like the theme: a row per model with its size, the chosen one printed in
/// reverse. A port of `src/app/guide/pages/Model.tsx`, with `.size`, `.fine` and `.action` of `Guide.module.css`.
///
/// Choosing only sets the preference; the bytes come from the word under the list, now, or from Get in Settings
/// later, so a phone on wifi tonight is ready tomorrow. Asking the AI on a note with no model on the phone says it
/// needs one and fetches nothing, so the line says where to get it rather than promising a download.
///
/// The line under the rows reads the download only where one can be had ([GuideModels.offered]): a build with no
/// engine has nothing to fetch, an iPhone runs no model, and a row still sets the preference either way.
///
/// What differs:
/// - The models on the phone come through [GuideModels] (guide_models.dart), a small interface of this folder's,
///   where the page calls `useModels()`; lib/ai's `ModelsController` is what goes behind it.
/// - The catalogue is Settings' copy of `MODELS` (lib/settings/panes/ai_pane.dart), which is the one lib/ai has too.
/// - The preferences are a store the page is given, as on the theme page.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/preferences.dart';
import '../../settings/panes/ai_pane.dart' show ModelChoice, gb, modelName, models;
import '../guide_models.dart';
import 'parts.dart';

class GuideModel extends StatelessWidget {
  const GuideModel({super.key, required this.phone, this.store});

  /// What is on the phone, and the way to fetch.
  final GuideModels phone;

  /// The preferences to read and set; the app's own when null.
  final ValueNotifier<Preferences>? store;

  @override
  Widget build(BuildContext context) {
    final prefs = store ?? preferences;
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, phone]),
      builder: (context, _) {
        final chosenId = prefs.value.formatModel;
        final ModelChoice? chosen = models.where((m) => m.id == chosenId).firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const GuideTitle('Choose your model'),
            const GuideLead('It rewrites your notes on the phone. Bigger is more careful, and slower. Nothing leaves the phone.'),
            GuideChoices(
              label: 'Model',
              children: [
                for (final model in models)
                  GuideChoice(
                    label: model.name,
                    hint: model.about,
                    on: chosenId == model.id,
                    onPick: () => prefs.value = prefs.value.copyWith(formatModel: model.id),
                    swatch: (context) => _size(context.tokens, gb(model.bytes), chosenId == model.id),
                  ),
              ],
            ),
            if (phone.offered && chosen != null) _Fine(phone: phone, chosen: chosen),
          ],
        );
      },
    );
  }
}

/// `.size`: a model's size in the swatch's place, the one number that decides the choice. On the chosen row
/// (`.choice[data-selected] .size`) it is the reversed paper.
Widget _size(Tokens t, String text, bool on) => GuideSwatch(
  text: text,
  style: t.textAt(t.fontSize('sm'), weight: 'bold', color: t.color('app-ink')).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  color: t.color(on ? 'app-paper' : 'app-paper-2'),
  border: t.color('app-rule'),
);

/// What the line under the rows says, and whether "get it now" follows it (`Model`'s own conditions).
({String words, bool get}) modelLine(GuideModels phone, ModelChoice chosen) {
  final download = phone.download;
  final here = phone.present(chosen.id);
  final problem = phone.problem;
  final words = download?.id == chosen.id
      ? 'Getting ${modelName(chosen.id)}, ${gb(download!.received)} of ${gb(download.total)}. Keep Ghost.md open.'
      : here
      ? '${chosen.name} is on the phone.'
      : problem != null && problem.isNotEmpty
      ? problem
      : '${chosen.name} is not on the phone yet. Get it later in Settings › Recording, or ';
  return (words: words, get: !here && download == null);
}

/// `.fine`: the line about the chosen model's download, under a hairline.
class _Fine extends StatelessWidget {
  const _Fine({required this.phone, required this.chosen});
  final GuideModels phone;
  final ModelChoice chosen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final line = modelLine(phone, chosen);
    final style = t.textAt(t.fontSize('sm'), color: t.color('glacier-text-subtle'));
    return Container(
      margin: EdgeInsets.only(top: t.space(4)),
      padding: EdgeInsets.only(top: t.space(4)),
      width: double.infinity,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')))),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: line.words),
            if (line.get)
              // `.app-word.action`: a button that is only its words, in the line, a `--glacier-space-2` lower.
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Padding(
                  padding: EdgeInsets.only(top: t.space(2)),
                  child: GuideWord(
                    'get it now',
                    onPressed: () => phone.fetch(chosen.id),
                    style: t.textAt(t.fontSize('md'), weight: 'medium'),
                    color: t.color('glacier-accent-text'),
                    bleed: 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
