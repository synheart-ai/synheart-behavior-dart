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

      // Listen to events
      behavior.onEvent.listen((event) {
        setState(() {
          _events.insert(0, event);
          if (_events.length > 50) {
            _events = _events.take(50).toList();
          }
        });
      });

      setState(() {
        _behavior = behavior;
        _isInitialized = true;
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

  @override
  void dispose() {
    _behavior?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                          Icon(
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
                              child: Text('No events yet. Start a session and interact with the app.'),
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
                                    style: Theme.of(context).textTheme.bodySmall,
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
                    TextField(
                      decoration: const InputDecoration(
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
}

