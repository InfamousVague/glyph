import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/export_all.dart';
import '../../core/library_folder.dart' show failureOf;
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'settings_host.dart';

/// What Settings' search finds on Export (`findable`, src/app/settings/ExportCard.findable.ts).
const List<SettingsFindable> exportFindable = [SettingsFindable('Export everything', 'backup back up usb drive stick zip archive copy save all notes')];

/// What the row says under its name, by where an export can go from here (`HINT`).
const Map<ExportWay, String> _hint = {
  ExportWay.mac: 'Every note, picture, film and recording, as one zip. Choose a USB drive or any folder.',
  ExportWay.android: 'Every note, picture, film and recording, as one zip. Plug in a USB drive and choose it, or any folder.',
  ExportWay.browser: 'Every note and picture this browser keeps, as one zip.',
  ExportWay.update: 'Update Ghost.md to export everything.',
  ExportWay.none: 'Exporting isn’t on iPhone yet.',
};

sealed class _State {
  const _State();
}

class _Idle extends _State {
  const _Idle();
}

class _Running extends _State {
  const _Running(this.progress);
  final ExportProgress? progress;
}

class _Done extends _State {
  const _Done(this.exported);
  final Exported exported;
}

class _Failed extends _State {
  const _Failed(this.why);
  final String why;
}

/// Port of `ExportCard` (src/app/settings/ExportCard.tsx; docs/DESIGN.md §167 and §205 of ../glyph; Matt: "Please
/// add a feature that allows me to plug in a USB drive and export the entire app onto a folder or zip file with
/// `ghostmarkdown_<datetime>.7z` or something"). One row: everything, as `ghostmarkdown_<date>_<time>.zip`, wherever
/// the device's own save asks, a drive plugged in among its places (lib/core/export_all.dart). While it runs, how
/// far it has got and a word to stop it; after, what it wrote.
///
/// What differs from the web original:
/// - The export's calls are the [ExportAll] it is handed, or the one Settings was given
///   (`SettingsFeatures.export`). With none the row reads as the page's does before it knows how an export leaves
///   (the device's own words, [hint]) and cannot be pressed.
/// - **The seam.** The root hands Settings
///   `SettingsFeatures(export: ExportAll.overCore(invoke: core.invoke, startJob: core.startJob, events: core.events))`.
class ExportPane extends StatefulWidget {
  const ExportPane({super.key, this.export});

  final ExportAll? export;

  static Widget hosted(BuildContext context) => ExportPane(export: SettingsHost.maybeOf(context)?.features.export);

  /// What the row says under its name on a device, before the page knows more (`HINT`).
  static String hint(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android => _hint[ExportWay.android]!,
        TargetPlatform.iOS => _hint[ExportWay.none]!,
        _ => _hint[ExportWay.mac]!,
      };

  @override
  State<ExportPane> createState() => _ExportPaneState();
}

class _ExportPaneState extends State<ExportPane> {
  ExportWay? _way;
  _State _state = const _Idle();

  @override
  void initState() {
    super.initState();
    unawaited(_find());
  }

  @override
  void didUpdateWidget(ExportPane old) {
    super.didUpdateWidget(old);
    if (!identical(old.export, widget.export)) unawaited(_find());
  }

  Future<void> _find() async {
    final export = widget.export;
    final found = await export?.way();
    if (mounted && identical(export, widget.export)) setState(() => _way = found);
  }

  void _start() {
    setState(() => _state = const _Running(null));
    unawaited(widget.export!.exportEverything((progress) {
      if (mounted && _state is _Running) setState(() => _state = _Running(progress));
    }).then<void>(
      (exported) {
        if (mounted) setState(() => _state = exported != null ? _Done(exported) : const _Idle());
      },
      onError: (Object error) {
        if (!mounted) return;
        final said = failureOf(error);
        setState(() => _state = _Failed(said == 'That didn’t work.' ? 'The export could not be written.' : said));
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _state;
    final running = state is _Running;
    final progress = state is _Running ? state.progress : null;
    final way = _way;
    final can = way == ExportWay.mac || way == ExportWay.android || way == ExportWay.browser;
    return PaneBody(
      children: [
        if (running)
          SettingsCallout(
            icon: const AppIcon(Lucide.hardDriveDownload, size: 20),
            action: RowAction(onPress: () => widget.export?.cancel(), child: const Text('Stop')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  progress != null && progress.total > 0
                      ? 'Exporting, ${sizeSaid(progress.done)} of ${sizeSaid(progress.total)}. Keep Ghost.md open, and the drive plugged in.'
                      : 'Choose where the export goes.',
                ),
                if (progress != null) ...[
                  SizedBox(height: t.space(2)),
                  GlacierProgressBar(ariaLabel: 'Exporting everything', value: progress.done.toDouble(), max: progress.total < 1 ? 1 : progress.total.toDouble(), size: GlacierProgressBarSize.sm),
                ],
              ],
            ),
          ),
        if (state is _Done) SettingsCallout(icon: const AppIcon(Lucide.hardDriveDownload, size: 20), child: Text(doneSaid(state.exported))),
        if (state is _Failed) SettingsCallout(child: Text(state.why)),
        PaneSection(
          children: [
            SettingRow(
              icon: const AppIcon(Lucide.hardDriveDownload, size: 20),
              label: 'Export everything',
              hint: Text(way != null ? _hint[way]! : ExportPane.hint(defaultTargetPlatform)),
              onPress: can && !running ? _start : null,
              disabled: !can || running,
            ),
          ],
        ),
      ],
    );
  }
}
