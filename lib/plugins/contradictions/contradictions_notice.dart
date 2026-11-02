/// The contradiction finder's quiet line on the home page (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "flags the stale one
/// inline … so old notes stop misleading you"): "2 notes may be out of date   Review", in the notices' own look
/// (lib/notes/notices.dart [JobNotice]), opening the plugin's page. Nothing while nothing may be out of date, or with
/// the plugin off.
library;

import 'package:flutter/widgets.dart';

import '../../ai/contradictions/runner.dart';
import '../../notes/notices.dart' show JobNotice;
import '../registry.dart' show plugins;
import 'contradictions.dart' show contradictionRunner;
import 'manifest.dart';

/// The line's words for [stale] notes.
String staleWords(int stale) => stale == 1 ? '1 note may be out of date' : '$stale notes may be out of date';

class ContradictionsNotice extends StatelessWidget {
  const ContradictionsNotice({super.key, this.runner, required this.onOpen, this.on});

  /// A test's finder; else the app's.
  final ContradictionRunner? runner;
  final VoidCallback onOpen;

  /// Whether the plugin is on: the registry's switch where null.
  final bool Function()? on;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ContradictionRunner?>(
        valueListenable: contradictionRunner,
        builder: (context, app, _) {
          final finder = runner ?? app;
          if (finder == null) return const SizedBox.shrink();
          return ListenableBuilder(
            listenable: Listenable.merge([finder, plugins]),
            builder: (context, _) {
              final stale = finder.staleNotes;
              if (stale == 0 || !(on ?? () => plugins.isEnabled(manifest.id))()) return const SizedBox.shrink();
              return KeyedSubtree(key: const ValueKey('contradictions-notice'), child: JobNotice(words: staleWords(stale), action: 'Review', onAction: onOpen));
            },
          );
        },
      );
}
