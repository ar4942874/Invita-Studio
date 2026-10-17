import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../studio_theme.dart';

/// Announces [message] to screen readers on platforms that support it.
///
/// Used for asynchronous progress that a sighted user sees as a spinner or a
/// status line, so assistive technology is told the same thing.
void announceForAccessibility(BuildContext context, String message) {
  if (!MediaQuery.supportsAnnounceOf(context)) return;
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
}

class BoundInput extends StatefulWidget {
  const BoundInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.maxLines = 1,
    this.maxLength = 220,
    this.hint,
    this.showLabel = true,
  });
  final String value, label;
  final ValueChanged<String> onChanged;
  final int maxLines, maxLength;
  final String? hint;
  final bool showLabel;
  @override
  State<BoundInput> createState() => _BoundInputState();
}

class _BoundInputState extends State<BoundInput> {
  late final TextEditingController _text;
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant BoundInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value) {
      final offset = math.max(
        0,
        math.min(_text.selection.baseOffset, widget.value.length),
      );
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.showLabel) ...[
        Text(
          widget.label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 7),
      ],
      Semantics(
        label: widget.label,
        child: TextField(
          controller: _text,
          onChanged: widget.onChanged,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          buildCounter: (
            context, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) => null,
          style: const TextStyle(fontSize: 12, height: 1.5),
          decoration: InputDecoration(
            hintText: widget.hint,
            semanticCounterText:
                '${_text.text.length} of ${widget.maxLength} characters',
          ),
        ),
      ),
    ],
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ],
  );
}

class TinyLabel extends StatelessWidget {
  const TinyLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: color ?? StudioColors.meta,
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: StudioColors.accent,
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(
      Icons.spa_outlined,
      size: size * .59,
      color: StudioColors.accentOn,
    ),
  );
}

class HintBox extends StatelessWidget {
  const HintBox(
    this.text, {
    super.key,
    this.icon = Icons.lightbulb_outline,
    this.warning = false,
  });
  final String text;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: warning ? StudioColors.warningSoft : StudioColors.wash,
      borderRadius: StudioShape.smRadius,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: warning ? StudioColors.warning : StudioColors.accent,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              color: StudioColors.muted,
              height: 1.6,
            ),
          ),
        ),
      ],
    ),
  );
}
