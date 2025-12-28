import 'dart:async';
import 'dart:convert';
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
      Duration(minutes: _backgroundSessionTimeoutMinutes),
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

      // Export 561 features as JSON for ML engineer (if motion data available)
      if (summary.motionData != null && summary.motionData!.isNotEmpty) {
        try {
          // Initialize inference to get ordered features
          final inference = MotionStateInference();
          await inference.loadModel();

          // Print header to distinguish motion data export
          print('\n');
          print(
              '═══════════════════════════════════════════════════════════════');
          print('📊 MOTION DATA EXPORT - 561 FEATURES PER WINDOW');
          print(
              '═══════════════════════════════════════════════════════════════');
          print('Total windows: ${summary.motionData!.length}');
          print('Total duration: ${summary.motionData!.length * 5} seconds');
          print('Features per window: 561 (ordered as per features.txt)');
          print(
              '═══════════════════════════════════════════════════════════════');
          print('');

          // Print each window as JSON (all 561 features per window)
          for (int i = 0; i < summary.motionData!.length; i++) {
            final windowNum = i + 1;

            // Get ordered features for this window (all 561 values)
            final orderedFeatures = await inference
                .getOrderedFeatures(summary.motionData![i].features);

            // Verify we have all 561 features
            if (orderedFeatures.length != 561) {
              print(
                  'ERROR: Window $windowNum has ${orderedFeatures.length} features, expected 561!');
              continue;
            }

            // Replace NaN and Infinity values with 0.0 before JSON encoding
            // JSON doesn't support NaN/Infinity, so we need to sanitize the data
            final sanitizedFeatures = orderedFeatures.map((value) {
              if (value.isNaN || value.isInfinite) {
                return 0.0;
              }
              return value;
            }).toList();

            // Count how many were replaced for logging
            final nanCount = orderedFeatures.where((v) => v.isNaN).length;
            final infCount = orderedFeatures.where((v) => v.isInfinite).length;
            if (nanCount > 0 || infCount > 0) {
              print(
                  '⚠️ Window $windowNum: Replaced $nanCount NaN and $infCount Infinity values with 0.0');
            }

            // Create JSON object for this window
            final windowJson = {
              'data_point_index': windowNum,
              'timestamp': summary.motionData![i].timestamp,
              'features':
                  sanitizedFeatures, // All 561 features in exact order (NaN/Inf replaced)
            };

            // Print as JSON string (compact format)
            try {
              final jsonString = json.encode(windowJson);
              print(jsonString);

              // Verify the JSON contains all features (check feature count in JSON)
              final decoded = json.decode(jsonString) as Map<String, dynamic>;
              final featuresInJson = decoded['features'] as List;
              if (featuresInJson.length != 561) {
                print(
                    'ERROR: Window $windowNum JSON contains ${featuresInJson.length} features, expected 561!');
              } else {
                print('✓ Window $windowNum: Verified 561 features in JSON');
              }
            } catch (e) {
              print('ERROR: Failed to encode Window $windowNum to JSON: $e');
            }
          }

          print('');
          print(
              '═══════════════════════════════════════════════════════════════');
          print('✅ END OF MOTION DATA EXPORT');
          print(
              '═══════════════════════════════════════════════════════════════');
          print('\n');
        } catch (e) {
          print('Error exporting features: $e');
        }
      } else {
        print('No motion data available to export');
      }

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
class SessionResultsScreen extends StatelessWidget {
  final BehaviorSessionSummary summary;
  final List<BehaviorEvent> events;

