import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../../application/studio_controller.dart';
import '../../domain/invitation_template.dart';
import '../focus_light_sheet.dart';
import '../guide/guide_scope.dart';
import '../guide/guide_stop.dart';
import '../studio_theme.dart';
import 'controls.dart';
import 'document_preview.dart';
import 'focus_light_layer.dart';

class ArtboardWorkspace extends StatefulWidget {
  const ArtboardWorkspace({
    super.key,
    required this.studio,
    required this.onReset,
    required this.onStyle,
    this.compact = false,
    this.hasInspector = true,
  });
  final StudioController studio;
  final VoidCallback onReset, onStyle;
  final bool compact, hasInspector;
  @override
  State<ArtboardWorkspace> createState() => _ArtboardWorkspaceState();
}

class _ArtboardWorkspaceState extends State<ArtboardWorkspace> {
  final _transform = TransformationController();
  double _zoom = 1;
  Size _viewport = Size.zero;
  void _setZoom(double zoom) {
    final z = zoom.clamp(.5, 2.0);
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, z)
      ..setEntry(1, 1, z)
      ..setEntry(0, 3, _viewport.width * (1 - z) / 2)
      ..setEntry(1, 3, _viewport.height * (1 - z) / 2);
    setState(() => _zoom = z);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _preview() {
    FocusScope.of(context).unfocus();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: StudioColors.canvas,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 10, 0),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 18),
                  const SizedBox(width: 9),
                  const Text(
                    'Invitation preview',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: DocumentPreview(
                  document: widget.studio.document,
                  // This one is inspectable at full size.
                  decodeWidth: 1080,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studio = widget.studio;
    return Column(
      children: [
        if (!widget.compact)
          Container(
            color: StudioColors.wash,
            padding: const EdgeInsets.fromLTRB(28, 25, 28, 23),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TinyLabel(
                        'A little love. A lasting impression.',
                        color: StudioColors.accent,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'An invitation, unmistakably you.',
                        style: TextStyle(
                          fontFamily: 'CormorantGaramond',
                          fontSize: 31,
                          height: 1.05,
                          letterSpacing: -.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: StudioColors.border),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 12,
                        color: StudioColors.accent,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'IMAGE STUDIO',
                        style: TextStyle(
                          fontSize: 8,
                          letterSpacing: 1,
                          color: StudioColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Container(
          height: 57,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: StudioColors.border),
              bottom: BorderSide(color: StudioColors.border),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Undo (Ctrl / Cmd Z)',
                visualDensity: widget.compact ? VisualDensity.compact : null,
                onPressed: studio.canUndo ? studio.undo : null,
                icon: const Icon(Icons.undo, size: 18),
              ),
              IconButton(
                tooltip: 'Redo (Ctrl / Cmd Shift Z)',
                visualDensity: widget.compact ? VisualDensity.compact : null,
                onPressed: studio.canRedo ? studio.redo : null,
                icon: const Icon(Icons.redo, size: 18),
              ),
              Container(
                width: 1,
                height: 20,
                color: StudioColors.border,
                margin: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 4 : 10,
                ),
              ),
              const Icon(
                Icons.crop_portrait_outlined,
                size: 15,
                color: StudioColors.muted,
              ),
              const SizedBox(width: 7),
              GuideTarget(
                anchor: GuideAnchors.format,
                radius: 8,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<InvitationFormat>(
                  value: studio.format,
                  isDense: true,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11,
                    color: StudioColors.ink,
                  ),
                  icon: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.keyboard_arrow_down, size: 15),
                  ),
                  items: InvitationFormat.values
                      .map(
                        (f) => DropdownMenuItem(
                          value: f,
                          child: Text('${f.label} · ${f.ratio}'),
                        ),
                      )
                      .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        FocusScope.of(context).unfocus();
                        studio.chooseFormat(v);
                        _setZoom(1);
                      }
                    },
                  ),
                ),
              ),
              SizedBox(width: widget.compact ? 0 : 4),
              GuideTarget(
                anchor: GuideAnchors.lights,
                radius: 8,
                child: _lightsButton(),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Preview invitation',
                visualDensity: widget.compact ? VisualDensity.compact : null,
                onPressed: _preview,
                icon: const Icon(Icons.visibility_outlined, size: 19),
              ),
              if (!widget.compact)
                IconButton(
                  tooltip: 'Reset layout',
                  onPressed: widget.onReset,
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
              if (!widget.hasInspector && !widget.compact)
                IconButton(
                  tooltip: 'Style text',
                  onPressed: widget.onStyle,
                  icon: const Icon(Icons.tune, size: 19),
                ),
            ],
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.25),
                radius: .9,
                colors: [StudioColors.surface, StudioColors.canvas],
              ),
            ),
            child: CustomPaint(
              painter: const _DotGrid(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewport = constraints.biggest;
                  final gap = widget.compact ? 22.0 : 36.0;
                  final ratio = studio.document.width / studio.document.height;
                  final height = math.max(
                    20.0,
                    math.min(
                      constraints.maxHeight - gap * 2,
                      (constraints.maxWidth - gap * 2) / ratio,
                    ),
                  );
                  final width = height * ratio;
                  return Stack(
                    children: [
                      Positioned(
                        left: widget.compact ? 13 : 25,
                        top: 15,
                        child: Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: StudioColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'LIVE PREVIEW',
                              style: TextStyle(
                                fontSize: 8,
                                letterSpacing: 1.1,
                                color: StudioColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InteractiveViewer(
                        transformationController: _transform,
                        panEnabled: _zoom > 1,
                        scaleEnabled: false,
                        minScale: .5,
                        maxScale: 2,
                        boundaryMargin: const EdgeInsets.all(500),
                        child: Center(
                          child: Container(
                            width: width,
                            height: height,
                            decoration: BoxDecoration(
                              color: decodeDocumentColor(studio.template.paper),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: StudioColors.ink.withValues(alpha: .13),
                                  blurRadius: 26,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .04),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: RepaintBoundary(
                              child: MediaQuery.withNoTextScaling(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CanvasEditorWidget(
                                      controller: studio.editor,
                                      viewportPadding: 0,
                                      theme: const CanvasTheme(
                                        selectionBorderColor:
                                            StudioColors.accent,
                                        handleColor: StudioColors.accent,
                                        rotationHandleColor:
                                            StudioColors.accent,
                                        selectionBorderWidth: 1.2,
                                        handleSize: 7,
                                      ),
                                    ),
                                    if (!studio.project.focusLight.isOff)
                                      FocusLightLayer(
                                        setting: studio.project.focusLight,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Container(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 12 : 25),
          decoration: const BoxDecoration(
            color: StudioColors.wash,
            border: Border(top: BorderSide(color: StudioColors.border)),
          ),
          child: Row(
            children: [
              Text(
                studio.format.dimensions,
                style: const TextStyle(fontSize: 10, color: StudioColors.muted),
              ),
              const Spacer(),
              Container(
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: StudioColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Zoom out',
                      onPressed: _zoom <= .5
                          ? null
                          : () => _setZoom(_zoom - .25),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const Icon(Icons.remove, size: 14),
                    ),
                    InkWell(
                      onTap: () => _setZoom(1),
                      child: SizedBox(
                        width: 42,
                        child: Text(
                          '${(_zoom * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zoom in',
                      onPressed: _zoom >= 2
                          ? null
                          : () => _setZoom(_zoom + .25),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const Icon(Icons.add, size: 14),
                    ),
                  ],
                ),
              ),
              if (!widget.compact) ...[
                const Spacer(),
                const Icon(
                  Icons.verified_outlined,
                  size: 12,
                  color: StudioColors.accent,
                ),
                const SizedBox(width: 5),
                const Text(
                  'HIGH-RES READY',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1,
                    color: StudioColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _lightsButton() {
    final setting = widget.studio.project.focusLight;
    final lit = !setting.isOff;
    final label = lit ? setting.light.label : 'Lights';
    final icon = Icon(
      lit ? Icons.light_mode : Icons.light_mode_outlined,
      size: 17,
      color: lit ? StudioColors.accent : StudioColors.ink,
    );
    if (widget.compact) {
      // The 320 px toolbar has no room for a default 48 px target here; 32 px
      // still clears the 44 px recommendation once its padding is counted and
      // keeps the row from overflowing on the narrowest phone.
      return IconButton(
        tooltip: 'Focus lights · $label',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () => FocusLightSheet.show(context, widget.studio),
        icon: icon,
      );
    }
    return TextButton.icon(
      onPressed: () => FocusLightSheet.show(context, widget.studio),
      icon: icon,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: lit ? FontWeight.w600 : FontWeight.w500,
          color: lit ? StudioColors.accent : StudioColors.ink,
        ),
      ),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}

class _DotGrid extends CustomPainter {
  const _DotGrid();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = StudioColors.muted.withValues(alpha: .16);
    for (double x = 12; x < size.width; x += 20) {
      for (double y = 12; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), .65, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGrid oldDelegate) => false;
}
