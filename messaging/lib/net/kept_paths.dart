/// Where a device keeps what is out of any backup (kept_files.dart), worked out from what it is: apart from the files
/// themselves, so a test can ask it of any platform.
library;

/// The folder [name] is kept in on a device of [os] (`android`, `ios`, `macos`, `windows`, `linux`): [data] is the app's
/// own folder on Android (Directory.systemTemp's parent), [env] the process's environment. Null where none can be
/// named.
String? keptPathFor(String name, {required String os, required String data, Map<String, String> env = const {}}) {
  String? join(String? base, List<String> parts) => base == null || base.isEmpty ? null : [base, ...parts].join(os == 'windows' ? r'\' : '/');
  return switch (os) {
    'android' => join(data, ['no_backup', name]),
    'ios' || 'macos' => join(env['HOME'] ?? data, ['Library', 'Caches', 'Ghost Messaging', name]),
    'windows' => join(env['LOCALAPPDATA'], ['Ghost Messaging', name]),
    'linux' => join(env['XDG_CACHE_HOME'] ?? (env['HOME'] == null ? null : '${env['HOME']}/.cache'), ['ghost-messaging', name]),
    _ => null,
  };
}
