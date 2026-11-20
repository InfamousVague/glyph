// More of Lucide's icons (lucide-static 1.70.0, ISC licence) for what Dev Keyboard draws that Ghost.md's set
// (lucide.g.dart) has not: each element of the svg as a path on the 24 grid, rects and circles washed.
// coverage:ignore-file

import 'app_icon.dart';

abstract final class LucideMore {
  // The pairing with a computer (lib/ui/computers.dart): its QR code, and the relay.
  static const qrCode = LucideIcon('qr-code', ['M4 3H7A1 1 0 0 1 8 4V7A1 1 0 0 1 7 8H4A1 1 0 0 1 3 7V4A1 1 0 0 1 4 3Z', 'M17 3H20A1 1 0 0 1 21 4V7A1 1 0 0 1 20 8H17A1 1 0 0 1 16 7V4A1 1 0 0 1 17 3Z', 'M4 16H7A1 1 0 0 1 8 17V20A1 1 0 0 1 7 21H4A1 1 0 0 1 3 20V17A1 1 0 0 1 4 16Z', 'M21 16h-3a2 2 0 0 0-2 2v3', 'M21 21v.01', 'M12 7v3a2 2 0 0 1-2 2H7', 'M3 12h.01', 'M12 3h.01', 'M12 16v.01', 'M16 12h1', 'M21 12v.01', 'M12 21v-1'], [0, 1, 2]);
  static const cloud = LucideIcon('cloud', ['M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z'], [0]);
  // A picture that is not there (lib/ui/thread.dart), and a voice message's controls.
  static const imageOff = LucideIcon('image-off', ['M2 2 22 22', 'M10.41 10.41a2 2 0 1 1-2.83-2.83', 'M13.5 13.5 6 21', 'M18 12l3 3', 'M3.59 3.59A1.99 1.99 0 0 0 3 5v14a2 2 0 0 0 2 2h14c.55 0 1.052-.22 1.41-.59', 'M21 15V5a2 2 0 0 0-2-2H9'], []);
  static const chartColumn = LucideIcon('chart-column', ['M3 3v16a2 2 0 0 0 2 2h16', 'M18 17V9', 'M13 17V5', 'M8 17v-3'], []);
  static const move = LucideIcon('move', ['M12 2v20', 'm15 19-3 3-3-3', 'm19 9 3 3-3 3', 'M2 12h20', 'm5 9-3 3 3 3', 'm9 5 3-3 3 3'], []);
  static const squareM = LucideIcon('square-m', ['M5 3H19A2 2 0 0 1 21 5V19A2 2 0 0 1 19 21H5A2 2 0 0 1 3 19V5A2 2 0 0 1 5 3Z', 'M8 16V8l4 4 4-4v8'], [0]);
  static const bird = LucideIcon('bird', ['M16 7h.01', 'M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20', 'm20 7 2 .5-2 .5', 'M10 18v3', 'M14 17.75V21', 'M7 18a6 6 0 0 0 3.84-10.61'], []);
  static const target = LucideIcon('target', ['M2 12A10 10 0 1 0 22 12A10 10 0 1 0 2 12Z', 'M6 12A6 6 0 1 0 18 12A6 6 0 1 0 6 12Z', 'M10 12A2 2 0 1 0 14 12A2 2 0 1 0 10 12Z'], [0, 1, 2]);
  static const smile = LucideIcon('smile', ['M2 12A10 10 0 1 0 22 12A10 10 0 1 0 2 12Z', 'M8 14s1.5 2 4 2 4-2 4-2', 'M9 9h.01', 'M15 9h.01'], [0]);
  static const keyboard = LucideIcon('keyboard', ['M10 8h.01', 'M12 12h.01', 'M14 8h.01', 'M16 12h.01', 'M18 8h.01', 'M6 8h.01', 'M7 16h10', 'M8 12h.01', 'M4 4H20A2 2 0 0 1 22 6V18A2 2 0 0 1 20 20H4A2 2 0 0 1 2 18V6A2 2 0 0 1 4 4Z'], [8]);
  static const languages = LucideIcon('languages', ['m5 8 6 6', 'm4 14 6-6 2-3', 'M2 5h12', 'M7 2h1', 'm22 22-5-10-5 10', 'M14 18h6'], []);
  static const settings = LucideIcon('settings', ['M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915', 'M9 12A3 3 0 1 0 15 12A3 3 0 1 0 9 12Z'], [1]);
  static const smartphone = LucideIcon('smartphone', ['M7 2H17A2 2 0 0 1 19 4V20A2 2 0 0 1 17 22H7A2 2 0 0 1 5 20V4A2 2 0 0 1 7 2Z', 'M12 18h.01'], [0]);
  static const vibrate = LucideIcon('vibrate', ['m2 8 2 2-2 2 2 2-2 2', 'm22 8-2 2 2 2-2 2 2 2', 'M9 5H15A1 1 0 0 1 16 6V18A1 1 0 0 1 15 19H9A1 1 0 0 1 8 18V6A1 1 0 0 1 9 5Z'], [2]);
  static const rocket = LucideIcon('rocket', ['M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5', 'M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09', 'M9 12a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.4 22.4 0 0 1-4 2z', 'M9 12H4s.55-3.03 2-4c1.62-1.08 5 .05 5 .05'], []);
  static const hand = LucideIcon('hand', ['M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2', 'M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2', 'M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8', 'M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15'], []);
  static const slidersHorizontal = LucideIcon('sliders-horizontal', ['M10 5H3', 'M12 19H3', 'M14 3v4', 'M16 17v4', 'M21 12h-9', 'M21 19h-5', 'M21 5h-7', 'M8 10v4', 'M8 12H3'], []);
  static const type = LucideIcon('type', ['M12 4v16', 'M4 7V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v2', 'M9 20h6'], []);
  // The video player's mute (lib/ui/video_screen.dart).
  static const volumeX = LucideIcon('volume-x', ['M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z', 'M22 9l-6 6', 'm16 9 6 6'], []);
  // The video player leaving full screen (lib/ui/video_screen.dart).
  static const minimize = LucideIcon('minimize', ['M8 3v3a2 2 0 0 1-2 2H3', 'M21 8h-3a2 2 0 0 1-2-2V3', 'M3 16h3a2 2 0 0 1 2 2v3', 'M16 21v-3a2 2 0 0 1 2-2h3'], []);
  // Settings › Voice and video's Music mode.
  static const music = LucideIcon('music', ['M9 18V5l12-2v13', 'M3 18A3 3 0 1 0 9 18A3 3 0 1 0 3 18Z', 'M15 16A3 3 0 1 0 21 16A3 3 0 1 0 15 16Z'], [1, 2]);
  static const audioLines = LucideIcon('audio-lines', ['M2 10v3', 'M6 6v11', 'M10 3v18', 'M14 8v7', 'M18 5v13', 'M22 10v3'], []);
  static const spellCheck = LucideIcon('spell-check', ['m20 15-5.5 5.5L12 18', 'm4 16 6-12 5.115 10.23', 'M6 12h8'], []);
  static const braces = LucideIcon('braces', ['M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1', 'M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1'], []);
  static const refreshCw = LucideIcon('refresh-cw', ['M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8', 'M21 3v5h-5', 'M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16', 'M8 16H3v5'], []);
  static const download = LucideIcon('download', ['M12 15V3', 'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4', 'm7 10 5 5 5-5'], []);
  static const store = LucideIcon('store', ['M15 21v-5a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v5', 'M17.774 10.31a1.12 1.12 0 0 0-1.549 0 2.5 2.5 0 0 1-3.451 0 1.12 1.12 0 0 0-1.548 0 2.5 2.5 0 0 1-3.452 0 1.12 1.12 0 0 0-1.549 0 2.5 2.5 0 0 1-3.77-3.248l2.889-4.184A2 2 0 0 1 7 2h10a2 2 0 0 1 1.653.873l2.895 4.192a2.5 2.5 0 0 1-3.774 3.244', 'M4 10.95V19a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8.05'], []);
  static const wandSparkles = LucideIcon('wand-sparkles', ['m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72', 'm14 7 3 3', 'M5 6v4', 'M19 14v4', 'M10 2v2', 'M7 8H3', 'M21 16h-4', 'M11 3H9'], []);
  static const textCursorInput = LucideIcon('text-cursor-input', ['M12 20h-1a2 2 0 0 1-2-2 2 2 0 0 1-2 2H6', 'M13 8h7a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-7', 'M5 16H4a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h1', 'M6 4h1a2 2 0 0 1 2 2 2 2 0 0 1 2-2h1', 'M9 6v12'], []);
  static const moveHorizontal = LucideIcon('move-horizontal', ['m18 8 4 4-4 4', 'M2 12h20', 'm6 8-4 4 4 4'], []);
  static const pointer = LucideIcon('pointer', ['M22 14a8 8 0 0 1-8 8', 'M18 11v-1a2 2 0 0 0-2-2a2 2 0 0 0-2 2', 'M14 10V9a2 2 0 0 0-2-2a2 2 0 0 0-2 2v1', 'M10 9.5V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v10', 'M18 11a2 2 0 1 1 4 0v3a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15'], []);
  static const badgeCheck = LucideIcon('badge-check', ['M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z', 'm16 9-5.5 5.5L8 12'], []);
  static const cpu = LucideIcon('cpu', ['M12 20v2', 'M12 2v2', 'M17 20v2', 'M17 2v2', 'M2 12h2', 'M2 17h2', 'M2 7h2', 'M20 12h2', 'M20 17h2', 'M20 7h2', 'M7 20v2', 'M7 2v2', 'M6 4H18A2 2 0 0 1 20 6V18A2 2 0 0 1 18 20H6A2 2 0 0 1 4 18V6A2 2 0 0 1 6 4Z', 'M9 8H15A1 1 0 0 1 16 9V15A1 1 0 0 1 15 16H9A1 1 0 0 1 8 15V9A1 1 0 0 1 9 8Z'], [12, 13]);
  static const hardDriveDownload = LucideIcon('hard-drive-download', ['M12 2v8', 'm16 6-4 4-4-4', 'M4 14H20A2 2 0 0 1 22 16V20A2 2 0 0 1 20 22H4A2 2 0 0 1 2 20V16A2 2 0 0 1 4 14Z', 'M6 18h.01', 'M10 18h.01'], [2]);
  static const circleCheck = LucideIcon('circle-check', ['M2 12A10 10 0 1 0 22 12A10 10 0 1 0 2 12Z', 'm16 9-5.5 5.5L8 12'], [0]);
  static const circlePlus = LucideIcon('circle-plus', ['M2 12A10 10 0 1 0 22 12A10 10 0 1 0 2 12Z', 'M8 12h8', 'M12 8v8'], [0]);
  static const trash2 = LucideIcon('trash-2', ['M10 11v6', 'M14 11v6', 'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6', 'M3 6h18', 'M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'], []);
  static const shieldCheck = LucideIcon('shield-check', ['M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z', 'm9 12 2 2 4-4'], []);
  static const wifiOff = LucideIcon('wifi-off', ['M12 20h.01', 'M8.5 16.429a5 5 0 0 1 7 0', 'M5 12.859a10 10 0 0 1 5.17-2.69', 'M19 12.859a10 10 0 0 0-2.007-1.523', 'M2 8.82a15 15 0 0 1 4.177-2.643', 'M22 8.82a15 15 0 0 0-11.288-3.764', 'm2 2 20 20'], []);
  static const brain = LucideIcon('brain', ['M12 18V5', 'M15 13a4.17 4.17 0 01-3-4 4.17 4.17 0 01-3 4', 'M17.707 6.294A3 3 0 1012 5a3 3 0 10-5.707 1.294', 'M17.996 5.125a4 4 0 012.526 5.77', 'M18 18a4 4 0 002-7.465', 'M19.967 17.482a4 4 0 11-7.967.517 4 4 0 11-7.967-.517', 'M6 18a4 4 0 01-2-7.465', 'M6.004 5.125a4 4 0 00-2.526 5.77'], []);
  // Kinds of text, for the list's filter (lib/plugins/kinds.dart) and its button.
  static const receipt = LucideIcon('receipt', ['M12 17V7', 'M16 8h-6a2 2 0 0 0 0 4h4a2 2 0 0 1 0 4H8', 'M4 3a1 1 0 0 1 1-1 1.3 1.3 0 0 1 .7.2l.933.6a1.3 1.3 0 0 0 1.4 0l.934-.6a1.3 1.3 0 0 1 1.4 0l.933.6a1.3 1.3 0 0 0 1.4 0l.933-.6a1.3 1.3 0 0 1 1.4 0l.934.6a1.3 1.3 0 0 0 1.4 0l.933-.6A1.3 1.3 0 0 1 19 2a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1 1.3 1.3 0 0 1-.7-.2l-.933-.6a1.3 1.3 0 0 0-1.4 0l-.934.6a1.3 1.3 0 0 1-1.4 0l-.933-.6a1.3 1.3 0 0 0-1.4 0l-.933.6a1.3 1.3 0 0 1-1.4 0l-.934-.6a1.3 1.3 0 0 0-1.4 0l-.933.6a1.3 1.3 0 0 1-.7.2 1 1 0 0 1-1-1z'], [2]);
  static const package = LucideIcon('package', ['M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z', 'M12 22V12', 'M3.29 7 12 12 20.71 7', 'm7.5 4.27 9 5.15'], [0]);
  static const landmark = LucideIcon('landmark', ['M10 18v-7', 'M11.119 2.205a2 2 0 0 1 1.762 0l7.84 3.846A.5.5 0 0 1 20.5 7h-17a.5.5 0 0 1-.22-.949z', 'M14 18v-7', 'M18 18v-7', 'M3 22h18', 'M6 18v-7'], [1]);
  static const circleDollarSign = LucideIcon('circle-dollar-sign', ['M2 12A10 10 0 1 0 22 12A10 10 0 1 0 2 12Z', 'M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8', 'M12 18V6'], [0]);
  static const calendarCheck = LucideIcon('calendar-check', ['M8 2v3', 'M16 2v3', 'M5 3H19A2 2 0 0 1 21 5V19A2 2 0 0 1 19 21H5A2 2 0 0 1 3 19V5A2 2 0 0 1 5 3Z', 'M3 9h18', 'm9 15 2 2 4-4'], [2]);
  static const funnel = LucideIcon('funnel', ['M10 20a1 1 0 0 0 .553.895l2 1A1 1 0 0 0 14 21v-7a2 2 0 0 1 .517-1.341L21.74 4.67A1 1 0 0 0 21 3H3a1 1 0 0 0-.742 1.67l7.225 7.989A2 2 0 0 1 10 14z'], [0]);
  // The day's plugins (lib/plugins/replies.dart, day.dart, strangers.dart, quiet.dart).
  static const reply = LucideIcon('reply', ['M20 18v-2a4 4 0 0 0-4-4H4', 'm9 17-5-5 5-5'], []);
  static const sunMedium = LucideIcon('sun-medium', ['M8 12A4 4 0 1 0 16 12A4 4 0 1 0 8 12Z', 'M12 3v1', 'M12 20v1', 'M3 12h1', 'M20 12h1', 'm18.364 5.636-.707.707', 'm6.343 17.657-.707.707', 'm5.636 5.636.707.707', 'm17.657 17.657.707.707'], [0]);
  static const calendarClock = LucideIcon('calendar-clock', ['M16 14v2.2l1.6 1', 'M16 2v3', 'M21 7.338V5a2 2 0 00-2-2H5a2 2 0 00-2 2v14a2 2 0 002 2h2.338', 'M3 9h5.859', 'M8 2v3', 'M10 16A6 6 0 1 0 22 16A6 6 0 1 0 10 16Z'], [5]);
  // Food delivery texts (lib/plugins/kinds.dart), and Messages on the list's toggle (lib/plugins/ui.dart).
  static const utensils = LucideIcon('utensils', ['M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2', 'M7 2v20', 'M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7'], []);
  static const messageCircle = LucideIcon('message-circle', ['M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719'], []);
  // Voice and video channels (lib/voice, lib/ui/voice_screen.dart).
  static const headphones = LucideIcon('headphones', ['M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3'], []);
  static const headphoneOff = LucideIcon('headphone-off', ['M21 14h-1.343', 'M9.128 3.47A9 9 0 0 1 21 12v3.343', 'm2 2 20 20', 'M20.414 20.414A2 2 0 0 1 19 21h-1a2 2 0 0 1-2-2v-3', 'M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 2.636-6.364'], []);
  static const phoneCall = LucideIcon('phone-call', ['M13 2a9 9 0 0 1 9 9', 'M13 6a5 5 0 0 1 5 5', 'M13.832 16.568a1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233 14 14 0 0 0 6.392 6.384'], []);
  static const phoneOff = LucideIcon('phone-off', ['M10.1 13.9a14 14 0 0 0 3.732 2.668 1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2 18 18 0 0 1-12.728-5.272', 'M22 2 2 22', 'M4.76 13.582A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233 14 14 0 0 0 .244.473'], []);
  static const videoOff = LucideIcon('video-off', ['M10.66 6H14a2 2 0 0 1 2 2v2.5l5.248-3.062A.5.5 0 0 1 22 7.87v8.196', 'M16 16a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h2', 'm2 2 20 20'], []);
  static const micOff = LucideIcon('mic-off', ['M12 19v3', 'M15 9.34V5a3 3 0 0 0-5.68-1.33', 'M16.95 16.95A7 7 0 0 1 5 12v-2', 'M18.89 13.23A7 7 0 0 0 19 12v-2', 'm2 2 20 20', 'M9 9v3a3 3 0 0 0 5.12 2.12'], []);
  // The Cleaner plugin (lib/plugins/cleaner.dart).
  static const brushCleaning = LucideIcon('brush-cleaning', ['m16 22-1-4', 'M19 14a1 1 0 0 0 1-1v-1a2 2 0 0 0-2-2h-3a1 1 0 0 1-1-1V4a2 2 0 0 0-4 0v5a1 1 0 0 1-1 1H6a2 2 0 0 0-2 2v1a1 1 0 0 0 1 1', 'M19 14H5l-1.973 6.767A1 1 0 0 0 4 22h16a1 1 0 0 0 .973-1.233z', 'm8 22 1-4'], []);
  static const userRoundSearch = LucideIcon('user-round-search', ['M5 8A5 5 0 1 0 15 8A5 5 0 1 0 5 8Z', 'M2 21a8 8 0 0 1 10.434-7.62', 'M15 18A3 3 0 1 0 21 18A3 3 0 1 0 15 18Z', 'm22 22-1.9-1.9'], [0, 2]);
  // Share feedback (lib/ui/feedback_screen.dart): its button, and a bug.
  static const messageSquareWarning = LucideIcon('message-square-warning', ['M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z', 'M12 7v2', 'M12 13h.01'], [0]);
  static const bug = LucideIcon('bug', ['m8 2 1.88 1.88', 'M14.12 3.88 16 2', 'M9 7.13v-1a3.003 3.003 0 1 1 6 0v1', 'M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6', 'M12 20v-9', 'M6.53 9C4.6 8.8 3 7.1 3 5', 'M6 13H2', 'M3 21c0-2.1 1.7-3.9 3.8-4', 'M20.97 5c0 2.1-1.6 3.8-3.5 4', 'M22 13h-4', 'M17.2 17c2.1.1 3.8 1.9 3.8 4'], []);
}
