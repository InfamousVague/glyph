/// The phone's own position: the [Locator] over the channel `ghost_md/location` (Kotlin's `Position`). Ports the
/// Android half of `locate` in `src/app/core/location.ts` (`readAccess`, `askAndroid`, then the fix) with
/// ../glyph's `location/LocationAccess.kt` behind it.
///
/// What differs:
/// - The page asked its WebView for the position (`navigator.geolocation.getCurrentPosition`); the phone's half
///   answers it here (`fix`), from the platform's own providers, with the page's two numbers handed over: a fix two
///   minutes old is taken as it is, and fifteen seconds is as long as the device may take.
/// - The prompt's answer comes back as the call's own (`request` answers the state once Android has), where the
///   page waited for `window.__glyph.location()` or for the app to come back.
/// - A run with no phone half (a desktop, a test) cannot locate at all: [PhoneLocator.cannot] is `none` until the
///   channel has answered once ([PhoneLocator.attach]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'location.dart';

/// The channel the phone's position answers on.
const MethodChannel positionChannel = MethodChannel('ghost_md/location');

/// How long the device may take over a fix (`FIX_TIMEOUT_MS`).
const int fixTimeoutMs = 15000;

/// A fix this recent is taken as it is: a person does not move far in two minutes (`FIX_MAX_AGE_MS`).
const int fixMaxAgeMs = 120000;

/// The most a fix may take, prompt and all (`FIX_CAP_MS`).
const Duration fixCap = Duration(seconds: 60);

/// How long Android's prompt is waited for before the state is read as it stands (`ASK_TIMEOUT_MS`).
const Duration askTimeout = Duration(seconds: 90);

LocationAccess _accessOf(Object? answer) => switch (answer) {
      'granted' => LocationAccess.granted,
      'approximate' => LocationAccess.approximate,
      'blocked' => LocationAccess.blocked,
      _ => LocationAccess.ask,
    };

/// Where the phone is, asked of its own half.
class PhoneLocator implements Locator {
  PhoneLocator({MethodChannel channel = positionChannel}) : _channel = channel;

  final MethodChannel _channel;
  bool _attached = false;

  /// Asks the phone's half whether it is there: a build with none cannot locate. Answers this, for a chain.
  Future<PhoneLocator> attach() async {
    try {
      await _channel.invokeMethod<String>('access');
      _attached = true;
    } on MissingPluginException {
      _attached = false;
    } on PlatformException {
      _attached = true;
    }
    return this;
  }

  @override
  LocateFailure? get cannot => _attached ? null : LocateFailure.none;

  @override
  bool get onPhone => _attached && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<LocationAccess?> access() async {
    if (!_attached) return null;
    try {
      return _accessOf(await _channel.invokeMethod<String>('access'));
    } catch (_) {
      return LocationAccess.ask;
    }
  }

  /// Raises Android's prompt and waits for its answer (`askAndroid`).
  Future<LocationAccess> _ask() async {
    try {
      return _accessOf(await _channel.invokeMethod<String>('request').timeout(askTimeout));
    } catch (_) {
      return await access() ?? LocationAccess.ask;
    }
  }

  @override
  Future<Fix> fix({bool quiet = false}) async {
    if (!_attached) throw const LocateError(LocateFailure.none);
    var state = await access() ?? LocationAccess.ask;
    if (state == LocationAccess.blocked) throw const LocateError(LocateFailure.blocked);
    if (state == LocationAccess.ask) {
      // A quiet ask that would have needed the prompt: nobody refused anything, and the next new note may ask.
      if (quiet) throw const LocateError(LocateFailure.unavailable);
      state = await _ask();
    }
    if (state == LocationAccess.blocked) throw const LocateError(LocateFailure.blocked);
    if (state == LocationAccess.ask) throw const LocateError(LocateFailure.refused);
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('fix', <String, Object?>{'maxAgeMs': fixMaxAgeMs, 'timeoutMs': fixTimeoutMs}).timeout(fixCap);
      final lat = answer?['lat'], lon = answer?['lon'];
      if (lat is! num || lon is! num) throw const LocateError(LocateFailure.unavailable);
      final accuracy = answer?['accuracy'], at = answer?['at'];
      return Fix(lat: lat.toDouble(), lon: lon.toDouble(), accuracy: accuracy is num ? accuracy.toDouble() : 0, at: at is num ? at.toInt() : DateTime.now().millisecondsSinceEpoch);
    } on TimeoutException {
      throw const LocateError(LocateFailure.timeout);
    } on PlatformException catch (failure) {
      throw LocateError(switch (failure.code) { 'refused' => LocateFailure.refused, 'timeout' => LocateFailure.timeout, _ => LocateFailure.unavailable });
    } on MissingPluginException {
      throw const LocateError(LocateFailure.none);
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
