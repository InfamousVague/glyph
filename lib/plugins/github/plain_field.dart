/// The plain line of text a plugin's page in Settings types into: GitHub's token, a Slack channel's name and its
/// webhook. A port of the `.field` rule both `GitHubPane.module.css` and `SlackPane.module.css` carry (the same
/// rule twice on the page; once here, and the Slack page takes it from this file).
///
/// `inline-size: 100%; min-block-size: var(--glacier-space-10); padding-inline: var(--glacier-space-3);
/// border: var(--glacier-hairline) solid var(--glacier-border); border-radius: var(--glacier-radius-md);
/// background: var(--glacier-surface); color: var(--glacier-text); font: inherit`, and focused,
/// `outline: 2px solid var(--glacier-focus-ring); outline-offset: 1px`.
///
/// What differs:
/// - The text is a [TextEditingController]'s, which the page holds, where the page's was a value and an `onChange`.
/// - The placeholder is the grey a browser gives one (`#757575`, measured on the page in both themes).
/// - A secret one (`type="password"`) is drawn as dots, is not said by a screen reader, is not learnt by the
///   keyboard, and offers no copy.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../settings/kit/settings_type.dart';

class PlainField extends StatefulWidget {
  const PlainField({super.key, required this.label, required this.controller, required this.placeholder, this.secret = false, this.onSubmitted});

  /// `aria-label`: what the field is called.
  final String label;
  final TextEditingController controller;
  final String placeholder;

  /// `type="password"`.
  final bool secret;
  final VoidCallback? onSubmitted;

  @override
  State<PlainField> createState() => _PlainFieldState();
}

class _PlainFieldState extends State<PlainField> implements TextSelectionGestureDetectorBuilderDelegate {
  final FocusNode _focus = FocusNode(debugLabel: 'PlainField');
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_redraw);
    widget.controller.addListener(_redraw);
  }

  @override
  void didUpdateWidget(PlainField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_redraw);
      widget.controller.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    _focus.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = pageText(t, t.lenOf('1rem'), color: t.color('glacier-text'));
    final focused = _focus.hasFocus;
    final empty = widget.controller.text.isEmpty;
    final radius = t.radius('md');
    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: _focus,
      style: style,
      cursorColor: t.color('glacier-text'),
      cursorWidth: 1,
      backgroundCursorColor: t.color('glacier-text-subtle'),
      selectionColor: focused ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      obscureText: widget.secret,
      // `autoCapitalize="off" autoCorrect="off" spellCheck={false}`
      keyboardType: widget.secret ? TextInputType.visiblePassword : TextInputType.text,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      maxLines: 1,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      onSelectionChanged: (selection, cause) {
        final touch = switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
          _ => false,
        };
        final show = touch && !empty && (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || cause == SelectionChangedCause.tap);
        if (_handles != show) setState(() => _handles = show);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
    );
    return GlacierFocusRing(
      visible: focused,
      radius: radius,
      offset: 1,
      child: Container(
        constraints: BoxConstraints(minHeight: t.space(10)),
        padding: EdgeInsets.symmetric(horizontal: t.space(3)),
        decoration: BoxDecoration(
          color: t.color('glacier-surface'),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: t.color('glacier-border'), width: t.len('glacier-hairline')),
        ),
        alignment: AlignmentDirectional.centerStart,
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: _gestures.buildGestureDetector(
            behavior: HitTestBehavior.translucent,
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                if (empty) ExcludeSemantics(child: Text(widget.placeholder, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: const Color(0xFF757575)))),
                DefaultTextEditingShortcuts(
                  child: Semantics(
                    label: widget.label,
                    textField: true,
                    obscured: widget.secret,
                    onTap: () {
                      _focus.requestFocus();
                      editableTextKey.currentState?.requestKeyboard();
                    },
                    child: editable,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
