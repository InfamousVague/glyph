/// Wrapped's page in Settings (docs/WRAPPED.md, "Where it lives"): the period, View the story, Make or Refresh with
/// the estimate and how far a run is (wrapped's head, page.dart), the review a press away, and what is sent. In Simple
/// (`Preferences.simple`) Read everything again waits behind More, which opens in place.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../../core/preferences.dart' show preferences;
import '../../settings/kit/settings_kit.dart';
import '../../settings/settings_search.dart' show SettingsFindable;
import 'page.dart';
import 'pass.dart' show WrappedPacing;
import 'service.dart';

/// What Settings' search finds on the page.
const List<SettingsFindable> wrappedFindable = [
  SettingsFindable('Your Wrapped', 'wrapped year review story spotify recap make refresh period this year last 12 months all time'),
  SettingsFindable('Review', 'unfinished to-dos todo check off stale archive trash tidy reorganise move merge duplicates links'),
  SettingsFindable('What is sent', 'wrapped ai sent cost tokens key privacy gist'),
];

class WrappedPane extends StatefulWidget {
  const WrappedPane({super.key, this.service});

  /// A test's own; else the app's.
  final WrappedService? service;

  @override
  State<WrappedPane> createState() => _WrappedPaneState();
}

class _WrappedPaneState extends State<WrappedPane> {
  bool _more = false;

  WrappedService? get _service => widget.service ?? WrappedService.current;

  @override
  void initState() {
    super.initState();
    final service = _service;
    if (service != null) unawaited(service.readAis());
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      // Before the root has made it (and in a test that draws the page alone): the page's headings, so Settings' search
      // finds what it lists.
      return const PaneBody(children: [
        PaneSection(title: 'Your Wrapped', children: [SettingRow(label: 'Wrapped starts once your notes are read.')]),
        PaneSection(title: 'Review', children: []),
        PaneSection(title: 'What is sent', description: Text('Your notes go only to the AI you have connected, with your own key, a few at a time.'), children: []),
      ]);
    }
    return ListenableBuilder(listenable: Listenable.merge([service, preferences]), builder: (context, _) => _page(context, service));
  }

  Widget _page(BuildContext context, WrappedService service) {
    final simple = preferences.value.simple;
    if (!_more && settingsSought(context, const ['Read everything again'])) _more = true;
    final full = !simple || _more;
    final ai = service.ai;
    final pace = ai == null ? WrappedPacing.cloud : WrappedPacing.of(ai);
    return PaneBody(
      children: [
        WrappedHead(service: service),
        PaneSection(
          title: 'Review',
          children: [
            SettingRow(
              key: const ValueKey('wrapped-open-page'),
              icon: const AppIcon(Lucide.squareCheckBig, size: 18),
              label: 'Unfinished to-dos, stale notes and tidying',
              hint: Text('${service.todos.length} open to-dos · ${service.stale.length} stale notes · ${service.suggestions.length} suggestions'),
              onPress: () => unawaited(openWrappedPage(context, service: service)),
            ),
          ],
        ),
        PaneSection(
          title: 'What is sent',
          description: Text(
            ai == null
                ? 'With no AI connected, your Wrapped is made of counts alone, on this device.'
                : '${ai.local ? 'Your notes stay on this device: the model on it reads them.' : 'Sent to ${ai.name} with your own key: each note’s title, folder, dates and first ${pace.charsPerNote} characters, ${pace.notesPerAsk} notes at a time, then one ask with a one-line gist of each.'} Your organizations’ notes are never read. A note is sent again only once its words change. What is found is kept in your Library’s .glyph folder.',
          ),
          children: const [],
        ),
        if (full)
          PaneSection(
            children: [
              SettingRow(
                key: const ValueKey('wrapped-forget'),
                label: 'Read everything again',
                hint: const Text('Forgets every gist, so the next Make my Wrapped sends every note again.'),
                control: RowAction(onPress: service.forgetReads, child: const Text('Forget')),
              ),
            ],
          )
        else
          PaneSection(
            children: [
              SettingRow(
                key: const ValueKey('wrapped-pane-more'),
                label: 'More',
                hint: const Text('Read everything again.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
            ],
          ),
      ],
    );
  }
}
