import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models/behavior_event.dart';
import 'synheart_behavior.dart' show SynheartBehavior;

/// A widget that wraps the app to detect gestures for behavior tracking.
///
/// This is needed because Flutter widgets are not native Android/iOS views,
/// so native touch listeners won't capture Flutter widget interactions.
class BehaviorGestureDetector extends StatefulWidget {
  final Widget child;
  final Function(BehaviorEvent)? onEvent;
  final String? sessionId;
  final SynheartBehavior? behavior; // Optional SDK instance to auto-send events

  const BehaviorGestureDetector({
    super.key,
    required this.child,
    this.onEvent,
    this.sessionId,
    this.behavior,
  });

  @override
  State<BehaviorGestureDetector> createState() =>
      _BehaviorGestureDetectorState();
}

class _BehaviorGestureDetectorState extends State<BehaviorGestureDetector> {
  // Scroll tracking - wait until scroll stops before calculating
  DateTime? _scrollStartTime;
  double _scrollStartPosition = 0.0;
  double _scrollEndPosition = 0.0;
  double _lastScrollPosition =
      0.0; // Track last position to detect direction from position change
  ScrollDirection? _scrollDirection;
  bool _hasDirectionReversal = false;
  double? _preservedStartPosition; // Preserve start position for continuation
  double? _initialEndPosition; // Backup for single-update scrolls
  double? _lastValidEndPosition; // Track last valid (non-zero) end position
  Timer? _scrollStopTimer;
  static const int _scrollStopThresholdMs =
      1000; // Wait 1000ms (1s) after last scroll update before finalizing scroll
  DateTime?
      _lastScrollFinalizedTime; // Track when scroll was last finalized to detect continuation
  static const int _scrollContinuationWindowMs =
      2000; // If new scroll starts within 2s of finalization, continue the same gesture

  // Velocity tracking for native velocity calculation
  DateTime? _lastVelocityTime;

  // Tap tracking
  DateTime? _tapDownTime;
  bool _hasScrolledSinceTapDown = false; // Track if scroll happened during tap
  bool _hasSwipedSinceTapDown = false; // Track if swipe happened during tap
  static const int _longPressThresholdMs = 500; // 500ms threshold

