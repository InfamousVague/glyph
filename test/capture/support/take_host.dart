import 'package:ghost_md/capture/command.dart' show Placement;
import 'package:ghost_md/capture/offers.dart' show Offer;
import 'package:ghost_md/capture/take_host.dart';

/// A host for a Take (capture/take.dart) under test: every member does nothing until a test says otherwise by
/// passing its own. A port of the web's `src/test/takeHost.ts`, whose `overrides: Partial<TakeHost<N>>` is the named
/// parameters here.
///
/// Each test of the take cares about one or two of the host's members - the offer it made, the chip it showed, the
/// note it changed. So the quiet defaults are written once, here, and a member the interface gains or loses is one
/// edit.
TakeHost<N> quietHost<N extends Object>({
  void Function(RouteView? view)? route,
  void Function(Offer<N>? offer)? offer,
  void Function(Haptic kind)? haptic,
  void Function()? changed,
  void Function(N note, String spoken, Placement placement)? addItems,
}) => _QuietHost<N>(route, offer, haptic, changed, addItems);

class _QuietHost<N extends Object> implements TakeHost<N> {
  _QuietHost(this._route, this._offer, this._haptic, this._changed, this._addItems);

  final void Function(RouteView? view)? _route;
  final void Function(Offer<N>? offer)? _offer;
  final void Function(Haptic kind)? _haptic;
  final void Function()? _changed;
  final void Function(N note, String spoken, Placement placement)? _addItems;

  @override
  void route(RouteView? view) => _route?.call(view);

  @override
  void offer(Offer<N>? offer) => _offer?.call(offer);

  @override
  void haptic(Haptic kind) => _haptic?.call(kind);

  @override
  void changed() => _changed?.call();

  @override
  void addItems(N note, String spoken, Placement placement) => _addItems?.call(note, spoken, placement);
}
