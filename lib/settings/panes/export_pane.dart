import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'settings_host.dart';

/// What Settings' search finds on Export (`findable`, src/app/settings/ExportCard.findable.ts).
const List<SettingsFindable> exportFindable = [SettingsFindable('Export everything', 'backup back up usb drive stick zip archive copy save all notes')];

/// Port of `ExportCard` (src/app/settings/ExportCard.tsx) at rest: the one row that carries everything off as a zip,
/// with the words for where an export can go from this device.
///
/// What differs from the web original: the export itself (core/exportAll.ts: the folder picker, the zip, its
/// progress, Stop, and what it says when it is done or fails) is stage 9. Until [onExport] is given the row is
/// drawn and cannot be pressed, as the page's is while it does not know how an export leaves; the callouts over the
/// row come with the feature.
class ExportPane extends StatelessWidget {
  const ExportPane({super.key, this.onExport});

  final VoidCallback? onExport;

  static Widget hosted(BuildContext context) => ExportPane(onExport: SettingsHost.maybeOf(context)?.features.onExport);

  /// What the row says under its name, by where an export can go from here (`HINT`).
  static String hint(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android => 'Every note, picture, film and recording, as one zip. Plug in a USB drive and choose it, or any folder.',
        TargetPlatform.iOS => 'Exporting isn’t on iPhone yet.',
        _ => 'Every note, picture, film and recording, as one zip. Choose a USB drive or any folder.',
      };

  @override
  Widget build(BuildContext context) => PaneBody(
        children: [
          PaneSection(
            children: [
              SettingRow(
                icon: const AppIcon(Lucide.hardDriveDownload, size: 20),
                label: 'Export everything',
                hint: Text(hint(defaultTargetPlatform)),
                onPress: onExport,
                disabled: onExport == null,
              ),
            ],
          ),
        ],
      );
}
