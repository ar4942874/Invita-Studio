import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/guide_prefs.dart';
import 'guide_stop.dart';

/// Drives the guided setup: which step is showing, what it points at, and what
/// the person has already finished.
///
/// Three separate ideas, deliberately not one "dismissed" bit:
/// * **finished** — "I have done this"; never shown again.
/// * **skipped** — "not now"; the step stays for next time.
/// * **dismissed** — "close the tour"; hidden for this session, resumed at the
///   same step next launch.
/// * **off** — "never show tips"; the tour does not come back until it is
///   switched on again from the menu.
class GuideController extends ChangeNotifier {
  GuideController({
    List<GuideStop> stops = guideStops,
    this.prefs = const GuidePrefs(),
  }) : stops = List.unmodifiable(stops);

  final List<GuideStop> stops;

  /// Where progress is remembered; injectable so tests can keep it in memory.
  final GuidePrefs prefs;

  final Set<String> _done = {};
  final Set<String> _registered = {};
  final Map<String, Rect> _rects = {};

  int _index = 0;
  bool _dismissed = false;
  bool _off = false;
  bool _started = false;
  bool _allDone = false;
  bool _disposed = false;

  /// Anchors that have reported their position at least once, so a step can be
  /// skipped on a screen where its control does not exist (a phone hides the
  /// style inspector, for example).
  Set<String> get registeredAnchors => Set.unmodifiable(_registered);

  Set<String> get finishedAnchors => Set.unmodifiable(_done);

  GuideStop? get current =>
      _started && _index >= 0 && _index < stops.length ? stops[_index] : null;

  /// 1-based position for the "3 of 9" label.
  int get position => current == null ? 0 : _index + 1;

  int get total => stops.length;

  bool get isOff => _off;

  bool get isDismissed => _dismissed;

  /// True when the tour is on screen right now.
  bool get isVisible =>
      _started && !_dismissed && !_off && !_allDone && current != null;

  /// True when every step has been finished.
  bool get isComplete => _allDone;

  /// Anything left to show, whether or not it is on screen.
  bool get hasRemaining => !_off && !_allDone && stops.any(_isOpen);

  bool _isOpen(GuideStop stop) => !_done.contains(stop.anchor);

  /// Reads the saved state. Completes even when preferences are unavailable.
  Future<void> restore() async {
    final progress = await prefs.load();
    if (_disposed) return;
    _done
      ..clear()
      ..addAll(progress.done);
    _off = progress.off;
    _allDone = !stops.any(_isOpen);
    final resume = progress.step == null
        ? null
        : stops.indexWhere((stop) => stop.anchor == progress.step);
    _index = resume == null || resume < 0 ? _firstOpen() : resume;
    _notify();
  }

  int _firstOpen() {
    final index = stops.indexWhere(_isOpen);
    return index < 0 ? 0 : index;
  }

  /// Opens the tour at the first unfinished step, or at [anchor].
  ///
  /// Called automatically the first time the editor opens, so nobody has to
  /// find a "show me around" button before they can start.
  void start({String? anchor}) {
    if (_disposed) return;
    final index = anchor == null
        ? stops.indexWhere(_isOpen)
        : stops.indexWhere((stop) => stop.anchor == anchor);
    _dismissed = false;
    _started = true;
    _index = index < 0 ? _firstOpen() : index;
    _allDone = current == null;
    unawaited(prefs.saveStep(current?.anchor));
    _notify();
  }

  /// First run only: opens the tour when there is something to show and the
  /// person has not asked it to stay away.
  void startIfNew() {
    if (_off || _started || _allDone) return;
    if (stops.any(_isOpen)) start();
  }

  /// Marks the current step finished, remembers it and moves on.
  void finishStep() {
    final step = current;
    if (step == null) return;
    _done.add(step.anchor);
    unawaited(prefs.saveDone(_done));
    _advance();
  }

  /// Moves on without marking the step finished. It will offer itself again on
  /// the next launch — "not now" is not "done".
  void skip() => _advance();

  /// Hides the tour for this session at the current step.
  void dismiss() {
    if (_disposed) return;
    _dismissed = true;
    unawaited(prefs.saveStep(current?.anchor));
    _notify();
  }

  /// "Do not show tips again". Persisted until switched back on.
  void turnOff() {
    if (_disposed) return;
    _off = true;
    _dismissed = true;
    unawaited(prefs.saveOff(true));
    _notify();
  }

  /// Brings the tour back after [turnOff].
  void turnOn() {
    if (_disposed) return;
    _off = false;
    unawaited(prefs.saveOff(false));
    start();
  }

  void _advance() {
    if (_disposed) return;
    final next = _nextOpen(_index);
    _index = next ?? _index;
    _allDone = next == null;
    if (next == null) _started = false;
    unawaited(prefs.saveStep(next == null ? null : stops[next].anchor));
    _notify();
  }

  /// The next unfinished stop whose control exists on this screen. Whether an
  /// anchor is missing is only trusted once some target has registered, so a
  /// cold start does not skip the whole tour.
  int? _nextOpen(int after) {
    for (var i = after + 1; i < stops.length; i++) {
      if (!_isOpen(stops[i])) continue;
      if (!_anchorMightExist(stops[i].anchor)) continue;
      return i;
    }
    for (var i = 0; i < after && i < stops.length; i++) {
      if (!_isOpen(stops[i])) continue;
      if (!_anchorMightExist(stops[i].anchor)) continue;
      return i;
    }
    return null;
  }

  bool _anchorMightExist(String anchor) =>
      _registered.isEmpty || !_registered.contains(anchor) || _rects[anchor] != null;

  /// Records that an anchor's widget exists, without needing it visible.
  void registerAnchor(String anchor) {
    if (_registered.add(anchor)) {
      // No notification: availability is a look-up, not a repaint.
    }
  }

  /// Reports where an anchor currently is, in global coordinates.
  ///
  /// Only notifies when the rectangle actually moved, so a target that
  /// re-measures itself after every rebuild cannot spin the frame loop.
  void reportAnchor(String anchor, Rect rect) {
    if (_disposed) return;
    _registered.add(anchor);
    final previous = _rects[anchor];
    if (previous != null &&
        (previous.top - rect.top).abs() < .5 &&
        (previous.left - rect.left).abs() < .5 &&
        (previous.width - rect.width).abs() < .5 &&
        (previous.height - rect.height).abs() < .5) {
      return;
    }
    _rects[anchor] = rect;
    if (current?.anchor == anchor) _notify();
  }

  Rect? rectFor(String anchor) => _rects[anchor];

  void forgetAnchors() {
    _rects.clear();
    _registered.clear();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
