/// Wrapped's card on the home page (Matt, 2026-11-05: "Have this plugin add a card to the home page to view the wrapped
/// section"), among the notices over the notes while the plugin is on, in Simple mode too. Three ways it reads:
/// - **Not made**: "Your Wrapped", what it is, Make my Wrapped (the estimate asked first, service.dart `make`).
/// - **Making**: "Making your Wrapped… 40%", with Open for the page.
/// - **Ready**: the period, one headline count ("312 notes this year"), the ghost, View for the story; a fresh one says
///   it is new.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../home/home_text.dart' show pageText;
import 'page.dart';
import 'service.dart';
import 'story.dart' show WrappedPill, storyHues;

/// Which way the card reads.
enum WrappedCardState { notMade, making, ready }

WrappedCardState wrappedCardState(WrappedService service) {
  if (service.running || service.state.wanted) return WrappedCardState.making;
  return service.state.made ? WrappedCardState.ready : WrappedCardState.notMade;
}

class WrappedHomeCard extends StatelessWidget {
  const WrappedHomeCard({super.key, this.service, this.onView, this.onOpen});

  /// A test's own; else the app's.
  final WrappedService? service;

  /// The story, and the page: the app's own ways unless a test says.
  final VoidCallback? onView;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final wrapped = service ?? WrappedService.current;
    if (wrapped == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: wrapped,
      builder: (context, _) {
        final t = context.tokens;
        final hue = storyHues.first;
        final state = wrappedCardState(wrapped);
        final stats = wrapped.stats();
        final (lead, line) = switch (state) {
          WrappedCardState.notMade => ('Your Wrapped', 'Your year in notes as a story, then the to-dos and stale notes to tidy.'),
          WrappedCardState.making => (wrapped.running ? 'Making your Wrapped… ${(wrapped.fraction * 100).round()}%' : 'Making your Wrapped…', wrapped.held ? 'Paused while the app is busy.' : 'Reading your notes slowly in the background.'),
          WrappedCardState.ready => ('${wrapped.state.fresh ? 'New · ' : ''}Your Wrapped · ${wrapped.state.period.label}', headlineOf(stats)),
        };
        final action = switch (state) {
          WrappedCardState.notMade => WrappedPill(key: const ValueKey('wrapped-card-make'), label: 'Make my Wrapped', hue: hue, onPressed: () => unawaited(wrapped.make(context))),
          WrappedCardState.making => WrappedPill(key: const ValueKey('wrapped-card-open'), label: 'Open', hue: hue, onPressed: onOpen ?? () => unawaited(openWrappedPage(context, service: wrapped))),
          WrappedCardState.ready => WrappedPill(key: const ValueKey('wrapped-card-view'), label: 'View', hue: hue, onPressed: onView ?? () => unawaited(openWrappedStoryFrom(context, wrapped))),
        };
        return Semantics(
          container: true,
          liveRegion: state == WrappedCardState.making,
          child: Container(
            key: ValueKey('wrapped-home-card-${state.name}'),
            margin: EdgeInsets.only(bottom: t.space(5)),
            padding: EdgeInsetsDirectional.fromSTEB(t.space(4), t.space(3), t.space(3), t.space(3)),
            decoration: BoxDecoration(color: hue.ground, borderRadius: BorderRadius.circular(t.radius('lg'))),
            child: Row(
              spacing: t.space(3),
              children: [
                SizedBox(width: 44, height: 48, child: Ghost(scene: state == WrappedCardState.making ? GhostScene.working : GhostScene.welcome, size: GhostSize.tiny, color: hue.ink)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(lead, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: hue.ink)),
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(line, style: pageText(t, t.fontSize('sm'), color: hue.ink.withValues(alpha: 0.85)))),
                      if (state == WrappedCardState.making && wrapped.running)
                        Padding(
                          padding: EdgeInsets.only(top: t.space(2)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(height: 3, child: FractionallySizedBox(alignment: AlignmentDirectional.centerStart, widthFactor: wrapped.fraction.clamp(0.02, 1), child: ColoredBox(color: hue.ink))),
                          ),
                        ),
                    ],
                  ),
                ),
                action,
              ],
            ),
          ),
        );
      },
    );
  }
}
