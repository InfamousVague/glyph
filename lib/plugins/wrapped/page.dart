/// The Wrapped page (docs/WRAPPED.md, "Where it lives"): the sidebar's Wrapped row, the bar's Open my Wrapped and the
/// tray's View open it over everything. At its head the period, the headline count, View the story (or Make my
/// Wrapped, and how far a run is); under it the review (review.dart).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart' show preferences;
import '../../home/home_text.dart' show pageText;
import '../../settings/kit/settings_kit.dart';
import 'review.dart';
import 'service.dart';
import 'stats.dart';
import 'story.dart';

/// Opens the Wrapped page over everything, for [service] (the app's unless given).
Future<void> openWrappedPage(BuildContext context, {WrappedService? service}) {
  final wrapped = service ?? WrappedService.current;
  if (wrapped == null) return Future<void>.value();
  unawaited(wrapped.readAis());
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      pageBuilder: (route, _, _) => WrappedPage(service: wrapped, onClose: () => Navigator.of(route).maybePop()),
    ),
  );
}

/// The story opened from anywhere: the page's, the home card's. Its Review opens the page; the one you forgot's Open
/// opens the note.
Future<void> openWrappedStoryFrom(BuildContext context, WrappedService service, {bool review = true}) => openWrappedStory(
      context,
      service,
      onReview: review ? () => unawaited(openWrappedPage(context, service: service)) : null,
      onOpenNote: wrappedOpenNote == null ? null : (id) => wrappedOpenNote!(id, null),
    );

/// The words a Wrapped's headline says: "312 notes this year".
String headlineOf(WrappedStats stats) {
  final when = switch (stats.period) { WrappedPeriod.year => 'this year', WrappedPeriod.last12 => 'in 12 months', WrappedPeriod.all => 'in all' };
  return '${stats.notes} ${stats.notes == 1 ? 'note' : 'notes'} $when';
}

class WrappedPage extends StatelessWidget {
  const WrappedPage({super.key, required this.service, required this.onClose});

  final WrappedService service;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      key: const ValueKey('wrapped-page'),
      color: t.color('app-paper'),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(2), 0),
              child: Row(
                children: [
                  Expanded(child: Text('Wrapped', style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink')))),
                  GlacierPressable(
                    key: const ValueKey('wrapped-page-close'),
                    onPressed: onClose,
                    semanticLabel: 'Close',
                    builder: (context, state) => SizedBox.square(dimension: t.space(10), child: Center(child: AppIcon(Lucide.x, size: 20, color: t.color('app-ink-2')))),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(10)),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: t.space(5),
                      children: [
                        WrappedHead(service: service),
                        WrappedReview(service: service),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page's head: the period, the headline, and View the story, Make my Wrapped or how far it is.
class WrappedHead extends StatelessWidget {
  const WrappedHead({super.key, required this.service});

  final WrappedService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([service, preferences]),
        builder: (context, _) {
          final state = service.state;
          final stats = service.stats();
          return PaneSection(
            title: 'Your Wrapped',
            description: Text(service.running ? (service.held ? 'Paused while the app is busy. It goes on by itself.' : 'Reading your notes slowly in the background, ${service.done} of ${service.total}.') : (state.made ? headlineOf(stats) : 'Your year in notes, as a story, then what to tidy.')),
            children: [
              for (final period in WrappedPeriod.values)
                SettingRow(
                  key: ValueKey('wrapped-period-${period.wire}'),
                  label: period.label,
                  control: Pick(checked: state.period == period, label: 'Wrapped for ${period.label.toLowerCase()}', onPress: () => service.setPeriod(period)),
                ),
              SettingRow(
                key: const ValueKey('wrapped-story-open'),
                icon: const AppIcon(Lucide.sparkles, size: 18),
                label: 'View the story',
                hint: Text(state.made ? 'Swipe through your ${stats.period.wordsFor(DateTime.now())} in notes.' : 'The counts are ready now; the AI’s themes come with Make my Wrapped.'),
                onPress: () => unawaited(openWrappedStoryFrom(context, service, review: false)),
              ),
              SettingRow(
                key: const ValueKey('wrapped-make'),
                icon: const AppIcon(Lucide.refreshCw, size: 18),
                label: service.running ? 'Making your Wrapped… ${(service.fraction * 100).round()}%' : (state.made ? 'Refresh my Wrapped' : 'Make my Wrapped'),
                hint: service.problem != null ? Text(service.problem!) : (service.cannotMake == null ? (service.estimate == null ? null : Text(service.estimate!.words)) : Text(service.cannotMake!)),
                value: service.running
                    ? RowAction(key: const ValueKey('wrapped-stop'), onPress: service.stopForGood, child: const Text('Stop'))
                    : RowAction(key: const ValueKey('wrapped-make-go'), onPress: () => unawaited(service.make(context)), child: Text(state.made ? 'Refresh' : 'Make')),
              ),
            ],
          );
        },
      );
}
