import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/front_tickers.dart';

class _Clock extends StatefulWidget {
  const _Clock(this.ticks);
  final ValueNotifier<int> ticks;
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => widget.ticks.value++)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  Future<int> ticksOver(WidgetTester tester, ValueNotifier<int> ticks) async {
    final before = ticks.value;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return ticks.value - before;
  }

  testWidgets('on Android a clock stops when the app is no longer in front, and goes on when it is', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ticks = ValueNotifier(0);
    await tester.pumpWidget(FrontTickers(child: _Clock(ticks)));
    expect(await ticksOver(tester, ticks), greaterThan(0));
    // Android's onPause: the window is still there and its surface is about to go.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(await ticksOver(tester, ticks), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(await ticksOver(tester, ticks), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('elsewhere a window that is not focused keeps moving', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final ticks = ValueNotifier(0);
    await tester.pumpWidget(FrontTickers(child: _Clock(ticks)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(await ticksOver(tester, ticks), greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
