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

class _BehaviorDemoPageState extends State<BehaviorDemoPage> {
  SynheartBehavior? _behavior;
  BehaviorSession? _currentSession;
  BehaviorStats? _currentStats;
  List<BehaviorEvent> _events = [];
  BehaviorWindowFeatures? _shortWindowFeatures;
  BehaviorWindowFeatures? _longWindowFeatures;
  bool _isInitialized = false;
  bool _isSessionActive = false;

  @override
  void initState() {
    super.initState();
    _initializeSDK();
  }

  Future<void> _initializeSDK() async {
    try {
      final behavior = await SynheartBehavior.initialize(
        config: const BehaviorConfig(
          enableInputSignals: true,
          enableAttentionSignals: true,
          enableMotionLite: false,
        ),
      );

      // Listen to raw events
      behavior.onEvent.listen((event) {
        setState(() {
          _events.insert(0, event);
          if (_events.length > 50) {
            _events = _events.take(50).toList();
          }
        });
      });

      // Listen to 30-second window features (updates every 5s)
      behavior.onShortWindowFeatures.listen((features) {
        setState(() {
          _shortWindowFeatures = features;
        });
      });

      // Listen to 5-minute window features (updates every 30s)
      behavior.onLongWindowFeatures.listen((features) {
        setState(() {
          _longWindowFeatures = features;
        });

        // Example: Convert to HSI payload format
        final hsiPayload = behavior.toHSIPayload(features);
        if (hsiPayload != null) {
          // In production, send this payload to your HSI service
          // print('HSI Payload: ${jsonEncode(hsiPayload)}');
        }
      });

      // Check and request notification permission
      await _checkAndRequestNotificationPermission(behavior);

      // Auto-start a session for testing
      final session = await behavior.startSession();
      print('[DEBUG] Example app: Started session ${session.sessionId}');

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
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start session: $e')),
        );
      }
    }
  }

  Future<void> _endSession() async {
    if (_currentSession == null) return;

    try {
      final summary = await _currentSession!.end();
      setState(() {
        _currentSession = null;
        _isSessionActive = false;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Session Summary'),
            content: Text(
              'Duration: ${summary.duration}ms\n'
              'Event Count: ${summary.eventCount}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
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

  @override
  void dispose() {
    _behavior?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Synheart Behavior Demo'),
      ),
      body: SingleChildScrollView(
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
                          _isInitialized ? 'Initialized' : 'Not Initialized',
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
                          Text('Session Active: ${_currentSession?.sessionId}'),
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
                        ? _startSession
                        : null,
                    child: const Text('Start Session'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _isInitialized && _isSessionActive ? _endSession : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('End Session'),
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

            const SizedBox(height: 16),

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
                      _buildStatRow('Typing Cadence',
                          _currentStats!.typingCadence?.toStringAsFixed(2)),
                      _buildStatRow('Scroll Velocity',
                          _currentStats!.scrollVelocity?.toStringAsFixed(2)),
                      _buildStatRow('App Switches/min',
                          _currentStats!.appSwitchesPerMinute.toString()),
                      _buildStatRow('Stability Index',
                          _currentStats!.stabilityIndex?.toStringAsFixed(2)),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // 30-Second Window Features
            if (_shortWindowFeatures != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '30-Second Window Features',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Chip(
                        label: Text(
                          'Updates every 5s',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        backgroundColor: Colors.blue.shade100,
                      ),
                      const SizedBox(height: 8),
                      _buildFeatureRow('Tap Rate (norm)',
                          _shortWindowFeatures!.tapRateNorm.toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Keystroke Rate (norm)',
                          _shortWindowFeatures!.keystrokeRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Scroll Velocity (norm)',
                          _shortWindowFeatures!.scrollVelocityNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Typing Stability',
                          _shortWindowFeatures!.typingCadenceStability
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Scroll Stability',
                          _shortWindowFeatures!.scrollCadenceStability
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Interaction Intensity',
                          _shortWindowFeatures!.interactionIntensity
                              .toStringAsFixed(3)),
                      _buildFeatureRow('Idle Ratio',
                          _shortWindowFeatures!.idleRatio.toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Switch Rate (norm)',
                          _shortWindowFeatures!.switchRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Fragmentation',
                          _shortWindowFeatures!.sessionFragmentation
                              .toStringAsFixed(3)),
                      _buildFeatureRow('Burstiness',
                          _shortWindowFeatures!.burstiness.toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Notif Rate (norm)',
                          _shortWindowFeatures!.notifRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Notif Open Rate (norm)',
                          _shortWindowFeatures!.notifOpenRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Notification Score',
                          _shortWindowFeatures!.notificationScore
                              .toStringAsFixed(3)),
                      const Divider(),
                      _buildFeatureRow(
                          'Distraction Score',
                          _shortWindowFeatures!.distractionScore
                              .toStringAsFixed(3),
                          isHighlight: true,
                          color: _shortWindowFeatures!.distractionScore > 0.5
                              ? Colors.red
                              : Colors.green),
                      _buildFeatureRow('Focus Hint',
                          _shortWindowFeatures!.focusHint.toStringAsFixed(3),
                          isHighlight: true,
                          color: _shortWindowFeatures!.focusHint > 0.5
                              ? Colors.green
                              : Colors.orange),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // 5-Minute Window Features
            if (_longWindowFeatures != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '5-Minute Window Features',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Chip(
                        label: Text(
                          'Updates every 30s',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        backgroundColor: Colors.purple.shade100,
                      ),
                      const SizedBox(height: 8),
                      _buildFeatureRow('Tap Rate (norm)',
                          _longWindowFeatures!.tapRateNorm.toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Keystroke Rate (norm)',
                          _longWindowFeatures!.keystrokeRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Scroll Velocity (norm)',
                          _longWindowFeatures!.scrollVelocityNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Typing Stability',
                          _longWindowFeatures!.typingCadenceStability
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Scroll Stability',
                          _longWindowFeatures!.scrollCadenceStability
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Interaction Intensity',
                          _longWindowFeatures!.interactionIntensity
                              .toStringAsFixed(3)),
                      _buildFeatureRow('Idle Ratio',
                          _longWindowFeatures!.idleRatio.toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Switch Rate (norm)',
                          _longWindowFeatures!.switchRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Fragmentation',
                          _longWindowFeatures!.sessionFragmentation
                              .toStringAsFixed(3)),
                      _buildFeatureRow('Burstiness',
                          _longWindowFeatures!.burstiness.toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Notif Rate (norm)',
                          _longWindowFeatures!.notifRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Notif Open Rate (norm)',
                          _longWindowFeatures!.notifOpenRateNorm
                              .toStringAsFixed(3)),
                      _buildFeatureRow(
                          'Notification Score',
                          _longWindowFeatures!.notificationScore
                              .toStringAsFixed(3)),
                      const Divider(),
                      _buildFeatureRow(
                          'Distraction Score',
                          _longWindowFeatures!.distractionScore
                              .toStringAsFixed(3),
                          isHighlight: true,
                          color: _longWindowFeatures!.distractionScore > 0.5
                              ? Colors.red
                              : Colors.green),
                      _buildFeatureRow('Focus Hint',
                          _longWindowFeatures!.focusHint.toStringAsFixed(3),
                          isHighlight: true,
                          color: _longWindowFeatures!.focusHint > 0.5
                              ? Colors.green
                              : Colors.orange),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Events List
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Events (${_events.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 300,
                      child: _events.isEmpty
                          ? const Center(
                              child: Text(
                                  'No events yet. Start a session and interact with the app.'),
                            )
                          : ListView.builder(
                              itemCount: _events.length,
                              itemBuilder: (context, index) {
                                final event = _events[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(event.type.name),
                                  subtitle: Text(
                                    'Session: ${event.sessionId}\n'
                                    'Time: ${DateTime.fromMillisecondsSinceEpoch(event.timestamp)}',
                                  ),
                                  trailing: Text(
                                    '${event.payload.length} fields',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // Interactive Test Area
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Area',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Try typing in the field below or scrolling to generate behavioral events.',
                    ),
                    const SizedBox(height: 8),
                    if (_behavior != null)
                      _behavior!.createBehaviorTextField(
                        decoration: const InputDecoration(
                          hintText: 'Type here to test keystroke timing...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 5,
                      )
                    else
                      const TextField(
                        decoration: InputDecoration(
                          hintText: 'Type here to test keystroke timing...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 5,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Wrap with gesture detector if SDK is initialized
    if (_behavior != null) {
      return _behavior!.wrapWithGestureDetector(content);
    }

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

  Widget _buildFeatureRow(String label, String value,
      {bool isHighlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isHighlight
                ? TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  )
                : null,
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: isHighlight ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
