import 'dart:io';

/// Opens [url] in a private window of a browser on this computer (Matt, 2026-11-15: "if possible prompt to open the link
/// incognito"): Firefox, Chrome, Edge, Brave or Vivaldi, the first found, by its own switch. Safari has no such switch
/// (its private window is File › New Private Window), so on a Mac without the others nothing opens and false is said.
Future<bool> openPrivately(String url) async {
  try {
    if (Platform.isMacOS) {
      // Firefox first: Chrome-based browsers may bind the sign-in to themselves (Device Bound Session Credentials),
      // and Google then refuses it from the helper; mautrix-gmessages' docs say Firefox works.
      const browsers = [
        ('Firefox', '--private-window'),
        ('Google Chrome', '--incognito'),
        ('Microsoft Edge', '--inprivate'),
        ('Brave Browser', '--incognito'),
        ('Vivaldi', '--incognito'),
      ];
      for (final (app, flag) in browsers) {
        if (!Directory('/Applications/$app.app').existsSync() && !Directory('${Platform.environment['HOME']}/Applications/$app.app').existsSync()) continue;
        final r = await Process.run('open', ['-na', app, '--args', flag, url]);
        if (r.exitCode == 0) return true;
      }
      return false;
    }
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ?? '';
      final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final pf86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      final browsers = [
        ('$pf\\Mozilla Firefox\\firefox.exe', '--private-window'),
        ('$pf\\Google\\Chrome\\Application\\chrome.exe', '--incognito'),
        ('$local\\Google\\Chrome\\Application\\chrome.exe', '--incognito'),
        ('$pf\\BraveSoftware\\Brave-Browser\\Application\\brave.exe', '--incognito'),
        ('$pf86\\Microsoft\\Edge\\Application\\msedge.exe', '--inprivate'),
        ('$pf\\Microsoft\\Edge\\Application\\msedge.exe', '--inprivate'),
      ];
      for (final (exe, flag) in browsers) {
        if (!File(exe).existsSync()) continue;
        await Process.start(exe, [flag, url], mode: ProcessStartMode.detached);
        return true;
      }
      return false;
    }
  } catch (_) {}
  return false;
}
