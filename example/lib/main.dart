import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synheart Behavior Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BehaviorDemoPage(),
    );
  }
}

class BehaviorDemoPage extends StatefulWidget {
  const BehaviorDemoPage({super.key});

  @override
  State<BehaviorDemoPage> createState() => _BehaviorDemoPageState();
}

class _BehaviorDemoPageState extends State<BehaviorDemoPage>
    with WidgetsBindingObserver {
  // Constants
  static const int _maxEventsToKeep = 50;
  static const int _eventRetentionMinutes = 5;
  static const int _backgroundSessionTimeoutMinutes = 1; // 1 minute

  SynheartBehavior? _behavior;
  BehaviorSession? _currentSession;
  BehaviorStats? _currentStats;
  List<BehaviorEvent> _events = [];
  List<BehaviorEvent> _sessionEvents =
      []; // Events collected during current session
  bool _isInitialized = false;
  bool _isSessionActive = false;
  bool _sessionAutoEnded = false; // Track if session was auto-ended
  BehaviorSessionSummary? _autoEndedSummary; // Store summary if auto-ended
  List<BehaviorEvent> _autoEndedEvents = []; // Store events if auto-ended
  Timer? _backgroundTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSDK();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App went to background
      _onAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      // App returned to foreground
      _onAppForegrounded();
    }
  }

  void _onAppBackgrounded() {
    // End any active typing sessions when app goes to background
    BehaviorTextField.endAllTypingSessions();

    if (!_isSessionActive || _currentSession == null) return;

    print(
        'App went to background. Starting ${_backgroundSessionTimeoutMinutes} minute timer...');

    // Cancel any existing timer
    _backgroundTimer?.cancel();

    // Start timer to auto-end session after 1 minute
    _backgroundTimer = Timer(
      const Duration(minutes: _backgroundSessionTimeoutMinutes),
      () {
        if (_isSessionActive && _currentSession != null) {
          print('Background timeout reached. Auto-ending session...');
          _endSession(autoEnded: true);
        }
      },
    );
  }

  void _onAppForegrounded() {
    // Cancel the timer if app returned before timeout
    _backgroundTimer?.cancel();

    // If session was auto-ended while in background, show results
    if (_sessionAutoEnded && _autoEndedSummary != null && mounted) {
      print(
          'App returned to foreground. Session was auto-ended. Showing results...');

      // Store values in local variables to avoid null issues in callback
      final summary = _autoEndedSummary!;
      final events = List<BehaviorEvent>.from(_autoEndedEvents);

      // Reset auto-ended flags immediately
      _sessionAutoEnded = false;
      _autoEndedSummary = null;
      _autoEndedEvents = [];

      // Delay slightly to ensure widget is fully mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SessionResultsScreen(
                summary: summary,
                events: events,
                behavior: _behavior,
              ),
            ),
          );
        }
      });
    }
  }

  Future<void> _initializeSDK() async {
    try {
      final behavior = await SynheartBehavior.initialize(
        config: const BehaviorConfig(
          enableInputSignals: true,
          enableAttentionSignals: true,
          enableMotionLite: true, // Enable motion data collection for ML
        ),
      );

      // Listen to raw events
      behavior.onEvent.listen((event) {
        setState(() {
          _events.insert(0, event);
          // Keep only recent events within retention period
          final now = DateTime.now().millisecondsSinceEpoch;
          final cutoffTime = now - (_eventRetentionMinutes * 60 * 1000);
          _events = _events
              .where((e) {
                try {
                  final eventTime =
                      DateTime.parse(e.timestamp).millisecondsSinceEpoch;
                  return eventTime >= cutoffTime;
                } catch (e) {
                  return false; // Remove events with invalid timestamps
                }
              })
              .take(_maxEventsToKeep)
              .toList();

          // Store events for current session (if session is active)
          if (_isSessionActive && _currentSession != null) {
            if (event.sessionId == _currentSession!.sessionId) {
              _sessionEvents.add(event);
            }
          }
        });
      });

      // Check and request notification permission
      await _checkAndRequestNotificationPermission(behavior);

      // Auto-start a session for testing
      final session = await behavior.startSession();

      setState(() {
        _behavior = behavior;
        _currentSession = session;
        _isInitialized = true;
        _isSessionActive = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize SDK: $e')),
        );
      }
    }
  }

  Future<void> _startSession() async {
    if (_behavior == null) return;

    try {
      final session = await _behavior!.startSession();
      setState(() {
        _currentSession = session;
        _isSessionActive = true;
        _sessionEvents = []; // Clear previous session events
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start session: $e')),
        );
      }
    }
  }

  Future<void> _endSession({bool autoEnded = false}) async {
    print('_endSession called (autoEnded: $autoEnded)');
    print('_currentSession: $_currentSession');
    print('_isSessionActive: $_isSessionActive');

    // End any active typing sessions (keyboard might still be open)
    BehaviorTextField.endAllTypingSessions();

    if (_currentSession == null) {
      print('ERROR: _currentSession is null!');
      if (mounted && !autoEnded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active session to end')),
        );
      }
      return;
    }

    // Cancel background timer if it exists
    _backgroundTimer?.cancel();
    _backgroundTimer = null;

    try {
      print('Calling _currentSession!.end()...');
      print('Session ID being ended: ${_currentSession!.sessionId}');
      final summary = await _currentSession!.end().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Session end timed out after 15 seconds');
        },
      );
      print('Session ended successfully. Summary: ${summary.sessionId}');
      final sessionEvents = List<BehaviorEvent>.from(_sessionEvents);
      print('Session events count: ${sessionEvents.length}');

      setState(() {
        _currentSession = null;
        _isSessionActive = false;
      });

      if (autoEnded) {
        // Store summary and events to show when app returns to foreground
        _sessionAutoEnded = true;
        _autoEndedSummary = summary;
        _autoEndedEvents = sessionEvents;
        print(
            'Session auto-ended. Will show results when app returns to foreground.');
      } else if (mounted) {
        print('Navigating to SessionResultsScreen...');
        // Navigate to session results screen immediately
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SessionResultsScreen(
              summary: summary,
              events: sessionEvents,
              behavior: _behavior,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('ERROR ending session: $e');
      print('Stack trace: $stackTrace');
      if (mounted && !autoEnded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to end session: $e')),
        );
      }
    }
  }

  Future<void> _refreshStats() async {
    if (_behavior == null) return;

    try {
      final stats = await _behavior!.getCurrentStats();
      setState(() {
        _currentStats = stats;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get stats: $e')),
        );
      }
    }
  }

  Future<void> _checkAndRequestNotificationPermission(
      [SynheartBehavior? behavior]) async {
    final sdk = behavior ?? _behavior;
    if (sdk == null) return;

    try {
      final hasPermission = await sdk.checkNotificationPermission();
      if (!hasPermission) {
        if (mounted) {
          final shouldRequest = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Notification Permission'),
              content: const Text(
                'To track notification events, please enable notification access.\n\n'
                'On Android: You will be taken to system settings to enable notification access.\n'
                'On iOS: A permission dialog will appear.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          );

          if (shouldRequest == true) {
            await sdk.requestNotificationPermission();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please enable notification access in settings if prompted.',
                  ),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to check notification permission: $e')),
        );
      }
    }
  }

  Future<void> _checkAndRequestCallPermission(
      [SynheartBehavior? behavior]) async {
    final sdk = behavior ?? _behavior;
    if (sdk == null) return;

    try {
      final hasPermission = await sdk.checkCallPermission();
      if (!hasPermission) {
        if (mounted) {
          final shouldRequest = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Call Permission'),
              content: const Text(
                'To track call events, please enable phone state access.\n\n'
                'On Android: A permission dialog will appear.\n'
                'On iOS: Call monitoring works automatically.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          );

          if (shouldRequest == true) {
            await sdk.requestCallPermission();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please grant phone state permission if prompted.',
                  ),
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call permission already granted.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check call permission: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundTimer?.cancel();
    _behavior?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = BehaviorGestureDetector(
      behavior: _behavior,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('Synheart Behavior Demo'),
        ),
        body: GestureDetector(
          // Dismiss keyboard when tapping outside text fields
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SDK Status',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _isInitialized ? Icons.check_circle : Icons.error,
                              color: _isInitialized ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isInitialized
                                  ? 'Initialized'
                                  : 'Not Initialized',
                            ),
                          ],
                        ),
                        if (_isSessionActive) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.play_circle,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                  'Session Active: ${_currentSession?.sessionId}'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Controls
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isInitialized && !_isSessionActive
                            ? () {
                                print('Start Session button clicked!');
                                _startSession();
                              }
                            : null,
                        child: const Text('Start Session'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (context) => ElevatedButton(
                          onPressed: _isInitialized && _isSessionActive
                              ? () {
                                  print('=== END SESSION BUTTON CLICKED ===');
                                  print('_isInitialized: $_isInitialized');
                                  print('_isSessionActive: $_isSessionActive');
                                  print('_currentSession: $_currentSession');
                                  print(
                                      '_currentSession?.sessionId: ${_currentSession?.sessionId}');
                                  _endSession();
                                }
                              : () {
                                  print(
                                      '=== END SESSION BUTTON CLICKED (DISABLED) ===');
                                  print('_isInitialized: $_isInitialized');
                                  print('_isSessionActive: $_isSessionActive');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Button disabled: initialized=$_isInitialized, active=$_isSessionActive',
                                      ),
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isInitialized && _isSessionActive
                                ? Colors.red
                                : Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            _isInitialized && _isSessionActive
                                ? 'End Session'
                                : 'End Session (Disabled)',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                ElevatedButton(
                  onPressed: _isInitialized ? _refreshStats : null,
                  child: const Text('Refresh Stats'),
                ),

                const SizedBox(height: 8),

                ElevatedButton(
                  onPressed: _isInitialized && _behavior != null
                      ? () => _checkAndRequestNotificationPermission(_behavior!)
                      : null,
                  child: const Text('Request Notification Permission'),
                ),

                const SizedBox(height: 8),

                ElevatedButton(
                  onPressed: _isInitialized && _behavior != null
                      ? () => _checkAndRequestCallPermission(_behavior!)
                      : null,
                  child: const Text('Request Call Permission'),
                ),

                const SizedBox(height: 16),
                if (!_isSessionActive) ...[
                  // Stats Card
                  if (_currentStats != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Stats',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            // _buildStatRow('Typing Cadence',
                            //     _currentStats!.typingCadence?.toStringAsFixed(2)),
                            _buildStatRow(
                                'Scroll Velocity',
                                _currentStats!.scrollVelocity
                                    ?.toStringAsFixed(2)),
                            _buildStatRow('App Switches/min',
                                _currentStats!.appSwitchesPerMinute.toString()),
                            _buildStatRow(
                                'Stability Index',
                                _currentStats!.stabilityIndex
                                    ?.toStringAsFixed(2)),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                ],

                // Typing Test Field
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Typing Test',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        BehaviorTextField(
                          decoration: const InputDecoration(
                            hintText: 'Type here to test typing events...',
                            border: OutlineInputBorder(),
                            labelText: 'Text Input',
                          ),
                          maxLines: 3,
                          onTypingEvent: (event) async {
                            // Send typing event to SDK
                            if (_behavior != null) {
                              await _behavior!.sendEvent(event);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Typing events will appear in the event stream above',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Interactive Test Area - Always visible, especially during session
                const SizedBox(height: 16),
                // Test list - removed for now to avoid blocking interactions
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 10,
                  itemBuilder: (context, index) {
                    return Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text('Item $index')));
                  },
                ),
                const SizedBox(height: 100),
                const Text('Scroll down to see more content'),
              ],
            ),
          ),
        ),
      ),
    );

    // BehaviorGestureDetector already wraps the Scaffold above
    return content;
  }

  Widget _buildStatRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value ?? 'N/A',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // Color _getEventTypeColor(BehaviorEventType eventType) {
  //   switch (eventType) {
  //     case BehaviorEventType.scroll:
  //       return Colors.blue;
  //     case BehaviorEventType.tap:
  //       return Colors.green;
  //     case BehaviorEventType.swipe:
  //       return Colors.orange;
  //     case BehaviorEventType.call:
  //       return Colors.red;
  //     case BehaviorEventType.notification:
  //       return Colors.purple;
  //   }
  // }
}

