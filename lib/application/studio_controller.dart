import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../domain/category_music.dart';
import '../domain/invitation_template.dart';
import '../domain/project.dart';
import '../domain/video/timeline.dart';
import '../services/draft_store.dart';
import '../services/photo_service.dart';

enum SaveState { saving, saved, failed }

class StudioController extends ChangeNotifier {
  StudioController({
    required StudioProject project,
    required this.store,
    List<StudioProject>? drafts,
  }) : _project = project,
       _drafts = drafts ?? [project] {
    editor = CanvasEditorController(
      initialDocument: project.document,
      imageProvider: (ref) {
        final asset = ref.assetId;
        // Photos the host itself produced are embedded as bounded data URLs.
        final bytes = photoBytesFromDataUrl(asset);
        if (bytes != null) return MemoryImage(bytes);
        final allowed = {
          for (final t in invitationTemplates)
            for (final f in InvitationFormat.values) t.art(f),
        };
        if (!allowed.contains(asset)) {
          throw StateError('Untrusted image asset.');
        }
        return AssetImage(asset!);
      },
    );
    _lastDocument = project.document;
    _subscription = editor.stateStream.listen((state) {
      if (_disposed) return;
      if (state.document != _lastDocument) {
        _lastDocument = state.document;
        _project = _project.copyWith(document: state.document);
        _upsert(_project);
        _scheduleSave();
      }
      notifyListeners();
    });
    _scheduleSave();
  }

  static Future<StudioController> restore({ProjectStore? store}) async {
    final storage = store ?? LocalProjectStore();
    try {
      final drafts = await storage.load();
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return StudioController(
        project: drafts.firstOrNull ?? StudioProject.sample(),
        store: storage,
        drafts: drafts.isEmpty ? null : drafts,
      );
    } catch (_) {
      final controller = StudioController(
        project: StudioProject.sample(),
        store: storage,
      );
      // Do not overwrite unreadable drafts automatically.
      controller._saveTimer?.cancel();
      controller.saveState = SaveState.failed;
      controller.storageError = 'Local drafts could not be restored. Export your project to keep a backup.';
      return controller;
    }
  }

  late final CanvasEditorController editor;
  final ProjectStore store;
  late final StreamSubscription<CanvasEditorState> _subscription;
  StudioProject _project;
  List<StudioProject> _drafts;
  late DesignDocument _lastDocument;
  final Map<String, String> _pendingFields = {};
  Future<void> _queue = Future.value();
  Future<void> _saveQueue = Future.value();
  Timer? _saveTimer;
  bool _disposed = false;
  int _revision = 0;
  SaveState saveState = SaveState.saving;
  String? storageError;

  StudioProject get project => _project.copyWith(
    document: editor.document,
    updatedAt: _project.updatedAt,
  );
  List<StudioProject> get drafts => List.unmodifiable(_drafts);

  /// The validated view of the project's timeline. Windows are clamped to the
  /// current duration and animations for deleted layers are dropped, so
  /// preview, inspector and exporter all see the same motion.
  VideoTimeline get video => _project.effectiveVideo;

  /// Replaces the video timeline and schedules the usual debounced autosave.
  /// Export always reads a frozen copy, so this is safe during export.
  void updateVideo(VideoTimeline value) {
    if (_disposed) return;
    _project = _project.copyWith(video: value);
    _upsert(_project);
    _scheduleSave();
    notifyListeners();
  }
  DesignDocument get document => editor.document;
  InvitationTemplate get template => templateFor(document);
  InvitationFormat get format => formatFor(document);
  TextNode? get selectedText => editor.state.selectedNode is TextNode
      ? editor.state.selectedNode as TextNode
      : null;
  bool get canUndo => editor.state.canUndo;
  bool get canRedo => editor.state.canRedo;
  int get layerCount => document.nodes.whereType<TextNode>().length;
  DesignNode? get selectedNode => editor.state.selectedNode;
  ImageNode? get selectedPhoto => selectedNode is ImageNode
      ? selectedNode as ImageNode
      : null;
  int get nodeCount =>
      document.nodes.where((n) => n is! BackgroundNode).length;
  String fieldValue(String id) =>
      _pendingFields[id] ??
      document.nodes
          .whereType<TextNode>()
          .where((n) => n.id == id)
          .firstOrNull
          ?.text ??
      '';

