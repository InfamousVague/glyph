import 'package:shared_preferences/shared_preferences.dart';

import '../carry/tauri_carry.dart' show CarryPrefs;
import 'stored.dart';

/// [Stored] kept on the device: the app's `localStorage`, over the same store the preferences are kept in
/// (lib/core/preferences.dart), so every `glyph-` key sits together as it does on the page.
///
/// Reads are answered from what was loaded when the app started, which is what makes them synchronous; a write is
/// handed to the device and not waited for, and one that is refused is silence, as the interface says.
class DeviceStored extends Stored {
  DeviceStored(this._kept);

  final SharedPreferences _kept;

  /// The device's storage, read once. Ask before the first frame.
  static Future<DeviceStored> open() async => DeviceStored(await SharedPreferences.getInstance());

  @override
  String? getItem(String key) {
    final value = _kept.get(key);
    return value is String ? value : null;
  }

  @override
  void setItem(String key, String text) {
    _kept.setString(key, text).ignore();
  }

  @override
  void removeItem(String key) {
    _kept.remove(key).ignore();
  }

  @override
  Iterable<String> get allKeys => _kept.getKeys();
}

/// The same store as the carry from the Tauri app writes into it (lib/carry/tauri_carry.dart [CarryPrefs]): each
/// write waited for, and read again from the phone afterwards, so "carried" means kept.
class DeviceCarryPrefs implements CarryPrefs {
  DeviceCarryPrefs(this._kept);

  final SharedPreferences _kept;

  /// The device's storage, for the carry: asked before anything else reads it.
  static Future<DeviceCarryPrefs> open() async => DeviceCarryPrefs(await SharedPreferences.getInstance());

  @override
  String? read(String key) {
    final value = _kept.get(key);
    return value is String ? value : null;
  }

  @override
  Future<bool> write(String key, String value) => _kept.setString(key, value);

  @override
  Future<void> reload() => _kept.reload();
}
