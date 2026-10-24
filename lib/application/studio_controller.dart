import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../domain/category_music.dart';
import '../domain/event_schedule.dart';
import '../domain/focus_light.dart';
import '../domain/invitation_template.dart';
import '../domain/project.dart';
import '../domain/video/timeline.dart';
import '../services/catalog_prefs.dart';
import '../services/draft_store.dart';
import '../services/photo_service.dart';

enum SaveState { saving, saved, failed }

class StudioController extends ChangeNotifier {
  StudioController({
    required StudioProject project,
    required this.store,
    List<StudioProject>? drafts,
    CatalogPrefs? catalog,
  }) : _project = project,
       _drafts = drafts ?? [project],
       catalog = catalog ?? const CatalogPrefs() {
    editor = CanvasEditorController(
      initialDocument: project.document,
      imageProvider: (ref) {
        final asset = ref.assetId;
        // Photos the host itself produced are embedded as bounded data URLs.
        final bytes = photoBytesFromDataUrl(asset);
        if (bytes != null) return MemoryImage(bytes);
        if (!invitationArtAssets.contains(asset)) {
          throw StateError('Untrusted image asset.');
        }
        return AssetImage(asset!);
      },
      onDocumentChanged: _onCommittedDocument,
    );
    _lastDocument = project.document;
    _committedDocument = project.document;
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
    catalogLoaded = _loadCatalog();
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

  /// Favourites and recents for the design picker. Persisted separately from
  /// the project because they describe the person, not one invitation.
  final CatalogPrefs catalog;
  final Set<String> _favourites = {};
  final List<String> _recent = [];

  /// Completes when the persisted favourites and recents have loaded. Tests
  /// await it so a tap and the initial load cannot race.
  late final Future<void> catalogLoaded;
  late final StreamSubscription<CanvasEditorState> _subscription;
  StudioProject _project;
  List<StudioProject> _drafts;
  late DesignDocument _lastDocument;

  /// Last committed document. Used as the "before" side of a document history
  /// entry, because the engine reports commits with the new document.
  late DesignDocument _committedDocument;

  /// Unified undo/redo for image *and* video edits, in the order they happened.
  /// Document steps are restored through the engine; video steps from the
  /// stored timeline snapshots. Only [Cursor] entries are undoable.
  final List<_HistoryEntry> _history = [];
  int _cursor = 0;
  static const _maxHistory = 80;

  /// Snapshot taken when a slider drag starts, so the whole drag is one step.
  VideoTimeline? _videoSession;

  /// Same idea for the focus-light sheet's intensity slider.
  FocusLightSetting? _focusSession;
  bool _resettingHistory = false;
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

  /// Designs the host starred.
  Set<String> get favourites => Set.unmodifiable(_favourites);

  /// Designs used recently, newest first.
  List<String> get recentDesigns => List.unmodifiable(_recent);

  bool isFavourite(String templateId) => _favourites.contains(templateId);

  Future<void> _loadCatalog() async {
    final favourites = await catalog.loadFavourites();
    final recent = await catalog.loadRecent();
    if (_disposed) return;
    // Merge instead of replacing: a tap that lands while the preferences are
    // still loading must not be lost.
    _favourites.addAll(favourites);
    final merged = [
      ..._recent,
      ...recent.where((id) => !_recent.contains(id)),
    ];
    _recent
      ..clear()
      ..addAll(merged.take(CatalogPrefs.maxRecent));
    notifyListeners();
  }

  void toggleFavourite(String templateId) {
    if (!_favourites.remove(templateId)) _favourites.add(templateId);
    notifyListeners();
    unawaited(catalog.saveFavourites(_favourites));
  }

  void _markUsed(String templateId) {
    _recent
      ..remove(templateId)
      ..insert(0, templateId);
    if (_recent.length > CatalogPrefs.maxRecent) {
      _recent.removeRange(CatalogPrefs.maxRecent, _recent.length);
    }
    unawaited(catalog.saveRecent(_recent));
  }

  /// The validated view of the project's timeline. Windows are clamped to the
  /// current duration and animations for deleted layers are dropped, so
  /// preview, inspector and exporter all see the same motion.
  VideoTimeline get video => _project.effectiveVideo;

  /// Replaces the video timeline and schedules the usual debounced autosave.
  /// Export always reads a frozen copy, so this is safe during export.
  ///
  /// The change joins the same undo history as image edits. Wrap a slider drag
  /// with [beginVideoSession]/[endVideoSession] so the whole drag is one step.
  void updateVideo(VideoTimeline value) {
    if (_disposed) return;
    final before = _project.video;
    _project = _project.copyWith(video: value);
    if (_videoSession == null) _recordVideo(before, value);
    _upsert(_project);
    _scheduleSave();
    notifyListeners();
  }

  /// The light currently thrown across the card.
  FocusLightSetting get focusLight => _project.focusLight;

  /// Swaps the light (or its strength) and schedules the usual autosave.
  ///
  /// Joins the shared undo history: a preset tap is one step, a whole slider
  /// drag is one step when wrapped in [beginFocusSession]/[endFocusSession].
  void updateFocusLight(FocusLightSetting value) {
    if (_disposed) return;
    final before = _project.focusLight;
    if (before == value) return;
    _project = _project.copyWith(focusLight: value);
    if (_focusSession == null) _recordFocus(before, value);
    _upsert(_project);
    _scheduleSave();
    notifyListeners();
  }

  void beginFocusSession() {
    _focusSession ??= _project.focusLight;
  }

  void endFocusSession() {
    final before = _focusSession;
    _focusSession = null;
    if (before != null) _recordFocus(before, _project.focusLight);
  }

  void _recordFocus(FocusLightSetting before, FocusLightSetting after) {
    if (before == after) return;
    _truncateRedo();
    _history.add(_HistoryEntry(isVideo: false, before: before, after: after));
    _cursor = _history.length;
    _trimHistory();
  }

  /// Starts coalescing a run of [updateVideo] calls (e.g. a slider drag) into
  /// one undo step.
  void beginVideoSession() {
    _videoSession ??= _project.video;
  }

  /// Ends a [beginVideoSession] and records one undo step if anything changed.
  void endVideoSession() {
    final before = _videoSession;
    _videoSession = null;
    if (before != null) _recordVideo(before, _project.video);
  }

  void _recordVideo(VideoTimeline before, VideoTimeline after) {
    if (before == after) return;
    _truncateRedo();
    _history.add(_HistoryEntry(isVideo: true, before: before, after: after));
    _cursor = _history.length;
    _trimHistory();
  }

  void _truncateRedo() {
    if (_cursor < _history.length) {
      _history.removeRange(_cursor, _history.length);
    }
  }

  void _trimHistory() {
    if (_history.length > _maxHistory) {
      _history.removeRange(0, _history.length - _maxHistory);
      _cursor = _history.length;
    }
  }

  /// Called by the engine on every committed document change (gesture end,
  /// add/delete, history session commit). Not called mid-drag, so the entry is
  /// one per user action. Restoring history uses `recordUndo: false`, which
  /// never triggers this, so no re-entrancy guard is needed.
  void _onCommittedDocument(DesignDocument document) {
    if (_disposed || _resettingHistory) {
      _committedDocument = document;
      return;
    }
    if (document == _committedDocument) return;
    _truncateRedo();
    _history.add(
      _HistoryEntry(isVideo: false, before: _committedDocument, after: document),
    );
    _cursor = _history.length;
    _trimHistory();
    _committedDocument = document;
  }
  DesignDocument get document => editor.document;

  /// The applied design, in the composition the card is actually drawn in.
  ///
  /// [_designByArt] answers with the design's default arrangement, so a card
  /// switched to another composition would otherwise be reported (and given
  /// back on a format change) in the wrong one.
  InvitationTemplate get template {
    final base = templateFor(document);
    final detected = layout;
    return detected == null ? base : base.withLayout(detected);
  }

  InvitationFormat get format => formatFor(document);

  /// The composition the card is drawn in, or `null` when the layers have been
  /// moved far enough that no arrangement fits.
  InvitationLayout? get layout {
    final base = templateFor(document);
    if (_layoutKnown &&
        identical(document, _layoutForDocument) &&
        identical(base, _layoutForTemplate)) {
      return _layout;
    }
    _layoutForDocument = document;
    _layoutForTemplate = base;
    _layoutKnown = true;
    _layout = detectLayout(document, template: base);
    return _layout;
  }

  DesignDocument? _layoutForDocument;
  InvitationTemplate? _layoutForTemplate;
  InvitationLayout? _layout;
  bool _layoutKnown = false;
  TextNode? get selectedText => editor.state.selectedNode is TextNode
      ? editor.state.selectedNode as TextNode
      : null;
  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _history.length;
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
    if (_cursor == 0) return;
    final entry = _history[--_cursor];
    await _restoreHistory(entry.before);
    if (!_disposed) notifyListeners();
  });
  Future<void> redo() => _enqueue(() async {
    if (_cursor >= _history.length) return;
    final entry = _history[_cursor++];
    await _restoreHistory(entry.after);
    if (!_disposed) notifyListeners();
  });

  /// Restores one side of a history entry (the "before" on undo, the "after" on
  /// redo), whether it holds a document or a video timeline.
  Future<void> _restoreHistory(Object? value) async {
    if (value is FocusLightSetting) {
      _project = _project.copyWith(focusLight: value);
      _upsert(_project);
      _scheduleSave();
      return;
    }
    if (value is VideoTimeline) {
      _project = _project.copyWith(video: value);
      _upsert(_project);
      _scheduleSave();
      return;
    }
    if (value is DesignDocument) {
      await editor.applyDocument(value, recordUndo: false);
      _committedDocument = value;
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> chooseTemplate(InvitationTemplate target) {
    _markUsed(target.id);
    return _reflow(target, format);
  }

  /// Redraws the current design in another composition.
  ///
  /// The words, photos and custom layers are kept — only the arrangement of the
  /// linked fields changes, and it is a single undo step.
  Future<void> chooseLayout(InvitationLayout target) =>
      chooseTemplate(template.withLayout(target));

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
    // Decode, resize and re-encode the photo. Large inputs do that work on a
    // background isolate so the UI never stalls mid-typing; smaller ones
    // finish faster synchronously than the isolate round-trip.
    final photo = bytes.lengthInBytes >= photoIsolateMinBytes
        ? await compute(preparePhoto, bytes)
        : preparePhoto(bytes);
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
    _resettingHistory = true;
    _videoSession = null;
    editor.loadDocument(project.document);
    await Future<void>.delayed(Duration.zero);
    _history.clear();
    _cursor = 0;
    _committedDocument = project.document;
    _resettingHistory = false;
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

  /// Changes the celebration after creation.
  ///
  /// The category drives the wording defaults, the bundled tune and which
  /// designs suit the card, so all three follow the change: a bundled tune is
  /// swapped for the new celebration's tune (imported music is left alone), and
  /// [template] — when given — is applied through the normal reflow, so words,
  /// photos and custom layers survive.
  Future<void> updateEventSettings({
    required InvitationCategory category,
    InvitationTemplate? template,
  }) async {
    if (_disposed) return;
    var next = _project.copyWith(category: category);
    final audio = next.video.audio;
    if (audio != null && CategoryMusic.isTune(audio.assetId)) {
      final tuneId = CategoryMusic.tuneId(category);
      if (audio.assetId != tuneId) {
        next = next.copyWith(
          video: next.video.copyWith(
            audio: audio.copyWith(
              assetId: tuneId,
              title: CategoryMusic.title(category),
              durationMs: CategoryMusic.durationFor(category),
              trimStartMs: 0,
              trimEndMs: 0,
            ),
          ),
        );
      }
    }
    _project = next;
    _upsert(next);
    _scheduleSave();
    notifyListeners();
    if (template != null && template.id != this.template.id) {
      await _reflow(template, format);
    }
  }

  /// Stores (or clears) the structured event behind the date/time fields.
  Future<void> setSchedule(EventDateTime? when) async {
    _project = when == null
        ? _project.copyWith(clearWhen: true)
        : _project.copyWith(when: when);
    _upsert(_project);
    _scheduleSave();
    notifyListeners();
  }

  /// Stores (or clears) the RSVP destination used for the invitation code.
  Future<void> setRsvpUrl(String? url) async {
    final trimmed = url?.trim() ?? '';
    _project = trimmed.isEmpty
        ? _project.copyWith(clearRsvpUrl: true)
        : _project.copyWith(rsvpUrl: trimmed);
    _upsert(_project);
    _scheduleSave();
    notifyListeners();
  }

  /// Copies [source] into a new draft and opens it.
  ///
  /// Duplicating is the "make a variation" workflow, so the copy becomes the
  /// active draft; the original is untouched and stays in the list.
  Future<StudioProject> duplicateProject(StudioProject source) async {
    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    final copy = source.fork(id: id, title: _copyTitle(source.title));
    await openProject(copy);
    return copy;
  }

  static String _copyTitle(String title) {
    const suffix = ' (copy)';
    final room = 80 - suffix.length;
    final base = title.length > room
        ? title.substring(0, room).trimRight()
        : title;
    return '$base$suffix';
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

/// One undoable step: a document change or a video-timeline change, holding the
/// state on either side so both modes share a single history.
class _HistoryEntry {
  const _HistoryEntry({
    required this.isVideo,
    required this.before,
    required this.after,
  });

  final bool isVideo;
  final Object? before;
  final Object? after;
}
