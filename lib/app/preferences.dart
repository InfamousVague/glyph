import 'package:flutter/foundation.dart';

/// The look a person chose, as the web app's preferences name it (src/app/core/preferences.ts): each field is a
/// `data-` attribute on the page there, and on the theme here.
@immutable
class AppPreferences {
  const AppPreferences({this.theme = 'system', this.density = 'default', this.textSize = 'default', this.rounding = 'default', this.haptics = true});

  /// `system`, `light`, `dark`, or a named theme: `dawn`, `boreal`, `ember`.
  final String theme;

  /// `default`, `extra-compact`, `compact`, `spacious`, `more-space`.
  final String density;

  /// `default`, `larger`, `largest`.
  final String textSize;

  /// `default`, `square`, `soft`, `rounder`.
  final String rounding;
  final bool haptics;

  static const presets = {'dawn': 'light', 'boreal': 'dark', 'ember': 'dark'};

  AppPreferences copyWith({String? theme, String? density, String? textSize, String? rounding, bool? haptics}) => AppPreferences(
        theme: theme ?? this.theme,
        density: density ?? this.density,
        textSize: textSize ?? this.textSize,
        rounding: rounding ?? this.rounding,
        haptics: haptics ?? this.haptics,
      );

  /// The page's attributes for these choices (preferences.ts `applyPreferences`). `theme` is left out for `system`,
  /// so the theme follows the phone's; a named theme is stamped twice, as its side and as its name.
  Map<String, String> get attrs => {
        'platform': defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS ? 'mobile' : 'desktop',
        'note-font': 'maple',
        'tabs': 'on',
        if (presets.containsKey(theme)) ...{'theme': presets[theme]!, 'theme-preset': theme} else if (theme != 'system') 'theme': theme,
        if (density != 'default') 'density': density,
        if (textSize != 'default') 'text-size': textSize,
        if (rounding != 'default') 'rounding': rounding,
      };
}

final ValueNotifier<AppPreferences> preferences = ValueNotifier(const AppPreferences());
