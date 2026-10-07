import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/app_icon.dart';

export 'package:ghost_md/art/app_icon.dart' show AppIcon, LucideIcon;
export 'package:ghost_md/art/lucide.g.dart' show Lucide;

/// Every [AppIcon] drawing [icon]: what `find.byIcon` was while the icons were a font's glyphs.
Finder byLucide(LucideIcon icon) => find.byWidgetPredicate((Widget widget) => widget is AppIcon && widget.icon == icon, description: 'AppIcon(${icon.name})');