  const SessionResultsScreen({
    super.key,
    required this.summary,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    // Sort events by timestamp (oldest first)
    final sortedEvents = List<BehaviorEvent>.from(events)
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
    final sessionStart = DateTime.parse(summary.startAt);

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
                    _buildInfoRow('Session ID', summary.sessionId),
                    _buildInfoRow(
                        'Start Time', _formatDateTime(summary.startAt)),
                    _buildInfoRow('End Time', _formatDateTime(summary.endAt)),
                    _buildInfoRow('Duration', _formatMs(summary.durationMs)),
                    _buildInfoRow(
                        'Micro Session', summary.microSession ? 'Yes' : 'No'),
                    _buildInfoRow('OS', summary.os),
                    if (summary.appId != null)
                      _buildInfoRow('App ID', summary.appId!),
                    if (summary.appName != null)
                      _buildInfoRow('App Name', summary.appName!),
                    _buildInfoRow(
                        'Session Spacing', _formatMs(summary.sessionSpacing)),
                    _buildInfoRow('Total Events', '${sortedEvents.length}'),
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
                        summary.motionData != null ? 'Yes' : 'No'),
                    _buildInfoRow('Motion Data Count',
                        '${summary.motionData?.length ?? 0} windows'),
                    _buildInfoRow('Motion State Available',
                        summary.motionState != null ? 'Yes' : 'No'),
                    if (summary.motionData != null &&
                        summary.motionData!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'First window sample (first 5 features):',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary.motionData!.first.features.entries
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
            if (summary.motionState != null) ...[
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
                      _buildInfoRow(
                          'Major State', summary.motionState!.majorState),
                      _buildInfoRow('Major State %',
                          '${(summary.motionState!.majorStatePct * 100).toStringAsFixed(1)}%'),
                      _buildInfoRow('ML Model', summary.motionState!.mlModel),
                      _buildInfoRow('Confidence',
                          summary.motionState!.confidence.toStringAsFixed(2)),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'State Array (${summary.motionState!.state.length} windows):',
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
                          '[${summary.motionState!.state.map((s) => '"$s"').join(', ')}]',
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
                        children: summary.motionState!.state
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
            if (summary.motionData != null &&
                summary.motionData!.isNotEmpty) ...[
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
                        '${summary.motionData!.length} time windows',
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
                      ...summary.motionData!.take(1).map((dataPoint) {
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
                      if (summary.motionData!.length > 1)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            '... and ${summary.motionData!.length - 1} more windows',
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
                        summary.deviceContext.avgScreenBrightness
                            .toStringAsFixed(3)),
                    _buildInfoRow('Start Orientation',
                        summary.deviceContext.startOrientation),
                    _buildInfoRow('Orientation Changes',
                        '${summary.deviceContext.orientationChanges}'),
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
                        '${summary.activitySummary.totalEvents}'),
                    _buildInfoRow('App Switch Count',
                        '${summary.activitySummary.appSwitchCount}'),
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
                        summary.behavioralMetrics.interactionIntensity
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Task Switch Rate',
                        summary.behavioralMetrics.taskSwitchRate
                            .toStringAsFixed(3)),
                    _buildInfoRow('Task Switch Cost',
                        _formatMs(summary.behavioralMetrics.taskSwitchCost)),
                    _buildInfoRow(
                        'Idle Time Ratio',
                        summary.behavioralMetrics.idleTimeRatio
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Active Time Ratio',
                        summary.behavioralMetrics.activeTimeRatio
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Notification Load',
                        summary.behavioralMetrics.notificationLoad
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Burstiness',
                        summary.behavioralMetrics.burstiness
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Distraction Score',
                        summary.behavioralMetrics.behavioralDistractionScore
                            .toStringAsFixed(3)),
                    _buildInfoRow('Focus Hint',
                        summary.behavioralMetrics.focusHint.toStringAsFixed(3)),
                    _buildInfoRow(
                        'Fragmented Idle Ratio',
                        summary.behavioralMetrics.fragmentedIdleRatio
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Scroll Jitter Rate',
                        summary.behavioralMetrics.scrollJitterRate
                            .toStringAsFixed(3)),
                    _buildInfoRow('Deep Focus Blocks',
                        '${summary.behavioralMetrics.deepFocusBlocks.length}'),
                    if (summary
                        .behavioralMetrics.deepFocusBlocks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Deep Focus Block Details:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...summary.behavioralMetrics.deepFocusBlocks
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
                        '${summary.notificationSummary.notificationCount}'),
                    _buildInfoRow('Notifications Ignored',
                        '${summary.notificationSummary.notificationIgnored}'),
                    _buildInfoRow(
                        'Ignore Rate',
                        summary.notificationSummary.notificationIgnoreRate
                            .toStringAsFixed(3)),
                    _buildInfoRow(
                        'Clustering Index',
                        summary.notificationSummary.notificationClusteringIndex
                            .toStringAsFixed(3)),
                    _buildInfoRow('Call Count',
                        '${summary.notificationSummary.callCount}'),
                    _buildInfoRow('Calls Ignored',
                        '${summary.notificationSummary.callIgnored}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Typing Session Summary Card
            if (summary.typingSessionSummary != null) ...[
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
                          '${summary.typingSessionSummary!.typingSessionCount}'),
                      _buildInfoRow(
                          'Avg Keystrokes/Session',
                          summary
                              .typingSessionSummary!.averageKeystrokesPerSession
                              .toStringAsFixed(1)),
                      _buildInfoRow(
                          'Avg Session Duration',
                          _formatMs((summary.typingSessionSummary!
                                      .averageTypingSessionDuration *
                                  1000)
                              .round())),
                      _buildInfoRow('Avg Typing Speed',
                          '${summary.typingSessionSummary!.averageTypingSpeed.toStringAsFixed(2)} taps/s'),
                      _buildInfoRow(
                          'Avg Typing Gap',
                          _formatMs(summary
                              .typingSessionSummary!.averageTypingGap
                              .round())),
                      _buildInfoRow(
                          'Average Inter-tap Interval',
                          _formatMs(summary
                              .typingSessionSummary!.averageInterTapInterval
                              .round())),
                      _buildInfoRow(
                          'Cadence Stability',
                          summary.typingSessionSummary!.typingCadenceStability
                              .toStringAsFixed(3)),
                      _buildInfoRow(
                          'Burstiness',
                          summary.typingSessionSummary!.burstinessOfTyping
                              .toStringAsFixed(3)),
                      _buildInfoRow(
                          'Total Typing Duration',
                          _formatMs(summary
                                  .typingSessionSummary!.totalTypingDuration *
                              1000)),
                      _buildInfoRow(
                          'Active Typing Ratio',
                          summary.typingSessionSummary!.activeTypingRatio
                              .toStringAsFixed(3)),
                      _buildInfoRow(
                          'Typing Contribution to Intensity',
                          summary.typingSessionSummary!
                              .typingContributionToInteractionIntensity
                              .toStringAsFixed(3)),
                      _buildInfoRow('Deep Typing Blocks',
                          '${summary.typingSessionSummary!.deepTypingBlocks}'),
                      _buildInfoRow(
                          'Typing Fragmentation',
                          summary.typingSessionSummary!.typingFragmentation
                              .toStringAsFixed(3)),
                      if (summary.typingSessionSummary!.individualTypingSessions
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Individual Typing Sessions (${summary.typingSessionSummary!.individualTypingSessions.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...summary
                            .typingSessionSummary!.individualTypingSessions
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
                        summary.systemState.internetState
                            ? 'Connected'
                            : 'Disconnected'),
                    _buildInfoRow('Do Not Disturb',
                        summary.systemState.doNotDisturb ? 'On' : 'Off'),
                    _buildInfoRow('Charging',
                        summary.systemState.charging ? 'Yes' : 'No'),
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