  // Swipe tracking
  DateTime? _swipeStartTime;
  Offset? _swipeStartPosition;
  Offset? _swipeLastPosition;
  bool _isSwipe = false;
  static const double _swipeThresholdPx = 50.0; // Minimum distance for swipe

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Handle all scroll notifications
        if (notification is ScrollUpdateNotification) {
          _handleScroll(notification);
          // Mark that scrolling occurred (prevents tap events during scroll)
          _hasScrolledSinceTapDown = true;
        } else if (notification is ScrollEndNotification) {
          // ScrollEndNotification fires when scroll momentum stops, but the user might
          // immediately start scrolling again in a different direction. We ignore this
          // notification and rely solely on the timer. If the user scrolls again within
          // 1200ms, _handleScroll will reset the timer and continue the same gesture.
          // This allows us to detect direction reversals across momentum stops.
          if (_scrollStartTime != null) {
            print(
                '📋 Scroll end notification received (ignoring - timer will finalize after ${_scrollStopThresholdMs}ms if no more updates)');
          }
          // Do nothing - let the timer handle finalization
        }
        return false; // Don't consume the notification
      },
      child: Listener(
        behavior: HitTestBehavior.translucent, // Don't block child widgets
        onPointerDown: (event) {
          // Track tap down time for tap detection
          _tapDownTime = DateTime.now();
          _hasScrolledSinceTapDown = false; // Reset scroll flag
          _hasSwipedSinceTapDown = false; // Reset swipe flag
        },
        onPointerUp: (event) {
          // Delay tap handling to let buttons handle their clicks first
          // Only emit tap event if it wasn't a swipe and no scroll occurred
          Future.delayed(const Duration(milliseconds: 150), () {
            if (_tapDownTime != null &&
                !_isSwipe &&
                !_hasScrolledSinceTapDown &&
                !_hasSwipedSinceTapDown) {
              _handleTap();
            }
            _tapDownTime = null;
            _hasScrolledSinceTapDown = false;
            _hasSwipedSinceTapDown = false;
          });
        },
        onPointerCancel: (event) {
          _tapDownTime = null;
          _hasScrolledSinceTapDown = false;
          _hasSwipedSinceTapDown = false;
        },
        child: GestureDetector(
          behavior: HitTestBehavior
              .deferToChild, // Let children handle gestures first
          onPanStart: (details) {
            _swipeStartTime = DateTime.now();
            _swipeStartPosition = details.globalPosition;
            _swipeLastPosition = details.globalPosition;
            _isSwipe = false;
          },
          onPanUpdate: (details) {
            _swipeLastPosition = details.globalPosition;
            _handlePan(details);
          },
          onPanEnd: (details) {
            _handlePanEnd(details);
          },
          child: widget.child,
        ),
      ),
    );
  }

  void _handleScroll(ScrollUpdateNotification notification) {
    final now = DateTime.now();
    final scrollDelta = notification.scrollDelta ?? 0.0;
    final currentPosition = notification.metrics.pixels;

    // Skip if scrollDelta is too small (noise filtering)
    // But allow if we're already tracking a scroll (to capture direction changes)
    // Lower threshold to catch more scrolls
    // CRITICAL: If we're already tracking a scroll, we MUST process ALL updates
    // to ensure _scrollEndPosition is updated with the final position
    if (scrollDelta.abs() < 0.01 && _scrollStartTime == null) {
      return; // Skip only on initial scroll if delta is too small
    }

    // IMPORTANT: When a scroll is active, we must update positions even for tiny deltas
    // This ensures we capture the true final position when scroll stops

    // If this is the start of a new scroll, check if it's a continuation of previous scroll
    if (_scrollStartTime == null) {
      // Check if this is a continuation of a recently finalized scroll
      final isContinuation = _lastScrollFinalizedTime != null &&
          now.difference(_lastScrollFinalizedTime!).inMilliseconds <
              _scrollContinuationWindowMs;

      if (isContinuation &&
          _scrollDirection != null &&
          _preservedStartPosition != null) {
        // Continue the previous scroll gesture
        _scrollStartTime =
            _lastScrollFinalizedTime; // Use the original start time
        // Restore the original start position for accurate distance calculation
        _scrollStartPosition = _preservedStartPosition!;
        _scrollEndPosition = currentPosition;
        // For continuation, set _lastScrollPosition to track future direction changes
        _lastScrollPosition = currentPosition - scrollDelta;
        // Track last valid position for continuation
        if (currentPosition != 0.0) {
          _lastValidEndPosition = currentPosition;
        }
        // Check if direction changed in continuation
        final continuationDirection =
            scrollDelta > 0 ? ScrollDirection.down : ScrollDirection.up;
        if (_scrollDirection != continuationDirection) {
          _hasDirectionReversal = true;
          print(
              '🔄 Direction reversal in continuation: $_scrollDirection -> $continuationDirection');
        }
        _scrollDirection = continuationDirection; // Update to new direction
        print(
            '🔄 Scroll continuation: startPos=$_scrollStartPosition, currentPos=$currentPosition, direction=$_scrollDirection, delta=$scrollDelta');
      } else {
        // Start a completely new scroll (not a continuation)
        _scrollStartTime = now;
        // Clear preserved position since this is a new scroll
        _preservedStartPosition = null;
        // Calculate start position: currentPosition already includes scrollDelta,
        // so start position = currentPosition - scrollDelta
        // For downward: scrollDelta > 0, so startPos = currentPos - positive = lower value ✓
        // For upward: scrollDelta < 0, so startPos = currentPos - negative = currentPos + |scrollDelta| = higher value ✓
        _scrollStartPosition = currentPosition - scrollDelta;
        // Set end position to current position (will be updated on each scroll update)
        // IMPORTANT: For single-update scrolls, this is the final position, so preserve it
        _scrollEndPosition = currentPosition;
        _lastScrollPosition = currentPosition;
        // Store initial end position as backup in case it gets reset
        // This is critical for single-update scrolls where _scrollEndPosition might be reset
        _initialEndPosition = currentPosition;
        // Also track as last valid position (important for upward scrolls that reach 0.0)
        if (currentPosition != 0.0) {
          _lastValidEndPosition = currentPosition;
        } else {
          _lastValidEndPosition = null; // Clear if starting at 0.0
        }
        print('💾 Stored initial end position: $_initialEndPosition');
        _hasDirectionReversal = false;
        // Use scrollDelta for initial direction
        _scrollDirection =
            scrollDelta > 0 ? ScrollDirection.down : ScrollDirection.up;
        // Initialize velocity tracking
        _lastVelocityTime = now;
        print(
            '📜 Scroll started: direction=$_scrollDirection, delta=$scrollDelta, startPos=$_scrollStartPosition, currentPos=$currentPosition, endPos=$_scrollEndPosition');
      }
    } else {
      // For subsequent updates, determine direction from both scrollDelta and position change
      // Use scrollDelta as primary (more immediate), position change as fallback
      final positionChange = currentPosition - _lastScrollPosition;

      // Determine direction from scrollDelta if significant
      // Use a very low threshold to catch direction changes even during fast scrolling
      ScrollDirection? newDirection;

      // Primary: Use scrollDelta (most immediate indicator of direction)
      // Lower threshold to catch fast direction reversals
      if (scrollDelta.abs() > 0.001) {
        newDirection =
            scrollDelta > 0 ? ScrollDirection.down : ScrollDirection.up;
      }
      // Fallback: Use position change if scrollDelta is too small (might happen at direction change point)
      else if (positionChange.abs() > 0.1) {
        newDirection =
            positionChange > 0 ? ScrollDirection.down : ScrollDirection.up;
      }
      // If both are too small, keep the last known direction (but still check for reversal)
      else {
        newDirection = _scrollDirection;
      }

      // Check for direction reversal: if direction changed from previous stored direction
      // This is the key check - if newDirection differs from _scrollDirection, we have a reversal
      // IMPORTANT: Check even if scrollDelta is small, as direction changes often happen with small deltas
      if (newDirection != null &&
          _scrollDirection != null &&
          _scrollDirection != newDirection) {
        _hasDirectionReversal = true;
        print(
            '🔄 Direction reversal detected DURING scroll: $_scrollDirection -> $newDirection (delta=$scrollDelta, posChange=$positionChange, currentPos=$currentPosition, lastPos=$_lastScrollPosition)');
      }

      // Update direction if we have a valid new direction
      // Always update direction when we detect a change, even if movement is small
      // This ensures we catch fast direction reversals
      if (newDirection != null && newDirection != _scrollDirection) {
        _scrollDirection = newDirection;
        // Update last position to track future direction changes
        _lastScrollPosition = currentPosition;
      } else if (positionChange.abs() > 0.1 || scrollDelta.abs() > 0.01) {
        // Update position even if direction didn't change, to track movement
        _lastScrollPosition = currentPosition;
      }

      // Always update end position to track the latest position
      // This ensures we capture the final position when scroll stops
      // CRITICAL: This must be updated on EVERY scroll update to capture the true end position
      _scrollEndPosition = currentPosition;
      // Also update _lastScrollPosition to ensure we have a valid fallback
      _lastScrollPosition = currentPosition;
      // Track last valid (non-zero) position - important when scroll reaches 0.0
      // This prevents losing the true final position when scrolling to the top
      if (currentPosition != 0.0) {
        _lastValidEndPosition = currentPosition;
      }
      // Debug: Log position updates to track what's happening
      if (scrollDelta.abs() > 1.0) {
        // print(
        //     '📏 Scroll update: currentPos=$currentPosition, endPos=$_scrollEndPosition, lastPos=$_lastScrollPosition, lastValid=$_lastValidEndPosition, delta=$scrollDelta');
      }

      // Calculate instantaneous velocity from scroll deltas
      // This is how native systems calculate velocity internally:
      // velocity = delta position / delta time
      if (_lastVelocityTime != null) {
        final timeDelta = now.difference(_lastVelocityTime!).inMilliseconds;
        if (timeDelta > 0 && scrollDelta.abs() > 0.01) {
          // Instantaneous velocity in pixels per second (native calculation method)
          // This mimics what Flutter's ScrollMetrics and native scroll views do internally
        }
      }
      _lastVelocityTime = now;
    }

    // Don't emit scroll events periodically - only emit when scroll stops (finalization)
    // This prevents too many events during slow scrolling and matches Android behavior

    // Cancel previous timer and start a new one
    // Wait longer before finalizing to capture direction reversals
    // This keeps the gesture alive even if there are small gaps between direction changes
    // IMPORTANT: We reset the timer on every scroll update, so as long as the user keeps scrolling
    // (even if direction changes), the scroll won't be finalized until they stop for 1200ms
    _scrollStopTimer?.cancel();
    _scrollStopTimer =
        Timer(const Duration(milliseconds: _scrollStopThresholdMs), () {
      _finalizeScroll();
    });
  }

  // Removed periodic emission - only emit on finalization to prevent too many events
  // during slow scrolling. This matches Android behavior where scroll events are only
  // emitted when the scroll gesture stops (after 1200ms of no updates).

  void _finalizeScroll() {
    if (_scrollStartTime == null) {
      return;
    }

    final now = DateTime.now();
    final durationMs = now.difference(_scrollStartTime!).inMilliseconds;

    // CRITICAL: Capture end position values BEFORE any potential reset
    // Store current values to prevent them from being lost
    final storedEndPosition = _scrollEndPosition;
    final storedLastPosition = _lastScrollPosition;
    final storedInitialEndPosition = _initialEndPosition;
    final storedLastValidPosition = _lastValidEndPosition;

    // Determine the final end position for distance calculation
    // Priority order:
    // 1. _scrollEndPosition (should be updated on every scroll update)
    //    BUT: If it's 0.0 and we have a valid lastValidPosition, use that instead
    // 2. _lastValidEndPosition (last non-zero position - critical for scrolls that reach 0.0)
    // 3. _lastScrollPosition (fallback if _scrollEndPosition was reset)
    // 4. _initialEndPosition (backup for single-update scrolls)
    // 5. _scrollStartPosition (last resort, results in 0 distance)
    double finalEndPosition;

    if (storedEndPosition != 0.0) {
      // Primary: Use the stored end position (most reliable)
      finalEndPosition = storedEndPosition;
    } else if (storedLastValidPosition != null &&
        storedLastValidPosition != 0.0) {
      // Fallback 1: Use last valid (non-zero) position
      // This is critical when scrolling reaches 0.0 - we need the last position before 0.0
      finalEndPosition = storedLastValidPosition;
      print(
          '⚠️ Using _lastValidEndPosition as fallback (scroll reached 0.0): $storedLastValidPosition');
    } else if (storedLastPosition != 0.0) {
      // Fallback 2: Use last known position
      finalEndPosition = storedLastPosition;
      print('⚠️ Using _lastScrollPosition as fallback: $storedLastPosition');
    } else if (storedInitialEndPosition != null &&
        storedInitialEndPosition != 0.0) {
      // Fallback 3: Use initial end position (for single-update scrolls)
      finalEndPosition = storedInitialEndPosition;
      print(
          '⚠️ Using _initialEndPosition as fallback: $storedInitialEndPosition');
    } else {
      // Last resort: Use start position (will result in 0 distance/velocity)
      finalEndPosition = _scrollStartPosition;
      print(
          '⚠️ WARNING: All end position values are 0.0 or null! Using start position (distance will be 0)');
    }

    // Calculate distance correctly for both directions
    // For downward scroll: endPosition > startPosition (positive)
    // For upward scroll: endPosition < startPosition (negative, so abs() makes it positive)
    final rawDistance = finalEndPosition - _scrollStartPosition;
    final distancePx = rawDistance.abs();

    // Emit scroll event if there's any movement (even small)
    // The ML engineer said to wait until scroll stops, so we emit even for small distances
    if (durationMs > 0 && distancePx >= 0) {
      // Calculate average velocity in pixels per second
      // Velocity = distance / time (always positive, direction is separate)
      final effectiveDistance = distancePx > 0 ? distancePx : 1.0;
      final velocity =
          (effectiveDistance / durationMs * 1000).clamp(0.0, 10000.0);

      // Debug: Log the calculation details
      print(
          '📊 Scroll finalization: startPos=$_scrollStartPosition, endPos=$finalEndPosition (stored=$storedEndPosition, last=$storedLastPosition, lastValid=$storedLastValidPosition, initial=$storedInitialEndPosition), rawDistance=$rawDistance, distance=$distancePx, duration=${durationMs}ms, velocity=$velocity px/s');

      // Calculate acceleration using proper physics formula
      // For constant acceleration from rest: a = 2d/t²
      // where d = distance (pixels), t = time (seconds)
      final durationSeconds = durationMs / 1000.0;
      final acceleration = durationSeconds > 0.1
          ? (2.0 * effectiveDistance) / (durationSeconds * durationSeconds)
          : 0.0;
      final clampedAcceleration = acceleration.clamp(0.0, 50000.0);

      // Emit scroll event with calculated metrics
      print(
          '📤 Emitting scroll: direction=${_scrollDirection ?? ScrollDirection.down}, reversal=$_hasDirectionReversal, velocity=$velocity px/s, acceleration=$clampedAcceleration px/s², distance=$distancePx px');
      _emitScrollEvent(
        velocity: velocity,
        acceleration: clampedAcceleration,
        direction: _scrollDirection ?? ScrollDirection.down,
        directionReversal: _hasDirectionReversal,
      );
    }

    // Reset velocity tracking
    _lastVelocityTime = null;

    // Mark scroll as finalized (but keep state for potential continuation)
    _lastScrollFinalizedTime = DateTime.now();
    // Preserve start position for potential continuation
    _preservedStartPosition = _scrollStartPosition;
    // Don't reset _scrollDirection or _hasDirectionReversal in case this scroll continues
    _scrollStartTime = null;
    _scrollEndPosition = 0.0;
    _lastScrollPosition = 0.0;
    _initialEndPosition = null; // Clear backup
    _lastValidEndPosition = null; // Clear last valid position
    // Keep _scrollDirection and _hasDirectionReversal for continuation detection
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_tapDownTime == null) return;

    final now = DateTime.now();
    final tapDurationMs = now.difference(_tapDownTime!).inMilliseconds;
    final longPress = tapDurationMs >= _longPressThresholdMs;

    _emitTapEvent(
      tapDurationMs: tapDurationMs,
      longPress: longPress,
    );

    _tapDownTime = null;
  }

  void _handlePan(DragUpdateDetails details) {
    if (_swipeStartPosition == null || _swipeStartTime == null) return;

    final currentPosition = details.globalPosition;
    final delta = currentPosition - _swipeStartPosition!;
    final distance = delta.distance;

    // Only treat as swipe if movement is significant AND primarily horizontal
    // Check if horizontal movement is greater than vertical movement
    if (distance > _swipeThresholdPx && delta.dx.abs() > delta.dy.abs()) {
      _isSwipe = true;
      _hasSwipedSinceTapDown = true; // Mark that swipe occurred during tap
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_swipeStartPosition == null ||
        _swipeStartTime == null ||
        _swipeLastPosition == null ||
        !_isSwipe) {
      _swipeStartTime = null;
      _swipeStartPosition = null;
      _swipeLastPosition = null;
      return;
    }

    final now = DateTime.now();
    final durationMs = now.difference(_swipeStartTime!).inMilliseconds;

    if (durationMs > 0) {
      // Use the last position to calculate distance
      final delta = _swipeLastPosition! - _swipeStartPosition!;
      final distancePx = delta.distance;
      final velocity = (distancePx / durationMs * 1000).clamp(0.0, 10000.0);

      // Calculate acceleration (change in velocity over time)
      // Simplified: use velocity and duration
      final acceleration =
          durationMs > 100 ? (velocity / (durationMs / 1000.0)) : 0.0;

      // Determine swipe direction (horizontal only: left or right)
      SwipeDirection direction;
      // Right swipe: positive x direction
      // Left swipe: negative x direction
      direction = (delta.dx > 0) ? SwipeDirection.right : SwipeDirection.left;

      _emitSwipeEvent(
        direction: direction,
        distancePx: distancePx,
        durationMs: durationMs,
        velocity: velocity,
        acceleration: acceleration,
      );
    }

    _swipeStartTime = null;
    _swipeStartPosition = null;
    _swipeLastPosition = null;
    _isSwipe = false;
  }

  void _emitScrollEvent({
    required double velocity,
    required double acceleration,
    required ScrollDirection direction,
    required bool directionReversal,
  }) {
    final event = BehaviorEvent.scroll(
      sessionId: widget.sessionId ?? "current",
      velocity: velocity,
      acceleration: acceleration,
      direction: direction,
      directionReversal: directionReversal,
    );
    widget.onEvent?.call(event);
    // Auto-send to SDK if provided
    widget.behavior?.sendEvent(event);
  }

  void _emitTapEvent({
    required int tapDurationMs,
    required bool longPress,
  }) {
    final event = BehaviorEvent.tap(
      sessionId: widget.sessionId ?? "current",
      tapDurationMs: tapDurationMs,
      longPress: longPress,
    );
    widget.onEvent?.call(event);
    // Auto-send to SDK if provided
    widget.behavior?.sendEvent(event);
  }

  void _emitSwipeEvent({
    required SwipeDirection direction,
    required double distancePx,
    required int durationMs,
    required double velocity,
    required double acceleration,
  }) {
    final event = BehaviorEvent.swipe(
      sessionId: widget.sessionId ?? "current",
      direction: direction,
      distancePx: distancePx,
      durationMs: durationMs,
      velocity: velocity,
      acceleration: acceleration,
    );
    widget.onEvent?.call(event);
    // Auto-send to SDK if provided
    widget.behavior?.sendEvent(event);
  }
}

