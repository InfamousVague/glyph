/// The walkthrough's last page. A port of `src/app/guide/pages/Start.tsx`, with `.art` and `.learn` of
/// `Guide.module.css`.
///
/// The walkthrough has said what Ghost.md is, how it looks and which model it runs, and hands over: everything else,
/// the marks, the words you can say, boards, canvases, journals, is the Academy's, short lessons inside the app, so
/// this page offers it and otherwise gets out of the way. Start, in the dock, closes the guide.
///
/// What differs: nothing.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app/widgets.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/shapes.dart';
import 'parts.dart';

class GuideStart extends StatelessWidget {
  const GuideStart({super.key, required this.onAcademy});

  /// The page's other way out: the Academy, for the rest.
  final VoidCallback onAcademy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The picture sits above its title in grey, quieter than the words it introduces.
        Padding(
          padding: EdgeInsets.only(bottom: t.space(5)),
          child: TipsShape(size: t.lenOf('7.5rem'), color: t.color('app-ink-3')),
        ),
        const GuideTitle('Learn it, or just start.'),
        const GuideLead(
          'The marks, the words you can say, boards, canvases and the rest are in the Ghost.md Academy: short lessons inside the app, a few minutes each. '
          'Take it now, or start writing and find it on the home page any time.',
        ),
        Padding(
          padding: EdgeInsets.only(top: t.space(6)),
          child: AppPill(onPressed: onAcademy, icon: AppIcon(Lucide.bookOpen, size: 18, strokeWidth: 2.2, color: t.color('app-paper')), child: const Text('Take the Ghost.md Academy')),
        ),
      ],
    );
  }
}
