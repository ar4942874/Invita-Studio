import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/studio_controller.dart';
import '../../services/export_service.dart';
import '../../services/file_actions.dart';
import '../studio_theme.dart';
import 'controls.dart';
import 'document_preview.dart';

class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, required this.studio});
  final StudioController studio;
  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ImageFormat _format = ImageFormat.png;
  int _scale = 2;
  bool _busy = false, _actionBusy = false;
  ExportedFile? _file;
  String? _error, _message;
  void _change(VoidCallback change) {
    setState(() {
      change();
      _file = null;
      _error = null;
      _message = null;
    });
  }

  Future<void> _render() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    announceForAccessibility(context, 'Preparing your invitation.');
    try {
      final result = await ExportService.render(
        widget.studio,
        format: _format,
        scale: _scale,
      );
      if (mounted) {
        setState(() => _file = result);
        announceForAccessibility(
          context,
          'Invitation ready, ${result.width} by ${result.height} pixels.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not create the image. $e');
        announceForAccessibility(context, 'Could not create the image.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    setState(() => _actionBusy = true);
    try {
      final message = await saveBytes(file.bytes, file.name, file.mime);
      if (mounted) {
        setState(() => _message = message);
        if (message != null) announceForAccessibility(context, message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The image could not be saved. Try Share, or download again.',
        );
        announceForAccessibility(context, 'The image could not be saved.');
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final file = _file;
    if (file == null) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    setState(() => _actionBusy = true);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(file.bytes, mimeType: file.mime, name: file.name),
          ],
          fileNameOverrides: [file.name],
          subject: 'Your invitation',
          title: 'Share invitation',
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
      if (mounted) {
        setState(
          () => _message = result.status == ShareResultStatus.dismissed
              ? 'Sharing cancelled.'
              : 'Sharing is handled by your device. Delivery is not confirmed here.',
        );
        announceForAccessibility(context, _message!);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = kIsWeb
              ? 'File sharing is not available in this browser. Download the image instead.'
              : 'The device could not open sharing. Save the file and try again.',
        );
        announceForAccessibility(context, _error!);
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Widget _readyActions(String ext) => LayoutBuilder(
    builder: (context, constraints) {
      final save = FilledButton.icon(
        onPressed: _actionBusy ? null : _save,
        icon: const Icon(Icons.file_download_outlined, size: 17),
        label: Text('${kIsWeb ? 'Download' : 'Save'} $ext'),
      );
      final share = Builder(
        builder: (buttonContext) => OutlinedButton.icon(
          onPressed: _actionBusy ? null : () => _share(buttonContext),
          icon: const Icon(Icons.ios_share, size: 16),
          label: const Text('Share'),
        ),
      );
      if (constraints.maxWidth < 270) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [save, const SizedBox(height: 9), share],
        );
      }
      return Row(
        children: [
          Expanded(child: save),
          const SizedBox(width: 10),
          share,
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final studio = widget.studio;
    final warnings = studio.layoutWarnings;
    final ext = _format == ImageFormat.png ? 'PNG' : 'JPEG';
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 570),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(27),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const TinyLabel(
                      'Send a little joy',
                      color: StudioColors.accent,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close export',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Ready for their inbox.',
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 34,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'A beautiful image, ready to save and share.',
                  style: TextStyle(fontSize: 12, color: StudioColors.muted),
                ),
                const SizedBox(height: 23),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: StudioColors.wash,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 67,
                        height: 94,
                        child: _file == null
                            ? DocumentPreview(
                                document: studio.document,
                                decodeWidth: 240,
                              )
                            : Image.memory(_file!.bytes, fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 17),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studio.project.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${studio.template.name} · ${studio.format.label}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: StudioColors.muted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  _file == null
                                      ? Icons.verified_outlined
                                      : Icons.check_circle_outline,
                                  size: 14,
                                  color: StudioColors.accent,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    _file == null
                                        ? 'Clean export. No editing handles.'
                                        : '${_file!.width} × ${_file!.height} · ${_file!.sizeLabel}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: StudioColors.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                const TinyLabel('File format'),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: _FormatOption(
                        title: 'PNG',
                        caption: 'Crisp & lossless',
                        selected: _format == ImageFormat.png,
                        onTap: _busy
                            ? null
                            : () => _change(() => _format = ImageFormat.png),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FormatOption(
                        title: 'JPEG',
                        caption: 'High quality · compact',
                        selected: _format == ImageFormat.jpeg,
                        onTap: _busy
                            ? null
                            : () => _change(() => _format = ImageFormat.jpeg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const TinyLabel('Resolution'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: StudioColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _scale,
                      isExpanded: true,
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 12,
                        color: StudioColors.ink,
                      ),
                      items: [
                        for (final scale in [1, 2])
                          DropdownMenuItem(
                            value: scale,
                            child: Text(
                              '${scale == 2 ? 'High resolution' : 'Standard'} · $scale×    ${(studio.document.width * scale).toInt()} × ${(studio.document.height * scale).toInt()}',
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v != null) _change(() => _scale = v);
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  'Dimensions are independent of screen size and zoom.',
                  style: TextStyle(fontSize: 10, color: StudioColors.muted),
                ),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  HintBox(
                    '${warnings.join('\n')} Move or resize those layers before exporting.',
                    warning: true,
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 15),
                  HintBox(_error!, warning: true, icon: Icons.error_outline),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 15),
                  HintBox(_message!, icon: Icons.check_circle_outline),
                ],
                const SizedBox(height: 25),
                if (_file == null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || warnings.isNotEmpty ? null : _render,
                      icon: _busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined, size: 17),
                      label: Text(
                        _busy ? 'Preparing your invitation…' : 'Create $ext',
                      ),
                    ),
                  )
                else
                  _readyActions(ext),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'No watermark. No account. Just your invitation.',
                    style: TextStyle(fontSize: 10, color: StudioColors.muted),
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

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
  });
  final String title, caption;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? StudioColors.accentSoft.withValues(alpha: .6)
        : Colors.white,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? StudioColors.accent : StudioColors.border,
            width: selected ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: selected ? StudioColors.accent : StudioColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              caption,
              style: const TextStyle(fontSize: 10, color: StudioColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}
