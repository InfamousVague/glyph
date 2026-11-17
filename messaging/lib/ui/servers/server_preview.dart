/// The server preview (Matt, 2026-11-17: "add a mocked sever under the "more" button in the dock when we click add
/// server it should launch the mock version with a button to toggle between the 5 different designs"): a made-up
/// server (server_mock.dart) in one of five layouts (server_layouts.dart), switched by the bar along its top. Nothing
/// in it reaches anyone: it is for choosing how servers should look.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app_state.dart';
import '../../art/app_icon.dart';
import '../../kit/settings_type.dart';
import '../common.dart';
import 'server_layouts.dart';
import 'server_mock.dart';

class ServerPreviewScreen extends StatefulWidget {
  const ServerPreviewScreen({super.key, this.server});

  /// The server shown; a fresh made-up one where not given.
  final MockServer? server;

  @override
  State<ServerPreviewScreen> createState() => _ServerPreviewScreenState();
}

class _ServerPreviewScreenState extends State<ServerPreviewScreen> {
  late final MockServer _server = widget.server ?? sampleServer();
  ServerLayout? _layout;

  static const _pref = 'dev_server_layout';

  ServerLayout _chosen(AppState app) => _layout ?? ServerLayout.values.where((l) => l.name == app.choice(_pref, '')).firstOrNull ?? ServerLayout.rail;

  @override
  void dispose() {
    if (widget.server == null) _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = AppState.of(context);
    final layout = _chosen(app);
    return GhostPage(
      title: 'Server preview',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(1), t.space(3), t.space(1)),
          child: GlacierSegmentedControl(
            fullWidth: true,
            size: GlacierSegmentedSize.md,
            ariaLabel: 'Server layout',
            value: layout.name,
            onValueChange: (v) {
              setState(() => _layout = ServerLayout.values.byName(v));
              app.set(_pref, v);
            },
            options: [
              for (final l in ServerLayout.values)
                GlacierSegmentedOption(
                  value: l.name,
                  label: Semantics(
                    key: ValueKey('server-layout-${l.name}'),
                    label: l.label,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(l.icon, size: 16, wash: false),
                      if (MediaQuery.sizeOf(context).width >= 600) ...[SizedBox(width: t.space(1)), Text(l.label)],
                    ]),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(2)),
          child: Text('${layout.label} · like ${layout.after}. ${layout.description}', maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
        ),
        Container(height: 1, color: t.color('app-rule')),
        Expanded(
          child: ListenableBuilder(
            listenable: _server,
            builder: (context, _) => KeyedSubtree(key: ValueKey(layout), child: serverLayout(layout, _server)),
          ),
        ),
      ]),
    );
  }
}