/// A TextField wrapper for behavior tracking.
/// Tracks typing sessions from keyboard open (focus gain) to keyboard close (focus loss).
/// Calculates all typing metrics and emits a typing event when the session ends.
/// Also detects paste operations in the text field.
class BehaviorTextField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final int? maxLines;
  final Function(BehaviorEvent)? onTypingEvent;
  final Function(BehaviorEvent)? onClipboardEvent;
  final SynheartBehavior? behavior; // Optional SDK instance to auto-send events
  final String? sessionId; // Optional session ID

  const BehaviorTextField({
    super.key,
    this.controller,
    this.decoration,
    this.maxLines,
    this.onTypingEvent,
    this.onClipboardEvent,
    this.behavior,
    this.sessionId,
  });

  @override
  State<BehaviorTextField> createState() => _BehaviorTextFieldState();

  /// Static method to end all active typing sessions
  /// Called when session ends or app goes to background
  static void endAllTypingSessions() {
    _BehaviorTextFieldState.endAllTypingSessions();
  }
}

class _BehaviorTextFieldState extends State<BehaviorTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  // Typing session tracking
  DateTime? _sessionStartTime;
  DateTime? _lastKeystrokeTime;
  int _previousLength = 0;
  List<int> _interKeyLatencies =
      []; // Store latencies in milliseconds (only actual intervals, no 0 for first keystroke)
  int _backspaceCount = 0; // Track number of backspace/delete operations
  int _pasteCount = 0;
  int _copyCount = 0;
  int _cutCount = 0;

  // Paste detection
  static const int _pasteDetectionThreshold =
      2; // Characters added to detect paste (lowered from 5 to catch shorter pastes)
  static const int _pasteEventDebounceMs =
      500; // Don't emit another paste event within 500ms
  DateTime? _lastTextChangeTime;
  DateTime? _lastPasteEventTime; // Track when we last emitted a paste event
  int? _lastPasteLength; // Track the text length when we last detected a paste

  // Copy/Cut detection
  TextSelection? _lastSelection; // Track last text selection to detect cut/copy
  DateTime? _lastSelectionTime; // Track when selection was made
  DateTime? _lastCopyEventTime; // Track when we last emitted a copy event
  DateTime? _lastCutEventTime; // Track when we last emitted a cut event
  static const int _clipboardEventDebounceMs =
      1000; // Don't emit another clipboard event within 1000ms (increased from 500ms)
  bool _hasProcessedSelectionForClipboard =
      false; // Track if we've already processed this selection for clipboard
  String?
      _lastClipboardEventId; // Track the last clipboard event ID to prevent exact duplicates

  // Static list to track all active BehaviorTextField instances for session/app lifecycle handling
  static final List<_BehaviorTextFieldState> _activeInstances = [];

  // Constants from note-4.md
  static const int gapThresholdMs = 5000; // 5 seconds for gap count
  static const int activityThresholdMs = 2000; // 2 seconds for activity ratio
  static const int deepTypingDurationSeconds = 60; // 1 minute
  static const double vMax = 10.0; // taps/s for speed normalization
  static const double w1 = 0.4; // weight for typing speed
  static const double w2 = 0.35; // weight for gap behavior
  static const double w3 = 0.25; // weight for cadence stability

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
    _controller.addListener(_onSelectionChanged);
    _focusNode.addListener(_onFocusChanged);
    _previousLength = _controller.text.length;
    // Register this instance for session/app lifecycle handling
    _activeInstances.add(this);
  }

  @override
  void dispose() {
    // End any active session before disposing
    _endTypingSession();
    // Unregister this instance
    _activeInstances.remove(this);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
      _controller.removeListener(_onSelectionChanged);
    }
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// Static method to end all active typing sessions
  /// Called when session ends or app goes to background
  static void endAllTypingSessions() {
    for (final instance
        in List<_BehaviorTextFieldState>.from(_activeInstances)) {
      instance._endTypingSession();
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // Keyboard opened - start typing session only if not already started
      // This prevents resetting the session if focus is briefly lost during clipboard operations
      if (_sessionStartTime == null) {
        _startTypingSession();
      }
    } else {
      // Keyboard closed or focus lost - end typing session immediately
      _endTypingSession();
    }
  }

  void _startTypingSession() {
    // Always start fresh session when focus is gained
    _sessionStartTime = DateTime.now();
    _lastKeystrokeTime = null;
    _interKeyLatencies.clear();
    _backspaceCount = 0; // Reset backspace count for new session
    _pasteCount = 0;
    _copyCount = 0;
    _cutCount = 0;
    _previousLength = _controller.text.length;
    _hasProcessedSelectionForClipboard =
        false; // Reset clipboard processing flag
  }

  void _endTypingSession() {
    // If we have an active session, emit the event (even if only 1 keystroke)
    if (_sessionStartTime != null) {
      // Check if we have at least one keystroke (either intervals or first keystroke)
      // If _interKeyLatencies is empty, we might still have typed 1 character
      if (_interKeyLatencies.isNotEmpty || _lastKeystrokeTime != null) {
        print(
            '⌨️ [END SESSION] Ending typing session - intervals: ${_interKeyLatencies.length}, backspaces: $_backspaceCount');
        // Emit typing session event
        _emitTypingSessionEvent();
      } else {
        print(
            '⌨️ [END SESSION] No keystrokes detected, skipping event emission');
      }
    }

    // Always reset session state when focus is lost
    _sessionStartTime = null;
    _lastKeystrokeTime = null;
    _interKeyLatencies.clear();
  }

  void _onTextChanged() {
    // Only track keystrokes when text field has focus
    if (!_focusNode.hasFocus) {
      _previousLength = _controller.text.length;
      return;
    }

    final currentLength = _controller.text.length;
    final now = DateTime.now();
    final lengthDiff = currentLength - _previousLength;

    // DEBUG: Log all text changes
    print(
        '📝 [TEXT CHANGE] previousLength: $_previousLength, currentLength: $currentLength, lengthDiff: $lengthDiff');
    print(
        '📝 [TEXT CHANGE] _interKeyLatencies.length: ${_interKeyLatencies.length}, _backspaceCount: $_backspaceCount');
    print(
        '📝 [TEXT CHANGE] _sessionStartTime: $_sessionStartTime, _lastKeystrokeTime: $_lastKeystrokeTime');

    // Only detect when text is added (not deleted)
    if (currentLength > _previousLength) {
      // Detect paste: large text insertion in short time
      final timeSinceLastChange = _lastTextChangeTime != null
          ? now.difference(_lastTextChangeTime!).inMilliseconds
          : null;

      // Debug logging for paste detection
      print(
          '📋 BehaviorTextField: Text changed - lengthDiff: $lengthDiff, timeSinceLastChange: $timeSinceLastChange ms, threshold: $_pasteDetectionThreshold');

      // Paste detection: if 2+ characters added, consider it a paste
      // This distinguishes paste from normal typing (which typically adds 1 char at a time)
      if (lengthDiff >= _pasteDetectionThreshold) {
        // Check if we recently emitted a paste event for the same text length (prevent duplicates)
        final isDuplicatePaste =
            _lastPasteLength != null && currentLength == _lastPasteLength;

        // Also check time-based debounce
        final timeSinceLastPaste = _lastPasteEventTime != null
            ? now.difference(_lastPasteEventTime!).inMilliseconds
            : null;

        // Create a unique event ID for this paste operation
        final pasteEventId =
            'paste_${currentLength}_${now.millisecondsSinceEpoch}';

        if (!isDuplicatePaste &&
            (timeSinceLastPaste == null ||
                timeSinceLastPaste >= _pasteEventDebounceMs) &&
            _lastClipboardEventId != pasteEventId) {
          // This looks like a paste operation and we haven't emitted one for this text length
          _emitPasteEvent();
          _lastPasteEventTime = now;
          _lastPasteLength =
              currentLength; // Track the length when we detected paste
          _lastClipboardEventId =
              pasteEventId; // Track this event to prevent duplicates
          // Don't count paste as typing - but keep the session alive
          // Just update last keystroke time so paste doesn't create a gap in typing metrics
          // This allows typing to continue after paste without breaking the session
          if (_sessionStartTime == null) {
            _startTypingSession();
          }
          // Update last keystroke time to prevent paste from creating a large gap
          // but don't reset the session - keep all typing data intact
          _lastKeystrokeTime = now;
        }
      } else {
        // Normal typing - track as before
        // Start session if not already started
        if (_sessionStartTime == null) {
          _startTypingSession();
        }

        // Calculate inter-key latency
        // Only store actual intervals (not 0 for first keystroke)
        if (_lastKeystrokeTime != null) {
          final latency = now.difference(_lastKeystrokeTime!).inMilliseconds;
          _interKeyLatencies.add(latency);
          print(
              '⌨️ [TYPING] Keystroke detected - latency: ${latency}ms, total intervals: ${_interKeyLatencies.length}');
        } else {
          // First keystroke: don't store interval, but log it
          print('⌨️ [TYPING] First keystroke detected (no interval yet)');
        }
        // First keystroke: don't store anything (no previous keystroke to measure interval)

        _lastKeystrokeTime = now;
      }

      _lastTextChangeTime = now;
    } else if (currentLength < _previousLength) {
      // Text was deleted (backspace/delete/cut)
      final deletedChars = _previousLength - currentLength;

      // Heuristic cut detection: if there was a selection and text was deleted, it's likely a cut
      // Check if we had a selection recently (even if it's now cleared, we track it)
      // We need to check BEFORE the selection was cleared, so we look at _lastSelection
      // BUT only if we haven't already processed this selection for a clipboard operation
      final hadValidSelection = _lastSelection != null &&
          _lastSelection!.isValid &&
          _lastSelection!.start != _lastSelection!.end;

      // Track if we detected a cut in this deletion - if so, don't count as backspace
      bool cutDetected = false;

      if (hadValidSelection && !_hasProcessedSelectionForClipboard) {
        // There was a selection, and text was deleted - likely a cut operation
        // Check debounce to prevent duplicate events
        final timeSinceLastCut = _lastCutEventTime != null
            ? now.difference(_lastCutEventTime!).inMilliseconds
            : null;

        // Create a unique event ID for this cut operation
        final cutEventId = 'cut_${deletedChars}_${now.millisecondsSinceEpoch}';

        if (timeSinceLastCut == null ||
            timeSinceLastCut >= _clipboardEventDebounceMs) {
          if (_lastClipboardEventId != cutEventId) {
            _emitCutEvent();
            _lastCutEventTime = now;
            _lastClipboardEventId =
                cutEventId; // Track this event to prevent duplicates
            // Mark that we've processed this selection to prevent copy detection from firing
            _hasProcessedSelectionForClipboard = true;
            cutDetected = true; // Mark that we detected a cut
            _lastSelection = null; // Clear selection after cut
            _lastSelectionTime = null; // Clear selection time
          } else {
            _hasProcessedSelectionForClipboard = true;
            cutDetected = true; // Already processed as cut
            _lastSelection = null;
            _lastSelectionTime = null;
          }
        } else {
          _hasProcessedSelectionForClipboard = true; // Still mark as processed
          cutDetected = true; // Debounced, but still a cut
          _lastSelection = null; // Still clear selection
          _lastSelectionTime = null;
        }
      }

      // Only count as backspace if it wasn't a cut
      if (!cutDetected) {
        // No selection or invalid selection - treat as backspace/delete
        _backspaceCount += deletedChars;
        print(
            '⌫ [BACKSPACE] Backspace detected - deleted: $deletedChars chars, total backspaces: $_backspaceCount');
        print(
            '⌫ [BACKSPACE] _previousLength: $_previousLength, currentLength: $currentLength');
        print(
            '⌫ [BACKSPACE] _interKeyLatencies.length: ${_interKeyLatencies.length}');
      } else {
        print(
            '⌫ [BACKSPACE] Skipping backspace count - this was a cut operation (deleted: $deletedChars chars)');
      }
    }

    _previousLength = currentLength;
  }

  void _onSelectionChanged() {
    final currentSelection = _controller.selection;
    final now = DateTime.now();

    // Detect copy: if there was a valid selection and now it's cleared (no selection or collapsed)
    // BUT only if we haven't already processed this selection for a clipboard operation (cut/copy)
    if (_lastSelection != null &&
        _lastSelection!.isValid &&
        _lastSelection!.start != _lastSelection!.end &&
        !_hasProcessedSelectionForClipboard) {
      // There was a valid selection
      if (!currentSelection.isValid ||
          currentSelection.start == currentSelection.end) {
        // Selection was cleared - this might be a copy operation
        // Check timing: if selection was held for at least 100ms, it's likely a copy
        // (very short selections are usually accidental)
        // Check debounce to prevent duplicate copy events
        final timeSinceLastCopy = _lastCopyEventTime != null
            ? now.difference(_lastCopyEventTime!).inMilliseconds
            : null;

        // Create a unique event ID for this copy operation based on selection
        final selectionKey = _lastSelection!.start.toString() +
            '_' +
            _lastSelection!.end.toString();
        final copyEventId =
            'copy_${selectionKey}_${now.millisecondsSinceEpoch}';

        if (timeSinceLastCopy == null ||
            timeSinceLastCopy >= _clipboardEventDebounceMs) {
          if (_lastClipboardEventId != copyEventId) {
            if (_lastSelectionTime != null) {
              final timeSinceSelection =
                  now.difference(_lastSelectionTime!).inMilliseconds;
              if (timeSinceSelection >= 100) {
                // Reduced threshold for better detection
                // Selection was held and then cleared - likely a copy
                _emitCopyEvent();
                _lastCopyEventTime = now;
                _lastClipboardEventId =
                    copyEventId; // Track this event to prevent duplicates
                // Mark that we've processed this selection to prevent duplicate detection
                _hasProcessedSelectionForClipboard = true;
                // Clear selection tracking to prevent re-detection
                _lastSelection = null;
                _lastSelectionTime = null;
              } else {
                print(
                    '❌ [COPY] Skipping - timeSinceSelection ($timeSinceSelection ms) < 100ms threshold');
              }
            } else {
              // Selection existed but we don't have timing - still likely a copy
              print(
                  '✅ [COPY] Detected COPY - selection cleared (no timing), eventId: $copyEventId');
              _emitCopyEvent();
              _lastCopyEventTime = now;
              _lastClipboardEventId =
                  copyEventId; // Track this event to prevent duplicates
              print(
                  '✅ [COPY] Event emitted and tracked - _lastClipboardEventId set to: $_lastClipboardEventId');
              // Mark that we've processed this selection
              _hasProcessedSelectionForClipboard = true;
              // Clear selection tracking to prevent re-detection
              _lastSelection = null;
              _lastSelectionTime = null;
            }
          } else {
            _hasProcessedSelectionForClipboard = true;
            _lastSelection = null;
            _lastSelectionTime = null;
          }
        } else {
          // Still clear selection tracking even if we skip the event
          _lastSelection = null;
          _lastSelectionTime = null;
          _hasProcessedSelectionForClipboard = true;
        }
      }
    }

    // Update selection tracking
    if (currentSelection.isValid &&
        currentSelection.start != currentSelection.end) {
      // New valid selection - reset the processed flag
      _lastSelection = currentSelection;
      _lastSelectionTime = now;
      _hasProcessedSelectionForClipboard =
          false; // Reset flag for new selection
    } else {
      // Selection cleared or invalid
      // Only update if we haven't already cleared it due to copy detection
      if (_lastSelection != null && !_hasProcessedSelectionForClipboard) {
        _lastSelection = currentSelection;
        _lastSelectionTime = null;
      }
    }
  }

  void _emitPasteEvent() {
    _emitClipboardEvent(ClipboardAction.paste);
  }

  void _emitCutEvent() {
    _emitClipboardEvent(ClipboardAction.cut);
  }

  /// Manually emit a copy event (for apps that want to track copy operations)
  /// This is also called automatically when copy is detected heuristically
  void emitCopyEvent() {
    _emitClipboardEvent(ClipboardAction.copy);
  }

  void _emitCopyEvent() {
    _emitClipboardEvent(ClipboardAction.copy);
  }

  void _emitClipboardEvent(ClipboardAction action) {
    switch (action) {
      case ClipboardAction.paste:
        _pasteCount++;
        break;
      case ClipboardAction.copy:
        _copyCount++;
        break;
      case ClipboardAction.cut:
        _cutCount++;
        break;
    }
    final event = BehaviorEvent.clipboard(
      sessionId: widget.sessionId ?? "current",
      action: action,
      context: ClipboardContext.textField,
    );

    if (widget.onClipboardEvent != null) {
      widget.onClipboardEvent?.call(event);
      // If onClipboardEvent is provided, don't auto-send via behavior
      // The callback is responsible for sending to SDK if needed
    } else {
      // Only auto-send to SDK if onClipboardEvent is not provided
      if (widget.behavior != null) {
        widget.behavior?.sendEvent(event);
      }
    }
  }

  void _emitTypingSessionEvent() {
    // Allow emitting even if _interKeyLatencies is empty (single keystroke case)
    // In that case, typingTapCount will be 1 (0 intervals + 1 first keystroke)
    if (_sessionStartTime == null) {
      return;
    }

    final sessionEndTime = _lastKeystrokeTime ?? DateTime.now();
    final durationMs =
        sessionEndTime.difference(_sessionStartTime!).inMilliseconds;
    final durationSeconds = durationMs / 1000.0;

    // N = typing_tap_count (total number of keyboard tap events)
    // IMPORTANT: _interKeyLatencies only stores intervals between keystrokes
    // If we have N keystrokes, we have (N-1) intervals
    // So typingTapCount = _interKeyLatencies.length + 1 (to account for first keystroke)
    final typingTapCount = _interKeyLatencies.length + 1;
    print('⌨️ [TYPING SESSION] Calculating typing metrics:');
    print(
        '⌨️ [TYPING SESSION] _interKeyLatencies.length: ${_interKeyLatencies.length}');
    print(
        '⌨️ [TYPING SESSION] typingTapCount (intervals + 1): $typingTapCount');
    print('⌨️ [TYPING SESSION] _backspaceCount: $_backspaceCount');

    // typing_speed = N / T (taps per second)
    final typingSpeed =
        durationSeconds > 0 ? typingTapCount / durationSeconds : 0.0;

    // mean_inter_tap_interval_ms = μ_Δt = (1 / (N - 1)) × Σ(i=2 to N) Δtᵢ
    // The average time elapsed between consecutive keyboard tap events
    // Sum of all consecutive intervals / (n-1) where n = number of keystrokes
    double meanInterTapIntervalMs = 0.0;
    if (_interKeyLatencies.isNotEmpty) {
      // _interKeyLatencies contains only actual intervals (no 0 for first keystroke)
      // If we have N keystrokes, we have N-1 intervals stored in _interKeyLatencies
      final sum =
          _interKeyLatencies.fold<int>(0, (sum, latency) => sum + latency);
      // Number of intervals = number of keystrokes - 1
      // Since typingTapCount = _interKeyLatencies.length + 1, we have:
      // intervalCount = typingTapCount - 1 = _interKeyLatencies.length
      final intervalCount = _interKeyLatencies.length;
      meanInterTapIntervalMs = intervalCount > 0 ? sum / intervalCount : 0.0;
    }

    // typing_cadence_variability: Standard deviation of (mean_inter_tap_interval_ms)
    // This is the standard deviation of inter-tap intervals around the mean
    // IMPORTANT: Units must match mean_inter_tap_interval_ms
    // Both mean_inter_tap_interval_ms and typing_cadence_variability are ALWAYS in milliseconds
    // - mean_inter_tap_interval_ms is calculated from _interKeyLatencies (stored in milliseconds)
    // - typing_cadence_variability is the standard deviation of those same millisecond values
    // σ_Δt = √( (1 / (N - 2)) × Σ(i=2 to N) (Δtᵢ - μ_Δt)² )
    // Where N = number of keystrokes, so we have (N-1) intervals
    // Formula denominator is (N-2), so we need at least 3 keystrokes (2 intervals) to calculate
    double typingCadenceVariability = 0.0;
    if (typingTapCount >= 3 &&
        _interKeyLatencies.length >= 2 &&
        meanInterTapIntervalMs > 0) {
      // _interKeyLatencies contains only actual intervals (N-1 intervals for N keystrokes)
      // Formula uses (N-2) as denominator: if we have (N-1) intervals, divide by (N-1-1) = (N-2)
      final nIntervals =
          _interKeyLatencies.length; // This is (N-1) where N = keystrokes
      final denominator =
          nIntervals - 1; // This gives (N-2) as required by formula

      if (denominator > 0) {
        // Calculate standard deviation of intervals around the mean
        // Both _interKeyLatencies and meanInterTapIntervalMs are in milliseconds
        // Therefore typingCadenceVariability will also be in milliseconds (same units)
        final sumSquaredDiffs = _interKeyLatencies
            .map((latency) =>
                (latency - meanInterTapIntervalMs) *
                (latency - meanInterTapIntervalMs))
            .fold<double>(0.0, (sum, diff) => sum + diff);

        final variance = sumSquaredDiffs / denominator;
        typingCadenceVariability = math.sqrt(variance);
        // typingCadenceVariability is now in the same units as meanInterTapIntervalMs
      }
    }

    // typing_cadence_stability = 1 - min(1, (σ_Δt / μ_Δt))
    double typingCadenceStability = 0.0;
    if (meanInterTapIntervalMs > 0 && typingCadenceVariability > 0) {
      final cv = typingCadenceVariability / meanInterTapIntervalMs;
      typingCadenceStability = (1.0 - math.min(1.0, cv)).clamp(0.0, 1.0);
    }

    // typing_gap_count = Σ(i=2 to N) 1(Δtᵢ > τ_gap) where τ_gap = 5 seconds
    final typingGapCount =
        _interKeyLatencies.where((latency) => latency > gapThresholdMs).length;

    // typing_gap_ratio = typing_gap_count / (N - 1)
    // N = number of keystrokes, so (N - 1) = number of intervals
    // Since typingTapCount = _interKeyLatencies.length + 1, we have:
    // intervalCount = typingTapCount - 1 = _interKeyLatencies.length
    final intervalCount = _interKeyLatencies.length;
    final typingGapRatio =
        intervalCount > 0 ? typingGapCount / intervalCount : 0.0;

    // typing_burstiness
    // Step 1: B_raw = (σ_ITI - μ_ITI) / (σ_ITI + μ_ITI)
    // Step 2: B_norm = (B_raw + 1) / 2
    double typingBurstiness = 0.0;
    if (_interKeyLatencies.length > 1 &&
        meanInterTapIntervalMs > 0 &&
        typingCadenceVariability > 0) {
      final bRaw = (typingCadenceVariability - meanInterTapIntervalMs) /
          (typingCadenceVariability + meanInterTapIntervalMs);
      typingBurstiness = ((bRaw + 1.0) / 2.0).clamp(0.0, 1.0);
    }

    // typing_activity_ratio = (Σ(i=2 to N) min(Δtᵢ, τ_activity)) / T
    // where τ_activity = 2 seconds
    final activeTypingTime = _interKeyLatencies.fold<int>(
        0, (sum, latency) => sum + math.min(latency, activityThresholdMs));
    final typingActivityRatio =
        durationMs > 0 ? (activeTypingTime / durationMs).clamp(0.0, 1.0) : 0.0;

    // typing_speed_norm = min(1, (typing_speed / v_max))
    final typingSpeedNorm = math.min(1.0, typingSpeed / vMax);

    // typing_interaction_intensity = w₁ · typing_speed_norm + w₂ · (1 - typing_gap_ratio) + w₃ · typing_cadence_stability
    final typingInteractionIntensity = (w1 * typingSpeedNorm +
            w2 * (1.0 - typingGapRatio) +
            w3 * typingCadenceStability)
        .clamp(0.0, 1.0);

    // deep_typing = true if duration ≥ 60 seconds (1 minute)
    // ML engineer requirement: Only check duration, ignore other metrics
    final deepTyping = durationSeconds >= deepTypingDurationSeconds;

    // Create typing session event with all calculated metrics
    final typingEvent = BehaviorEvent.typing(
      sessionId: 'current',
      typingTapCount: typingTapCount,
      typingSpeed: typingSpeed,
      meanInterTapIntervalMs: meanInterTapIntervalMs,
      typingCadenceVariability: typingCadenceVariability,
      typingCadenceStability: typingCadenceStability,
      typingGapCount: typingGapCount,
      typingGapRatio: typingGapRatio,
      typingBurstiness: typingBurstiness,
      typingActivityRatio: typingActivityRatio,
      typingInteractionIntensity: typingInteractionIntensity,
      durationSeconds: durationSeconds.round(),
      startAt: _sessionStartTime!.toUtc().toIso8601String(),
      endAt: sessionEndTime.toUtc().toIso8601String(),
      deepTyping: deepTyping,
      backspaceCount: _backspaceCount,
      number_of_copy: _copyCount,
      number_of_paste: _pasteCount,
      number_of_cut: _cutCount,
    );

    // Emit event through callback
    widget.onTypingEvent?.call(typingEvent);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: widget.decoration,
      maxLines: widget.maxLines,
    );
  }
}
