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
  // Scroll tracking
  DateTime? _lastScrollTime;
  double _lastScrollVelocity = 0.0;
  ScrollDirection? _lastScrollDirection;
  bool _hasDirectionReversal = false;

  // Tap tracking
  DateTime? _tapDownTime;
  static const int _longPressThresholdMs = 500; // 500ms threshold

  // Swipe tracking
  DateTime? _swipeStartTime;
  Offset? _swipeStartPosition;
  Offset? _swipeLastPosition;
  bool _isSwipe = false;
  static const double _swipeThresholdPx = 50.0; // Minimum distance for swipe

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        _handleScroll(notification);
        return false; // Don't consume the notification
      },
      child: Listener(
        behavior: HitTestBehavior.translucent, // Don't block child widgets
        onPointerDown: (event) {
          // Track tap down time for tap detection
          _tapDownTime = DateTime.now();
        },
        onPointerUp: (event) {
          // Delay tap handling to let buttons handle their clicks first
          // Only emit tap event if it wasn't on an interactive widget
          Future.delayed(const Duration(milliseconds: 150), () {
            if (_tapDownTime != null && !_isSwipe) {
              _handleTap();
            }
            _tapDownTime = null;
          });
        },
        onPointerCancel: (event) {
          _tapDownTime = null;
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

    if (_lastScrollTime != null && scrollDelta != 0) {
      final timeDelta = now.difference(_lastScrollTime!).inMilliseconds;
      if (timeDelta > 0) {
        // Calculate velocity in pixels per second
        final velocity =
            (scrollDelta.abs() / timeDelta * 1000).clamp(0.0, 10000.0);

        // Calculate acceleration (change in velocity over time)
        final acceleration = _lastScrollVelocity > 0
            ? (velocity - _lastScrollVelocity) / (timeDelta / 1000.0)
            : 0.0;

        // Determine scroll direction
        final direction =
            scrollDelta > 0 ? ScrollDirection.down : ScrollDirection.up;

        // Check for direction reversal
        if (_lastScrollDirection != null && _lastScrollDirection != direction) {
          _hasDirectionReversal = true;
        }

        // Only emit if significant movement
        if (velocity > 10.0) {
          _emitScrollEvent(
            velocity: velocity,
            acceleration: acceleration,
            direction: direction,
            directionReversal: _hasDirectionReversal,
          );

          _lastScrollVelocity = velocity;
          _lastScrollDirection = direction;
          _hasDirectionReversal = false;
        }
      }
    } else {
      _lastScrollVelocity = 0.0;
    }

    _lastScrollTime = now;
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

    // If movement is significant, treat as swipe
    if (distance > _swipeThresholdPx) {
      _isSwipe = true;
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

      // Determine swipe direction
      final angle = math.atan2(delta.dy, delta.dx);
      SwipeDirection direction;
      if (angle.abs() < math.pi / 4) {
        direction = SwipeDirection.right;
      } else if (angle.abs() > 3 * math.pi / 4) {
        direction = SwipeDirection.left;
      } else if (angle > 0) {
        direction = SwipeDirection.down;
      } else {
        direction = SwipeDirection.up;
      }

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
/// Note: Keystrokes are not tracked as separate events in the new event model.
/// Text input interactions are captured as tap events.
class BehaviorTextField extends StatelessWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final int? maxLines;

  const BehaviorTextField({
    super.key,
    this.controller,
    this.decoration,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: decoration,
      maxLines: maxLines,
    );
  }
}