/// Screen to display session results with events timeline and behavior metrics
class SessionResultsScreen extends StatefulWidget {
  final BehaviorSessionSummary summary;
  final List<BehaviorEvent> events;
  final SynheartBehavior? behavior;

  const SessionResultsScreen({
    super.key,
    required this.summary,
    required this.events,
    this.behavior,
  });

  @override
  State<SessionResultsScreen> createState() => _SessionResultsScreenState();
}

class _SessionResultsScreenState extends State<SessionResultsScreen> {
  DateTime? _selectedStartTime;
  DateTime? _selectedEndTime;

  @override
  void initState() {
    super.initState();
    // Initialize time range to session start/end
    final sessionStartUtc = DateTime.parse(widget.summary.startAt);
    final sessionEndUtc = DateTime.parse(widget.summary.endAt);
    _selectedStartTime = sessionStartUtc;
    _selectedEndTime = sessionEndUtc;
  }

  @override
  Widget build(BuildContext context) {
    // Sort events by timestamp (oldest first)
    final sortedEvents = List<BehaviorEvent>.from(widget.events)
      ..sort((a, b) {
        try {
          final timeA = DateTime.parse(a.timestamp);
          final timeB = DateTime.parse(b.timestamp);
          return timeA.compareTo(timeB);
        } catch (e) {
          return 0;
        }
      });

    // Calculate relative time from session start
    final sessionStart = DateTime.parse(widget.summary.startAt);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Results'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Information',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Session ID', widget.summary.sessionId),
                    _buildInfoRow(
                        'Start Time', _formatDateTime(widget.summary.startAt)),
                    _buildInfoRow(
                        'End Time', _formatDateTime(widget.summary.endAt)),
                    _buildInfoRow(
                        'Duration', _formatMs(widget.summary.durationMs)),
                    _buildInfoRow('Micro Session',
                        widget.summary.microSession ? 'Yes' : 'No'),
                    _buildInfoRow('OS', widget.summary.os),
                    if (widget.summary.appId != null)
                      _buildInfoRow('App ID', widget.summary.appId!),
                    if (widget.summary.appName != null)
                      _buildInfoRow('App Name', widget.summary.appName!),
                    _buildInfoRow('Session Spacing',
                        _formatMs(widget.summary.sessionSpacing)),
                    _buildInfoRow('Total Events', '${sortedEvents.length}'),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    // Time Range Picker Section
                    Text(
                      'Time Range Selection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    // Start Time Picker
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickStartTime(context),
                            icon: const Icon(Icons.access_time),
                            label: Text(
                              _selectedStartTime != null
                                  ? 'Start: ${_formatDateTimeWithSeconds(_selectedStartTime!.toLocal())}'
                                  : 'Pick Start Time',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // End Time Picker
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickEndTime(context),
                            icon: const Icon(Icons.access_time),
                            label: Text(
                              _selectedEndTime != null
                                  ? 'End: ${_formatDateTimeWithSeconds(_selectedEndTime!.toLocal())}'
                                  : 'Pick End Time',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Calculate Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_selectedStartTime != null &&
                                _selectedEndTime != null)
                            ? () => _calculateAndLog()
                            : null,
                        icon: const Icon(Icons.calculate),
                        label: const Text('Calculate Metrics'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Motion Data Debug Card (temporary for debugging)
            Card(
              color: Colors.orange.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motion Data Debug',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.orange[900],
                          ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('Motion Data Available',
                        widget.summary.motionData != null ? 'Yes' : 'No'),
                    _buildInfoRow('Motion Data Count',
                        '${widget.summary.motionData?.length ?? 0} windows'),
                    _buildInfoRow('Motion State Available',
                        widget.summary.motionState != null ? 'Yes' : 'No'),
                    if (widget.summary.motionData != null &&
                        widget.summary.motionData!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'First window sample (first 5 features):',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.summary.motionData!.first.features.entries
                            .take(5)
                            .map((e) =>
                                '${e.key}: ${e.value.toStringAsFixed(4)}')
                            .join('\n'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Motion State Card
            if (widget.summary.motionState != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Motion State',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Major State',
                          widget.summary.motionState!.majorState),
                      _buildInfoRow('Major State %',
                          '${(widget.summary.motionState!.majorStatePct * 100).toStringAsFixed(1)}%'),
                      _buildInfoRow(
                          'ML Model', widget.summary.motionState!.mlModel),
                      _buildInfoRow(
                          'Confidence',
                          widget.summary.motionState!.confidence
                              .toStringAsFixed(2)),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'State Array (${widget.summary.motionState!.state.length} windows):',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      // Display as JSON-like array format
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          '[${widget.summary.motionState!.state.map((s) => '"$s"').join(', ')}]',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Also show as readable list
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: widget.summary.motionState!.state
                            .asMap()
                            .entries
                            .map((entry) {
                          return Chip(
                            label: Text(
                              '${entry.key + 1}: ${entry.value}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Motion Data Card (ML Features)
            if (widget.summary.motionData != null &&
                widget.summary.motionData!.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Motion Data (ML Features)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        'Data Points',
                        '${widget.summary.motionData!.length} time windows',
                      ),
                      _buildInfoRow(
                        'Time Window',
                        '5 seconds per window',
                      ),
                      _buildInfoRow(
                        'Features per Window',
                        '561 ML features',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sample Features (First window):',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...widget.summary.motionData!.take(1).map((dataPoint) {
                        return ExpansionTile(
                          title: Text(
                            'Window: ${dataPoint.timestamp}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Features: ${dataPoint.features.length}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  // Show first 20 features as examples
                                  ...dataPoint.features.entries
                                      .take(20)
                                      .map((entry) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 4.0),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              entry.key,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: 'monospace'),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text(
                                              entry.value.toStringAsFixed(4),
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: 'monospace'),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  if (dataPoint.features.length > 20)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        '... and ${dataPoint.features.length - 20} more features',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                      if (widget.summary.motionData!.length > 1)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            '... and ${widget.summary.motionData!.length - 1} more windows',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Device Context Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Context',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        'Avg Screen Brightness',
                        widget.summary.deviceContext.avgScreenBrightness
                            .toStringAsFixed(3)),
                    _buildInfoRow('Start Orientation',
                        widget.summary.deviceContext.startOrientation),
                    _buildInfoRow('Orientation Changes',
                        '${widget.summary.deviceContext.orientationChanges}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Activity Summary Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activity Summary',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Total Events',
                        '${widget.summary.activitySummary.totalEvents}'),
                    _buildInfoRow('App Switch Count',
                        '${widget.summary.activitySummary.appSwitchCount}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Behavior Metrics Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Behavior Metrics',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        'Interaction Intensity',
                        widget.summary.behavioralMetrics.interactionIntensity
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Task Switch Rate',
                        widget.summary.behavioralMetrics.taskSwitchRate
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Task Switch Cost',
                        _formatMs(
                            widget.summary.behavioralMetrics.taskSwitchCost)),
                    _buildInfoRow(
                        'Idle Time Ratio',
                        widget.summary.behavioralMetrics.idleTimeRatio
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Active Time Ratio',
                        widget.summary.behavioralMetrics.activeTimeRatio
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Notification Load',
                        widget.summary.behavioralMetrics.notificationLoad
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Burstiness',
                        widget.summary.behavioralMetrics.burstiness
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Distraction Score',
                        widget.summary.behavioralMetrics
                            .behavioralDistractionScore
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Focus Hint',
                        widget.summary.behavioralMetrics.focusHint
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Fragmented Idle Ratio',
                        widget.summary.behavioralMetrics.fragmentedIdleRatio
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Scroll Jitter Rate',
                        widget.summary.behavioralMetrics.scrollJitterRate
                            .toStringAsFixed(3)),
                    _buildInfoRow('Deep Focus Blocks',
                        '${widget.summary.behavioralMetrics.deepFocusBlocks.length}'),
                    if (widget.summary.behavioralMetrics.deepFocusBlocks
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Deep Focus Block Details:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...widget.summary.behavioralMetrics.deepFocusBlocks
                          .asMap()
                          .entries
                          .map((entry) {
                        final index = entry.key;
                        final block = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Text(
                            'Block ${index + 1}: ${_formatDateTime(block.startAt)} - ${_formatDateTime(block.endAt)} (${_formatMs(block.durationMs)})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Notification Summary Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification Summary',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Notification Count',
                        '${widget.summary.notificationSummary.notificationCount}'),
                    _buildInfoRow('Notifications Ignored',
                        '${widget.summary.notificationSummary.notificationIgnored}'),
                    _buildInfoRow(
                        'Ignore Rate',
                        widget
                            .summary.notificationSummary.notificationIgnoreRate
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Clustering Index',
                        widget.summary.notificationSummary
                            .notificationClusteringIndex
                            .toStringAsFixed(3)),
                    _buildInfoRow('Call Count',
                        '${widget.summary.notificationSummary.callCount}'),
                    _buildInfoRow('Calls Ignored',
                        '${widget.summary.notificationSummary.callIgnored}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Typing Session Summary Card
            if (widget.summary.typingSessionSummary != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.keyboard, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text(
                            'Typing Session Summary',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Typing Sessions',
                          '${widget.summary.typingSessionSummary!.typingSessionCount}'),
                      _buildInfoRow(
                          'Avg Keystrokes/Session',
                          widget.summary.typingSessionSummary!
                              .averageKeystrokesPerSession
                              .toStringAsFixed(1)),
                      _buildInfoRow(
                          'Avg Session Duration',
                          _formatMs((widget.summary.typingSessionSummary!
                                      .averageTypingSessionDuration *
                                  1000)
                              .round())),
                      _buildInfoRow('Avg Typing Speed',
                          '${widget.summary.typingSessionSummary!.averageTypingSpeed.toStringAsFixed(2)} taps/s'),
                      _buildInfoRow(
                          'Avg Typing Gap',
                          _formatMs(widget
                              .summary.typingSessionSummary!.averageTypingGap
                              .round())),
                      _buildInfoRow(
                          'Average Inter-tap Interval',
                          _formatMs(widget.summary.typingSessionSummary!
                              .averageInterTapInterval
                              .round())),
                      _buildInfoRow(
                          'Cadence Stability',
                          widget.summary.typingSessionSummary!
                              .typingCadenceStability
                              .toStringAsFixed(3)),
                      _buildInfoRow(
                          'Burstiness',
                          widget
                              .summary.typingSessionSummary!.burstinessOfTyping
                              .toStringAsFixed(3)),
                      _buildInfoRow(
                          'Total Typing Duration',
                          _formatMs(widget.summary.typingSessionSummary!
                                  .totalTypingDuration *
                              1000)),
                      _buildInfoRow(
                          'Active Typing Ratio',
                          widget.summary.typingSessionSummary!.activeTypingRatio
                              .toStringAsFixed(3)),
                      _buildInfoRow(
                          'Typing Contribution to Intensity',
                          widget.summary.typingSessionSummary!
                              .typingContributionToInteractionIntensity
                              .toStringAsFixed(3)),
                      _buildInfoRow('Deep Typing Blocks',
                          '${widget.summary.typingSessionSummary!.deepTypingBlocks}'),
                      _buildInfoRow(
                          'Typing Fragmentation',
                          widget
                              .summary.typingSessionSummary!.typingFragmentation
                              .toStringAsFixed(3)),
                      if (widget.summary.typingSessionSummary!
                          .individualTypingSessions.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Individual Typing Sessions (${widget.summary.typingSessionSummary!.individualTypingSessions.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...widget.summary.typingSessionSummary!
                            .individualTypingSessions
                            .asMap()
                            .entries
                            .map((entry) {
                          final index = entry.key;
                          final session = entry.value;
                          return ExpansionTile(
                            title: Text(
                              'Session ${index + 1}${session.deepTyping ? " (Deep Typing)" : ""}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              '${_formatMs(session.duration * 1000)} • ${session.typingTapCount} keystrokes',
                              style: const TextStyle(fontSize: 12),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow('Start Time',
                                        _formatDateTime(session.startAt)),
                                    _buildInfoRow('End Time',
                                        _formatDateTime(session.endAt)),
                                    _buildInfoRow('Duration',
                                        _formatMs(session.duration * 1000)),
                                    _buildInfoRow('Deep Typing',
                                        session.deepTyping ? 'Yes' : 'No'),
                                    _buildInfoRow('Keystrokes',
                                        '${session.typingTapCount}'),
                                    _buildInfoRow('Typing Speed',
                                        '${session.typingSpeed.toStringAsFixed(2)} taps/s'),
                                    _buildInfoRow(
                                        'Mean Inter-Tap Interval',
                                        _formatMs(session.meanInterTapIntervalMs
                                            .round())),
                                    _buildInfoRow(
                                        'Cadence Variability',
                                        _formatMs(session
                                            .typingCadenceVariability
                                            .round())),
                                    _buildInfoRow(
                                        'Cadence Stability',
                                        session.typingCadenceStability
                                            .toStringAsFixed(3)),
                                    _buildInfoRow('Gap Count',
                                        '${session.typingGapCount}'),
                                    _buildInfoRow(
                                        'Gap Ratio',
                                        session.typingGapRatio
                                            .toStringAsFixed(3)),
                                    _buildInfoRow(
                                        'Burstiness',
                                        session.typingBurstiness
                                            .toStringAsFixed(3)),
                                    _buildInfoRow(
                                        'Activity Ratio',
                                        session.typingActivityRatio
                                            .toStringAsFixed(3)),
                                    _buildInfoRow(
                                        'Interaction Intensity',
                                        session.typingInteractionIntensity
                                            .toStringAsFixed(3)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // System State Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System State',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        'Internet',
                        widget.summary.systemState.internetState
                            ? 'Connected'
                            : 'Disconnected'),
                    _buildInfoRow('Do Not Disturb',
                        widget.summary.systemState.doNotDisturb ? 'On' : 'Off'),
                    _buildInfoRow('Charging',
                        widget.summary.systemState.charging ? 'Yes' : 'No'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Events Timeline
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Events Timeline (${sortedEvents.length} events)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (sortedEvents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child:
                              Text('No events collected during this session.'),
                        ),
                      )
                    else
                      ...sortedEvents.asMap().entries.map((entry) {
                        final index = entry.key;
                        final event = entry.value;
                        final eventTime = DateTime.parse(event.timestamp);
                        final relativeTime = eventTime.difference(sessionStart);
                        final relativeTimeMs = relativeTime.inMilliseconds;

                        return _buildEventTimelineItem(
                          context,
                          event,
                          index + 1,
                          relativeTimeMs,
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartTime(BuildContext context) async {
    final sessionStartUtc = DateTime.parse(widget.summary.startAt);
    final sessionEndUtc = DateTime.parse(widget.summary.endAt);
    final sessionStartLocal = sessionStartUtc.toLocal();
    final sessionEndLocal = sessionEndUtc.toLocal();

    final selected = await _showDateTimePicker(
      context: context,
      title: 'Select Start Time',
      initialDateTime: _selectedStartTime?.toLocal() ?? sessionStartLocal,
      firstDate: sessionStartLocal.subtract(const Duration(days: 1)),
      lastDate: sessionEndLocal.add(const Duration(days: 1)),
    );

    if (selected != null) {
      setState(() {
        _selectedStartTime = selected.toUtc();
      });
    }
  }

  Future<void> _pickEndTime(BuildContext context) async {
    final sessionStartUtc = DateTime.parse(widget.summary.startAt);
    final sessionEndUtc = DateTime.parse(widget.summary.endAt);
    final sessionStartLocal = sessionStartUtc.toLocal();
    final sessionEndLocal = sessionEndUtc.toLocal();

    final selected = await _showDateTimePicker(
      context: context,
      title: 'Select End Time',
      initialDateTime: _selectedEndTime?.toLocal() ??
          (_selectedStartTime?.toLocal() ?? sessionStartLocal),
      firstDate: _selectedStartTime?.toLocal() ?? sessionStartLocal,
      lastDate: sessionEndLocal.add(const Duration(days: 1)),
    );

    if (selected != null) {
      setState(() {
        _selectedEndTime = selected.toUtc();
      });
    }
  }

  Future<void> _calculateAndLog() async {
    if (_selectedStartTime == null || _selectedEndTime == null) {
      print('ERROR: Start time or end time is null');
      return;
    }

    if (widget.behavior == null) {
      print('ERROR: Behavior SDK is not available');
      return;
    }

    // Validate that start time is before end time
    if (_selectedStartTime!.isAfter(_selectedEndTime!)) {
      print('');
      print('========================================');
      print('ERROR: INVALID TIME RANGE');
      print('========================================');
      print('Start time must be before end time!');
      print('');
      print('Selected Start (UTC): ${_selectedStartTime!.toIso8601String()}');
      print('Selected End (UTC): ${_selectedEndTime!.toIso8601String()}');
      print(
          'Duration: ${_formatMs(_selectedEndTime!.difference(_selectedStartTime!).inMilliseconds)}');
      print('========================================');
      print('');
      return;
    }

    // Validate time range is within session duration (with 1 second tolerance)
    final sessionStartUtc = DateTime.parse(widget.summary.startAt);
    final sessionEndUtc = DateTime.parse(widget.summary.endAt);
    final sessionStartMs = sessionStartUtc.millisecondsSinceEpoch;
    final sessionEndMs = sessionEndUtc.millisecondsSinceEpoch;
    final selectedStartMs = _selectedStartTime!.millisecondsSinceEpoch;
    final selectedEndMs = _selectedEndTime!.millisecondsSinceEpoch;
    const toleranceMs = 1000; // 1 second tolerance

    if (selectedStartMs < (sessionStartMs - toleranceMs) ||
        selectedEndMs > (sessionEndMs + toleranceMs)) {
      print('');
      print('========================================');
      print('ERROR: TIME RANGE OUT OF BOUNDS');
      print('========================================');
      print('Session Start (UTC): ${sessionStartUtc.toIso8601String()}');
      print('Session End (UTC): ${sessionEndUtc.toIso8601String()}');
      print(
          'Session Duration: ${_formatMs((sessionEndMs - sessionStartMs).toInt())}');
      print('');
      print('Selected Start (UTC): ${_selectedStartTime!.toIso8601String()}');
      print('Selected End (UTC): ${_selectedEndTime!.toIso8601String()}');
      print(
          'Selected Duration: ${_formatMs((selectedEndMs - selectedStartMs).toInt())}');
      print('');
      if (selectedStartMs < (sessionStartMs - toleranceMs)) {
        final diffMs = sessionStartMs - selectedStartMs;
        print(
            'ERROR: Selected start time is ${_formatMs(diffMs.toInt())} before session start time');
      }
      if (selectedEndMs > (sessionEndMs + toleranceMs)) {
        final diffMs = selectedEndMs - sessionEndMs;
        print(
            'ERROR: Selected end time is ${_formatMs(diffMs.toInt())} after session end time');
      }
      print('========================================');
      print('');
      return;
    }

    final startTimestampSeconds =
        _selectedStartTime!.millisecondsSinceEpoch ~/ 1000;
    final endTimestampSeconds =
        _selectedEndTime!.millisecondsSinceEpoch ~/ 1000;

    print('========================================');
    print('CALCULATE METRICS FOR TIME RANGE');
    print('========================================');
    print('Session ID: ${widget.summary.sessionId}');
    print('Start Time (UTC): ${_selectedStartTime!.toIso8601String()}');
    print('End Time (UTC): ${_selectedEndTime!.toIso8601String()}');
    print(
        'Start Time (Local): ${_selectedStartTime!.toLocal().toIso8601String()}');
    print('End Time (Local): ${_selectedEndTime!.toLocal().toIso8601String()}');
    print('Start Timestamp (seconds): $startTimestampSeconds');
    print('End Timestamp (seconds): $endTimestampSeconds');
    print('Duration: ${endTimestampSeconds - startTimestampSeconds} seconds');
    print(
        'Duration: ${_formatMs((endTimestampSeconds - startTimestampSeconds) * 1000)}');
    print('========================================');
    print('');

    try {
      print('Calling calculateMetricsForTimeRange...');
      final result = await widget.behavior!.calculateMetricsForTimeRange(
        startTimestampSeconds: startTimestampSeconds,
        endTimestampSeconds: endTimestampSeconds,
        sessionId: widget.summary.sessionId,
      );

      // Convert to Map<String, dynamic> safely
      final metrics = Map<String, dynamic>.from(result);

      print('');
      print('========================================');
      print('SESSION BEHAVIOR METRICS');
      print('========================================');
      print('');
      print('"session behavior" : {');
      print('    "session_id": "${widget.summary.sessionId}",');
      print('    "start_at": "${_selectedStartTime!.toIso8601String()}",');
      print('    "end_at": "${_selectedEndTime!.toIso8601String()}",');
      print('    "micro_session": ${widget.summary.microSession},');
      print('    "OS": "${widget.summary.os}",');
      if (widget.summary.appId != null) {
        print('    "app_id": "${widget.summary.appId}",');
      }
      print('    "session_spacing": ${widget.summary.sessionSpacing},');

      // Motion State
      if (metrics['motion_state'] != null) {
        final motionState =
            Map<String, dynamic>.from(metrics['motion_state'] as Map);
        print('    "motion_state": {');
        if (motionState['major_state'] != null) {
          print('        "state": "${motionState['major_state']}",');
        }
        if (motionState['ml_model'] != null) {
          print('        "ml_model": "${motionState['ml_model']}",');
        }
        if (motionState['confidence'] != null) {
          print('        "confidence": ${motionState['confidence']}');
        }
        print('    },');
      }

      // Device Context
      if (metrics['device_context'] != null) {
        final deviceContext =
            Map<String, dynamic>.from(metrics['device_context'] as Map);
        print('    "device_context": {');
        print(
            '      "avg_screen_brightness": ${deviceContext['avg_screen_brightness'] ?? 0},');
        print(
            '      "start_orientation": "${deviceContext['start_orientation'] ?? 'N/A'}",');
        print(
            '      "orientation_changes": ${deviceContext['orientation_changes'] ?? 0}');
        print('    },');
      }

      // Activity Summary
      if (metrics['activity_summary'] != null) {
        final activitySummary =
            Map<String, dynamic>.from(metrics['activity_summary'] as Map);
        print('  "activity_summary": {');
        print('    "total_events": ${activitySummary['total_events'] ?? 0},');
        print(
            '    "app_switch_count": ${activitySummary['app_switch_count'] ?? 0}');
        print('  },');
      }

      // Behavioral Metrics
      if (metrics['behavioral_metrics'] != null) {
        final behavioralMetrics =
            Map<String, dynamic>.from(metrics['behavioral_metrics'] as Map);
        print('  "behavioral_metrics": {');
        print(
            '      "interaction_intensity": ${behavioralMetrics['interaction_intensity'] ?? 0},');
        print(
            '      "task_switch_rate": ${behavioralMetrics['task_switch_rate'] ?? 0},');
        print(
            '      "task_switch_cost": ${behavioralMetrics['task_switch_cost'] ?? 0},');
        print(
            '      "idle_time_ratio": ${behavioralMetrics['idle_time_ratio'] ?? 0},');
        print(
            '      "active_time_ratio": ${behavioralMetrics['active_time_ratio'] ?? 0},');
        print(
            '      "notification_load": ${behavioralMetrics['notification_load'] ?? 0},');
        print('      "burstiness": ${behavioralMetrics['burstiness'] ?? 0},');
        print(
            '      "behavioral_distraction_score": ${behavioralMetrics['behavioral_distraction_score'] ?? 0},');

        if (behavioralMetrics['deep_focus_blocks'] != null) {
          final deepFocusBlocks =
              behavioralMetrics['deep_focus_blocks'] as List;
          print('      "deep_focus_blocks": [');
          for (var i = 0; i < deepFocusBlocks.length; i++) {
            final block = Map<String, dynamic>.from(deepFocusBlocks[i] as Map);
            print('        {');
            print('          "start_at": "${block['start_at'] ?? ''}",');
            print('          "end_at": "${block['end_at'] ?? ''}",');
            print('          "duration_ms": ${block['duration_ms'] ?? 0}');
            if (i < deepFocusBlocks.length - 1) {
              print('        },');
            } else {
              print('        }');
            }
          }
          print('      ]');
        }
        print('  },');
      }

      // Notification Summary
      if (metrics['notification_summary'] != null) {
        final notificationSummary =
            Map<String, dynamic>.from(metrics['notification_summary'] as Map);
        print('  "notification_summary": {');
        print(
            '    "notification_count": ${notificationSummary['notification_count'] ?? 0},');
        print(
            '    "notification_ignored": ${notificationSummary['notification_ignored'] ?? 0},');
        print(
            '    "notification_ignore_rate": ${notificationSummary['notification_ignore_rate'] ?? 0},');
        print(
            '    "notification_clustering_index": ${notificationSummary['notification_clustering_index'] ?? 0},');
        print('    "call_count": ${notificationSummary['call_count'] ?? 0},');
        print(
            '    "call_ignored": ${notificationSummary['call_ignored'] ?? 0}');
        print('  },');
      }

      // System State
      if (metrics['system_state'] != null) {
        final systemState =
            Map<String, dynamic>.from(metrics['system_state'] as Map);
        print('  "system_state": {');
        print(
            '    "internet_state": ${systemState['internet_state'] ?? false},');
        print(
            '    "do_not_disturb": ${systemState['do_not_disturb'] ?? false},');
        print('    "charging": ${systemState['charging'] ?? false}');
        print('  }');
      }

      print('}');
      print('');
      print('========================================');
    } catch (e, stackTrace) {
      print('');
      print('ERROR calculating metrics: $e');
      print('Stack trace: $stackTrace');
      print('');
    }
  }

  Future<DateTime?> _showDateTimePicker({
    required BuildContext context,
    required String title,
    required DateTime initialDateTime,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime selectedDate = initialDateTime;
    int hour = initialDateTime.hour;
    int minute = initialDateTime.minute;
    int second = initialDateTime.second;

    return showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Date picker section
                    const Text(
                      'Date',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: firstDate,
                          lastDate: lastDate,
                        );
                        if (pickedDate != null) {
                          setState(() {
                            selectedDate = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              hour,
                              minute,
                              second,
                            );
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const Icon(Icons.calendar_today),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Time picker section
                    const Text(
                      'Time (HH:MM:SS)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Hour
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_up),
                              onPressed: () {
                                setState(() {
                                  hour = (hour + 1) % 24;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                            Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                hour.toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: () {
                                setState(() {
                                  hour = (hour - 1 + 24) % 24;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                        const Text(':', style: TextStyle(fontSize: 24)),
                        // Minute
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_up),
                              onPressed: () {
                                setState(() {
                                  minute = (minute + 1) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                            Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                minute.toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: () {
                                setState(() {
                                  minute = (minute - 1 + 60) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                        const Text(':', style: TextStyle(fontSize: 24)),
                        // Second
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_up),
                              onPressed: () {
                                setState(() {
                                  second = (second + 1) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                            Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                second.toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: () {
                                setState(() {
                                  second = (second - 1 + 60) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(selectedDate);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDateTimeWithSeconds(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEventTimelineItem(
    BuildContext context,
    BehaviorEvent event,
    int eventNumber,
    int relativeTimeMs,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getEventTypeColor(event.eventType),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  event.eventType.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '+${_formatMs(relativeTimeMs)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Time: ${_formatDateTime(event.timestamp)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Metrics:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          ...event.metrics.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        '${entry.key}: ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              fontFamily: 'monospace',
                            ),
                      ),
                    ),
                    Flexible(
                      flex: 2,
                      child: Text(
                        entry.value.toString(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Color _getEventTypeColor(BehaviorEventType eventType) {
    switch (eventType) {
      case BehaviorEventType.scroll:
        return Colors.blue;
      case BehaviorEventType.tap:
        return Colors.green;
      case BehaviorEventType.swipe:
        return Colors.orange;
      case BehaviorEventType.call:
        return Colors.red;
      case BehaviorEventType.notification:
        return Colors.purple;
      case BehaviorEventType.typing:
        return Colors.teal;
    }
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}:'
          '${dateTime.second.toString().padLeft(2, '0')}.'
          '${(dateTime.millisecond ~/ 100).toString()}';
    } catch (e) {
      return isoString;
    }
  }

  String _formatMs(int milliseconds) {
    if (milliseconds < 1000) {
      return '${milliseconds}ms';
    } else if (milliseconds < 60000) {
      return '${(milliseconds / 1000).toStringAsFixed(1)}s';
    } else {
      return '${(milliseconds / 60000).toStringAsFixed(1)}m';
    }
  }
}