  Future<void> _enqueue(Future<void> Function() task) {
    final result = _queue.then((_) async {
      if (!_disposed) await task();
    });
    _queue = result.catchError((Object error, StackTrace stack) {
      if (!_disposed) {
        storageError = 'An edit could not be applied: $error';
        notifyListeners();
      }
    });
    return result;
  }

  Future<void> flush() async {
    await _queue;
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> setField(String id, String value) {
    _pendingFields[id] = value;
    notifyListeners();
    return _enqueue(() async {
      final nodes = document.nodes
          .map(
            (node) => node.id == id && node is TextNode
                ? fitTextNode(node.copyWith(text: value))
                : node,
          )
          .toList();
      await editor.applyDocument(document.copyWith(nodes: nodes));
      if (_pendingFields[id] == value) _pendingFields.remove(id);
      if (!_disposed) notifyListeners();
    });
  }

  void selectLayer(String? id) {
    editor.selectNode(id);
  }

  Future<void> undo() => _enqueue(() async {
    editor.undo();
    await Future<void>.delayed(Duration.zero);
  });
  Future<void> redo() => _enqueue(() async {
    editor.redo();
    await Future<void>.delayed(Duration.zero);
  });

  Future<void> chooseTemplate(InvitationTemplate target) =>
      _reflow(target, format);
  Future<void> chooseFormat(InvitationFormat target) =>
      _reflow(template, target, preserveStyle: true);
  Future<void> resetLayout() => _reflow(template, format, keepExtras: false);

  Future<void> _reflow(
    InvitationTemplate target,
    InvitationFormat targetFormat, {
    bool preserveStyle = false,
    bool keepExtras = true,
  }) => _enqueue(() async {
    final old = document;
    var next = target.createDocument(
      documentId: old.id,
      format: targetFormat,
      fields: fieldsFor(old),
    );
    if (preserveStyle) {
      final oldBase = template.createDocument(
        documentId: old.id,
        format: format,
      );
      final styled = next.nodes.map((node) {
        if (node is! TextNode) return node;
        final previous = old.nodes
            .whereType<TextNode>()
            .where((n) => n.id == node.id)
            .firstOrNull;
        final base = oldBase.nodes
            .whereType<TextNode>()
            .where((n) => n.id == node.id)
            .firstOrNull;
        if (previous == null || base == null) return node;
        return fitTextNode(
          node.copyWith(
            fontSize: previous.fontSize * node.fontSize / base.fontSize,
            fontFamily: previous.fontFamily,
            fontWeight: previous.fontWeight,
            textColor: previous.textColor,
            textAlign: previous.textAlign,
            letterSpacing: previous.letterSpacing,
            lineHeight: previous.lineHeight,
          ),
        );
      }).toList();
      next = next.copyWith(nodes: styled);
    }
    final extras = keepExtras
        ? old.nodes
              .where(
                (n) =>
                    n is ImageNode ||
                    (n is TextNode && !boundIds.contains(n.id)),
              )
              .map<DesignNode>((n) {
                final sy = targetFormat.height / old.height;
                final frame = Rect.fromLTWH(
                  n.frame.left,
                  n.frame.top * sy,
                  n.frame.width,
                  n.frame.height * sy,
                );
                return n is TextNode
                    ? fitTextNode(n.copyWith(frame: frame))
                    : n.copyWith(frame: frame);
              })
              .toList()
        : <DesignNode>[];
    await editor.applyDocument(
      next.copyWith(
        nodes: [
          ...next.nodes,
          for (var i = 0; i < extras.length; i++)
            extras[i].copyWith(zIndex: next.nodes.length + i),
        ],
      ),
      clearSelection: true,
    );
  });

  List<String> get _styleTargets =>
      selectedText == null ? ['first', 'second'] : [selectedText!.id];
  TextNode get styleReference =>
      selectedText ??
      document.nodes.whereType<TextNode>().firstWhere((n) => n.id == 'first');
  void beginStyleSession() {
    unawaited(
      _enqueue(() async {
        editor.beginHistorySession();
      }),
    );
  }

  void endStyleSession() {
    unawaited(
      _enqueue(() async {
        editor.commitHistorySession();
        await Future<void>.delayed(Duration.zero);
      }),
    );
  }

  Future<void> styleText({
    String? fontFamily,
    double? fontSize,
    String? color,
    int? weight,
    String? align,
    bool recordUndo = true,
  }) {
    final targets = _styleTargets;
    return _enqueue(() async {
      var nodes = document.nodes.map((node) {
        if (node is! TextNode || !targets.contains(node.id)) return node;
        final next = node.copyWith(
          fontFamily: fontFamily,
          fontSize: fontSize?.clamp(8, 240),
          textColor: color,
          fontWeight: weight,
          textAlign: align,
        );
        final painter = TextPainter(
          text: TextSpan(text: next.text, style: nodeTextStyle(next)),
          textDirection: invitationTextDirection(next.text),
        )..layout(maxWidth: next.frame.width);
        final sized = next.copyWith(
          frame: Rect.fromLTWH(
            next.frame.left,
            next.frame.top,
            next.frame.width,
            math.max(20, painter.height),
          ),
        );
        painter.dispose();
        return sized;
      }).toList();
      // Growing (or shrinking) a field re-stacks the linked wording so the
      // card never overlaps or spills off the page.
      if (fontSize != null) nodes = _reflowStack(nodes);
      await editor.applyDocument(
        document.copyWith(nodes: nodes),
        recordUndo: recordUndo,
      );
    });
  }

  /// Vertical order of the linked wording when the card is re-stacked.
  static const _stackOrder = [
    'header',
    'first',
    'amp',
    'second',
    'message',
    'date',
    'time',
    'venue',
    'address',
    'rsvp',
  ];

  /// Gaps between stacked fields as a fraction of the card height. Tuned so an
  /// untouched card looks like the original template.
  static const _stackGaps = <String, double>{
    'header>first': .030,
    'first>amp': .004,
    'amp>second': .004,
    'second>message': .034,
    'message>date': .030,
    'date>time': .010,
    'time>venue': .032,
    'venue>address': .010,
    'address>rsvp': .040,
  };

  /// Re-positions the linked text fields as a single vertical stack.
  ///
  /// Fields keep their horizontal placement and width; only the vertical order
  /// and spacing change so a larger field pushes its siblings instead of
  /// overlapping them. The stack is anchored to the opening line's position,
  /// then shifted up and its gaps compressed until it fits the page margins.
  List<DesignNode> _reflowStack(List<DesignNode> nodes) {
    final byId = <String, TextNode>{
      for (final node in nodes.whereType<TextNode>()) node.id: node,
    };
    final present = _stackOrder.where(byId.containsKey).toList();
    if (present.length < 2) return nodes;

    final docHeight = document.height;
    final topMargin = docHeight * .05;
    final bottomMargin = docHeight * .05;
    final anchor = byId[present.first]!.frame.top;

    double heightOf(TextNode node) {
      final painter = TextPainter(
        text: TextSpan(text: node.text, style: nodeTextStyle(node)),
        textDirection: invitationTextDirection(node.text),
      )..layout(maxWidth: math.max(2, node.frame.width));
      final height = math.max(20.0, painter.height);
      painter.dispose();
      return height;
    }

    final heights = {for (final id in present) id: heightOf(byId[id]!)};
    final content = heights.values.fold<double>(0, (sum, h) => sum + h);

    /// Positions the stack with the field gaps scaled by [k] (1 = full gaps).
    ({Map<String, double> tops, double end}) layout(double k) {
      final tops = <String, double>{};
      var cursor = anchor;
      for (var i = 0; i < present.length; i++) {
        final id = present[i];
        if (i > 0) {
          final gap = (_stackGaps['${present[i - 1]}>$id'] ?? .02) * k * docHeight;
          cursor += gap;
        }
        tops[id] = cursor;
        cursor += heights[id]!;
      }
      return (tops: tops, end: cursor);
    }

    void shiftUp(Map<String, double> tops, double amount) {
      if (amount <= 0) return;
      for (final id in present) {
        tops[id] = tops[id]! - amount;
      }
    }

    final bottomLimit = docHeight - bottomMargin;
    double endOf(Map<String, double> tops) =>
        tops[present.last]! + heights[present.last]!;

    var result = layout(1);
    var tops = result.tops;
    if (result.end > bottomLimit) {
      final firstTop = tops[present.first]!;
      final shift = math.min(
        result.end - bottomLimit,
        math.max(0.0, firstTop - topMargin),
      );
      shiftUp(tops, shift);
    }
    if (endOf(tops) > bottomLimit) {
      // Compress the gaps when the stack still overflows the bottom margin.
      final available = bottomLimit - topMargin;
      final fullGaps = (result.end - anchor) - content;
      if (fullGaps > 0 && available > content) {
        final k = ((available - content) / fullGaps).clamp(0.0, 1.0);
        result = layout(k);
        tops = result.tops;
        final firstTop = tops[present.first]!;
        shiftUp(
          tops,
          math.min(
            math.max(0.0, result.end - bottomLimit),
            math.max(0.0, firstTop - topMargin),
          ),
        );
      }
    }

    return [
      for (final node in nodes)
        if (node is TextNode && tops.containsKey(node.id))
          node.copyWith(
            frame: Rect.fromLTWH(
              node.frame.left,
              tops[node.id]!,
              node.frame.width,
              heights[node.id]!,
            ),
          )
        else
          node,
    ];
  }


  Future<void> editSelected(String value) async {
    final selected = selectedText;
    if (selected != null) await setField(selected.id, value);
  }

  Future<void> addText() => _enqueue(() async {
    if (document.nodes.length >= 50) return;
    final id = 'extra.${DateTime.now().microsecondsSinceEpoch}';
    final node = TextNode(
      id: id,
      frame: Rect.fromLTWH(180, document.height * .55, 720, 90),
      zIndex: document.nodes.length,
      text: 'Your personal touch',
      fontFamily: 'CormorantGaramond',
      fontSize: 44,
      textColor: template.ink,
      textAlign: 'center',
    );
    await editor.applyDocument(
      document.copyWith(nodes: [...document.nodes, node]),
      selectNodeId: id,
    );
  });

  /// Places a prepared photo on the canvas as an editable, movable layer.
  ///
  /// [bytes] is any supported image file. The photo is downscaled and stored as
  /// a bounded data URL so it survives drafts and project export. Throws
  /// [FormatException] when the file cannot be used.
  Future<void> addPhotoFromBytes(Uint8List bytes) async {
    if (_disposed) return;
    if (document.nodes.length >= 50) {
      throw const FormatException('An invitation can hold up to 50 layers.');
    }
    final photo = preparePhoto(bytes);
    final width = math.min(760.0, document.width * .72);
    final height = (width * photo.height / photo.width)
        .clamp(80.0, document.height)
        .toDouble();
    final topZ = document.nodes.fold<int>(
      -1,
      (max, n) => math.max(max, n.zIndex),
    );
    final node = ImageNode(
      id: 'photo.${DateTime.now().microsecondsSinceEpoch}',
      frame: Rect.fromLTWH(
        (document.width - width) / 2,
        (document.height - height) / 2,
        width,
        height,
      ),
      zIndex: topZ + 1,
      assetId: photo.dataUrl,
      fit: 'cover',
    );
    await _enqueue(() async {
      await editor.applyDocument(
        document.copyWith(nodes: [...document.nodes, node]),
        selectNodeId: node.id,
      );
    });
  }

  /// Updates the box-fit mode of the selected photo layer.
  Future<void> setPhotoFit(String fit) => _enqueue(() async {
    final photo = selectedPhoto;
    if (photo == null || !['cover', 'contain', 'fill'].contains(fit)) return;
    await editor.applyDocument(
      document.copyWith(
        nodes: document.nodes
            .map(
              (n) =>
                  n.id == photo.id && n is ImageNode ? n.copyWith(fit: fit) : n,
            )
            .toList(),
      ),
    );
  });

  Future<void> deleteSelected() => _enqueue(() async {
    final selected = selectedNode;
    if (selected == null || selected is BackgroundNode) return;
    if (selected is TextNode && boundIds.contains(selected.id)) return;
    await editor.applyDocument(
      document.copyWith(
        nodes: document.nodes.where((n) => n.id != selected.id).toList(),
      ),
      clearSelection: true,
    );
  });

  Future<void> moveLayer(bool forward) => _enqueue(() async {
    final selected = selectedNode;
    if (selected == null || selected is BackgroundNode) return;
    final background = document.nodes.whereType<BackgroundNode>().first;
    final nodes = document.nodes.where((n) => n is! BackgroundNode).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final index = nodes.indexWhere((n) => n.id == selected.id);
    final target = index + (forward ? 1 : -1);
    if (target < 0 || target >= nodes.length) return;
    final item = nodes.removeAt(index);
    nodes.insert(target, item);
    await editor.applyDocument(
      document.copyWith(
        nodes: [
          background,
          for (var i = 0; i < nodes.length; i++)
            nodes[i].copyWith(zIndex: i + 1),
        ],
      ),
    );
  });

  Future<void> centerSelected() => _enqueue(() async {
    final selected = selectedNode;
    if (selected == null || selected is BackgroundNode) return;
    final nodes = document.nodes
        .map(
          (n) => n.id == selected.id
              ? selected.copyWith(
                  frame: selected.frame.shift(
                    Offset(
                      (document.width - selected.frame.width) / 2 -
                          selected.frame.left,
                      0,
                    ),
                  ),
                  rotation: 0,
                  scaleX: 1,
                  scaleY: 1,
                )
              : n,
        )
        .toList();
    await editor.applyDocument(document.copyWith(nodes: nodes));
  });

  void rename(String title) {
    if (title.trim().isEmpty) return;
    _project = project.copyWith(
      title: title.trim().substring(0, math.min(80, title.trim().length)),
    );
    _upsert(_project);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> openProject(StudioProject project) async {
    if (!_drafts.any((d) => d.id == project.id) && _drafts.length >= 12) {
      throw StateError(
        '12 local drafts maximum. Export and delete an older draft before opening another.',
      );
    }
    await flush();
    await saveNow();
    _project = project;
    _pendingFields.clear();
    editor.loadDocument(project.document);
    await Future<void>.delayed(Duration.zero);
    _upsert(project);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> newProject() => openProject(StudioProject.sample());

  /// Creates a fresh invitation from the home-screen wizard and opens it.
  ///
  /// [fields] are the details the user typed; missing values fall back to the
  /// template defaults.
  Future<void> createProject({
    required InvitationCategory category,
    required InvitationTemplate template,
    required Map<String, String> fields,
    InvitationFormat format = InvitationFormat.classic,
  }) async {
    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    final project = StudioProject(
      id: id,
      title: category.titleFor(fields),
      updatedAt: DateTime.now(),
      category: category,
      document: template.createDocument(
        documentId: id,
        format: format,
        fields: fields,
      ),
      // Each celebration starts with its bundled tune already chosen; the
      // video settings sheet can swap or remove it.
      video: VideoTimeline(audio: CategoryMusic.forCategory(category)),
    );
    await openProject(project);
  }
  void _upsert(StudioProject value) {
    _drafts = [
      value,
      ..._drafts.where((d) => d.id != value.id),
    ].take(12).toList();
  }

  Future<void> deleteDraft(String id) async {
    if (id == project.id) return;
    _drafts.removeWhere((d) => d.id == id);
    await saveNow();
    notifyListeners();
  }

  void _scheduleSave() {
    _revision++;
    saveState = SaveState.saving;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 650),
      () => unawaited(saveNow()),
    );
  }

  Future<void> saveNow() {
    _saveTimer?.cancel();
    final snapshot = List<StudioProject>.of(_drafts);
    final revision = _revision;
    _saveQueue = _saveQueue.then((_) async {
      try {
        await store.save(snapshot);
        saveState = revision == _revision ? SaveState.saved : SaveState.saving;
        storageError = null;
      } catch (_) {
        saveState = SaveState.failed;
        storageError =
            'Local storage is unavailable or full. Export a project backup.';
      }
      if (!_disposed) notifyListeners();
    });
    return _saveQueue;
  }

  /// Detect clipped glyphs, including rotated/scaled bounds, before exporting.
  List<String> get layoutWarnings {
    final warnings = <String>[];
    for (final node in document.nodes.whereType<TextNode>()) {
      if (node.text.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: node.text, style: nodeTextStyle(node)),
        textDirection: invitationTextDirection(node.text),
      )..layout(maxWidth: node.frame.width);
      final center = node.frame.center;
      final rect = Rect.fromLTWH(
        node.frame.left,
        node.frame.top,
        node.frame.width,
        painter.height,
      );
      painter.dispose();
      final angle = node.rotation * math.pi / 180;
      final points =
          [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight].map((
            p,
          ) {
            final x = (p.dx - center.dx) * node.scaleX,
                y = (p.dy - center.dy) * node.scaleY;
            return Offset(
              center.dx + x * math.cos(angle) - y * math.sin(angle),
              center.dy + x * math.sin(angle) + y * math.cos(angle),
            );
          });
      if (points.any(
        (p) =>
            p.dx < -.5 ||
            p.dy < -.5 ||
            p.dx > document.width + .5 ||
            p.dy > document.height + .5,
      )) {
        warnings.add('${layerLabel(node.id)} extends beyond the invitation.');
      }
    }
    return warnings;
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _subscription.cancel();
    editor.dispose();
    super.dispose();
  }
}
