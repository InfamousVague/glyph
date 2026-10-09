import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The kit's haptic vocabulary (`@glacier/react` haptics.ts `HapticKind`).
enum HapticKind { selection, light, medium, heavy, success, warning, error }

typedef HapticFn = void Function([HapticKind kind]);

/// Programmatic feedback, announced so a visual layer can answer in the same frame as the motor (feedback.ts).
class FeedbackEvent {
  const FeedbackEvent(this.kind, [this.at]);
  final HapticKind kind;

  /// Where on the screen, for an effect that spreads from a point; absent, and it centres.
  final Offset? at;
}

final _listeners = <void Function(FeedbackEvent)>{};

/// Subscribe to programmatic feedback. Returns the way to stop.
VoidCallback subscribeFeedback(void Function(FeedbackEvent) listener) {
  _listeners.add(listener);
  return () => _listeners.remove(listener);
}

void emitFeedback(FeedbackEvent event) {
  for (final listener in _listeners.toList()) {
    listener(event);
  }
}

bool _enabled = false;

/// Turn the motor on or off. [HapticsProvider] drives this.
void setHapticsEnabled(bool next) => _enabled = next;
bool hapticsEnabled() => _enabled;

/// Buzz the device for [kind], if haptics are on. The web kit could only vary a vibration's length; the phone has
/// real impacts, so each kind is the platform's own, and the three that were patterns keep their rhythm.
void fireMotor([HapticKind kind = HapticKind.light]) {
  if (!_enabled) return;
  switch (kind) {
    case HapticKind.selection:
      HapticFeedback.selectionClick();
    case HapticKind.light:
      HapticFeedback.lightImpact();
    case HapticKind.medium:
      HapticFeedback.mediumImpact();
    case HapticKind.heavy:
      HapticFeedback.heavyImpact();
    // An iPhone has the three as notifications of its own, which is what the page asks it for there
    // (`notificationFeedback(kind)`): one of them, not a rhythm of impacts laid over it.
    case HapticKind.success:
      _notifies ? HapticFeedback.successNotification() : _pattern([HapticFeedback.lightImpact, HapticFeedback.mediumImpact], 52);
    case HapticKind.warning:
      _notifies ? HapticFeedback.warningNotification() : _pattern([HapticFeedback.mediumImpact, HapticFeedback.mediumImpact], 76);
    case HapticKind.error:
      _notifies ? HapticFeedback.errorNotification() : _pattern([HapticFeedback.heavyImpact, HapticFeedback.heavyImpact, HapticFeedback.heavyImpact], 62);
  }
}

bool get _notifies => defaultTargetPlatform == TargetPlatform.iOS;

void _pattern(List<Future<void> Function()> taps, int everyMs) {
  for (var i = 0; i < taps.length; i++) {
    if (i == 0) {
      taps[i]();
    } else {
      Timer(Duration(milliseconds: everyMs * i), taps[i]);
    }
  }
}

/// Motor and announcement together: what components call directly.
void haptic([HapticKind kind = HapticKind.light]) {
  fireMotor(kind);
  emitFeedback(FeedbackEvent(kind));
}

/// Marks its child as something a press gives feedback on, as `button`, `[role=switch]` and the rest of feedback.ts's
/// `PRESSABLE` are on the page. [kind] null is `data-haptic="none"`, and a disabled control passes [enabled] false.
class HapticTarget extends StatelessWidget {
  const HapticTarget({super.key, this.kind = HapticKind.light, this.enabled = true, required this.child});
  final HapticKind? kind;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => MetaData(metaData: _HapticMark(enabled ? kind : null), behavior: HitTestBehavior.translucent, child: child);
}

class _HapticMark {
  const _HapticMark(this.kind);
  final HapticKind? kind;
}

/// Haptics for every touch press under it, by one listener, so no component needs wiring; and [of], the fire function
/// components call for feedback that is not a press (HapticsProvider.tsx).
class HapticsProvider extends StatefulWidget {
  const HapticsProvider({super.key, this.enabled = false, this.impl, required this.child});

  /// The master switch, wired to a preference. Off by default.
  final bool enabled;

  /// Replaces the motor, for a shell with haptics of its own.
  final HapticFn? impl;
  final Widget child;

  /// The fire function of the nearest provider (`useHaptics`), or the kit's own.
  static HapticFn of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_HapticsScope>()?.fire ?? haptic;

  @override
  State<HapticsProvider> createState() => _HapticsProviderState();
}

class _HapticsProviderState extends State<HapticsProvider> {
  HapticFn get _motor => widget.impl ?? fireMotor;

  void _fire([HapticKind kind = HapticKind.light]) {
    _motor(kind);
    emitFeedback(FeedbackEvent(kind));
  }

  @override
  void initState() {
    super.initState();
    setHapticsEnabled(widget.enabled);
  }

  @override
  void didUpdateWidget(HapticsProvider old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled) setHapticsEnabled(widget.enabled);
  }

  @override
  void dispose() {
    setHapticsEnabled(false);
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || event.kind != PointerDeviceKind.touch) return; // a mouse and a pen have no motor
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is _HapticMark) {
        final kind = (target.metaData as _HapticMark).kind;
        if (kind != null) _motor(kind); // motor only: a visual layer watches the same press itself
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      behavior: HitTestBehavior.translucent,
      child: _HapticsScope(fire: _fire, child: widget.child),
    );
  }
}

class _HapticsScope extends InheritedWidget {
  const _HapticsScope({required this.fire, required super.child});
  final HapticFn fire;

  @override
  bool updateShouldNotify(_HapticsScope old) => false;
}
