import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'dart:convert';
import 'models/behavior_session.dart';

/// Service for running ONNX inference on motion data to predict activity states.
class MotionStateInference {
  final OnnxRuntime _onnxRuntime = OnnxRuntime();
  OrtSession? _session;
  List<String> _classLabels = ['LAYING', 'MOVING', 'SITTING', 'STANDING'];
  bool _isLoaded = false;

  // Feature order from features.txt (loaded once, cached)
  static List<String>? _cachedFeatureOrder;

  // Counter for logging key features only on first prediction
  static int _predictionCount = 0;

  // Counter for logging probabilities only on first prediction
  static int _probLogCount = 0;

  // Use labels directly from label_mapping.json (LAYING, MOVING, SITTING, STANDING)
  // Convert to lowercase for output format

  bool get isLoaded => _isLoaded;

  /// Load the ONNX model and label mapping from assets.
  Future<void> loadModel() async {
    if (_isLoaded) return;

    try {
      // Create session options
      final sessionOptions = OrtSessionOptions();

      // Create session from asset using OnnxRuntime
      // Try package path first (for plugin assets), then fallback to regular path
      try {
        _session = await _onnxRuntime.createSessionFromAsset(
          'packages/synheart_behavior/assets/models/linear_svc_model.onnx',
          options: sessionOptions,
        );
      } catch (e) {
        _session = await _onnxRuntime.createSessionFromAsset(
          'assets/models/linear_svc_model.onnx',
          options: sessionOptions,
        );
      }

      // Load label mapping
      String labelMappingString;
      try {
        labelMappingString = await rootBundle.loadString(
          'packages/synheart_behavior/assets/models/label_mapping.json',
        );
      } catch (e) {
        labelMappingString =
            await rootBundle.loadString('assets/models/label_mapping.json');
      }
      final labelMapping =
          json.decode(labelMappingString) as Map<String, dynamic>;
      _classLabels = List<String>.from(labelMapping['labels'] as List);

      _isLoaded = true;

      // Preload feature order silently
      try {
        await _loadFeatureOrder();
      } catch (e) {
        // Feature order will be loaded on first inference
      }
    } catch (e) {
      print('MotionStateInference: Error loading model: $e');
      // Don't rethrow - allow SDK to continue without motion state inference
      // This is especially important for test environments where ONNX runtime may not be available
      _isLoaded = false;
    }
  }

  /// Load feature order from features.txt file.
  /// This ensures features are in the exact order expected by the model.
  Future<List<String>> _loadFeatureOrder() async {
    // Return cached order if already loaded
    if (_cachedFeatureOrder != null) {
      return _cachedFeatureOrder!;
    }

    try {
      // Try package path first (for plugin assets), then fallback to regular path
      String featuresText;
      try {
        print(
            'MotionStateInference: Trying to load features.txt from package path...');
        featuresText = await rootBundle.loadString(
          'packages/synheart_behavior/features.txt',
        );
        print('MotionStateInference: Successfully loaded from package path');
      } catch (e) {
        print(
            'MotionStateInference: Package path failed ($e), trying regular path...');
        featuresText = await rootBundle.loadString('features.txt');
        print('MotionStateInference: Successfully loaded from regular path');
      }

      // Parse features.txt: format is "1 tBodyAcc-mean()-X" or "1\ttBodyAcc-mean()-X"
      final lines = featuresText.split('\n');
      final featureOrder = <String>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // Extract feature name (everything after the number and whitespace)
        // Format: "number featureName" or "number\tfeatureName"
        // Use regex to find the first whitespace and take everything after it
        final match = RegExp(r'^\d+\s+(.+)$').firstMatch(trimmed);
        if (match != null) {
          final featureName = match.group(1)!.trim();
          featureOrder.add(featureName);
        } else {
          // Fallback: try splitting on whitespace
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final featureName = parts.sublist(1).join(' ').trim();
            featureOrder.add(featureName);
          }
        }
      }

      if (featureOrder.length != 561) {
        throw Exception(
            'Expected 561 features in features.txt, got ${featureOrder.length}');
      }

      _cachedFeatureOrder = featureOrder;
      return featureOrder;
    } catch (e) {
      print('MotionStateInference: ERROR loading features.txt: $e');
      print(
          'MotionStateInference: Falling back to alphabetical sort (may cause incorrect predictions!)');
      // Fallback: return empty list, will use alphabetical sort
      return [];
    }
  }

  /// Convert features map to ordered list of 561 doubles.
  /// Uses the exact feature order from features.txt.
  Future<List<double>> _featuresMapToList(Map<String, double> features) async {
    if (features.length != 561) {
      throw ArgumentError('Expected 561 features, got ${features.length}');
    }

    // Load the correct feature order from features.txt
    final featureOrder = await _loadFeatureOrder();

    if (featureOrder.isEmpty || featureOrder.length != 561) {
      // Fallback to alphabetical sort if features.txt couldn't be loaded
      print(
          'MotionStateInference: WARNING - Using alphabetical sort as fallback!');
      final sortedKeys = features.keys.toList()..sort();
      return sortedKeys.map((key) => features[key]!).toList();
    }

    // CRITICAL: Use the EXACT order from features.txt (index 1-561)
    // Do NOT sort or change the order - follow features.txt exactly as ML engineer specified
    // The index in features.txt (1-561) must match the array position (0-560)
    final orderedFeatures = <double>[];
    int missingCount = 0;
    final missingFeatures = <String>[];
    final bandEnergyAxisCounter =
        <String, int>{}; // Track which axis we're on for each band

    // Iterate through featureOrder which is already in the exact order from features.txt
    // Index 0 in orderedFeatures = feature at line 1 in features.txt
    // Index 1 in orderedFeatures = feature at line 2 in features.txt
    // ... and so on
    for (int idx = 0; idx < featureOrder.length; idx++) {
      final featureName = featureOrder[idx];
      double? featureValue;

      // First, try exact match
      if (features.containsKey(featureName)) {
        featureValue = features[featureName]!;
      } else {
        // Handle bandsEnergy features: features.txt has "fBodyAcc-bandsEnergy()-1,8" (no axis)
        // repeated 3 times (for X, Y, Z), but native code generates with axis suffix
        // Map based on occurrence order: 1st occurrence -> -X, 2nd -> -Y, 3rd -> -Z
        if (featureName.contains('bandsEnergy()') &&
            !featureName.contains('-X') &&
            !featureName.contains('-Y') &&
            !featureName.contains('-Z')) {
          final baseName = featureName;
          final axisIndex = bandEnergyAxisCounter[baseName] ?? 0;
          final axes = ['-X', '-Y', '-Z'];

          if (axisIndex < axes.length) {
            final mappedName = '$baseName${axes[axisIndex]}';
            if (features.containsKey(mappedName)) {
              featureValue = features[mappedName]!;
              bandEnergyAxisCounter[baseName] = axisIndex + 1;
            }
          }
        }
      }

      if (featureValue != null) {
        orderedFeatures.add(featureValue);
      } else {
        // Feature missing - use 0.0 as fallback and log warning
        // This maintains the correct index position even if feature is missing
        orderedFeatures.add(0.0);
        missingCount++;
        missingFeatures
            .add('[$idx] $featureName'); // Include index for debugging
      }
    }

    if (missingCount > 0) {
      print(
          'MotionStateInference: WARNING - $missingCount features missing from data');
      print(
          'MotionStateInference: Missing features: ${missingFeatures.take(10).join(", ")}${missingCount > 10 ? " ..." : ""}');

      // Also check what features ARE available (sample)
      final availableFeatures = features.keys
          .where((k) => k.contains('bandsEnergy'))
          .take(5)
          .toList();
      if (availableFeatures.isNotEmpty) {
        print(
            'MotionStateInference: Sample bandsEnergy features available: ${availableFeatures.join(", ")}');
      }
    } else {
      print('MotionStateInference: All 561 features mapped successfully');

      // Verify first few features are in correct order (for debugging)
      if (featureOrder.length >= 5 && orderedFeatures.length >= 5) {
        print('MotionStateInference: Verifying feature order (first 5):');
        for (int i = 0; i < 5; i++) {
          final expectedName = featureOrder[i];
          final actualValue = orderedFeatures[i];
          print(
              '  Index $i: ${expectedName} = ${actualValue.toStringAsFixed(6)}');
        }
      }
    }

    return orderedFeatures;
  }

  /// Run inference on a single motion data point.
  /// Returns a tuple of (predictedState, confidence)
  Future<MapEntry<String, double>> _predictSingle(
      Map<String, double> features) async {
    if (!_isLoaded || _session == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    try {
      // Convert features map to ordered list using exact order from features.txt
      // This ensures features are in the exact order the model expects
      final featureList = await _featuresMapToList(features);

      // Validate input: ensure we have exactly 561 features
      if (featureList.length != 561) {
        throw ArgumentError(
            'Expected 561 features after ordering, got ${featureList.length}');
      }

      // Check if feature map was empty (no sensor data collected)
      if (features.isEmpty) {
        print(
            'MotionStateInference: WARNING - Feature map is empty! No sensor data was collected. This will result in all-zero features.');
        print(
            'MotionStateInference: Check if enableMotionLite is true in BehaviorConfig and sensors are available.');
      }

      // Note: ML engineer confirmed no normalization is needed - features should be used as-is

      // Check for critical data quality issues
      if (featureList.isNotEmpty) {
        final nanCount = featureList.where((v) => v.isNaN).length;
        final infCount = featureList.where((v) => v.isInfinite).length;
        final zeroCount = featureList.where((v) => v == 0.0).length;
        final nonZeroCount = featureList.length - zeroCount;

        if (nanCount > 0 || infCount > 0) {
          print(
              'MotionStateInference: ERROR - Found $nanCount NaN values and $infCount Infinity values!');
        }

        // Check if most features are zero (indicates missing sensor data)
        if (zeroCount > featureList.length * 0.9) {
          print(
              'MotionStateInference: WARNING - ${zeroCount}/${featureList.length} features are zero! This suggests sensor data may not be collected properly.');
          print(
              'MotionStateInference: Only $nonZeroCount features have non-zero values.');
        }

        // Log feature statistics for first prediction
        if (_predictionCount == 0) {
          final minVal = featureList.reduce((a, b) => a < b ? a : b);
          final maxVal = featureList.reduce((a, b) => a > b ? a : b);
          final meanVal =
              featureList.reduce((a, b) => a + b) / featureList.length;
          print(
              'MotionStateInference: Feature statistics - Min: ${minVal.toStringAsFixed(6)}, Max: ${maxVal.toStringAsFixed(6)}, Mean: ${meanVal.toStringAsFixed(6)}, Zeros: $zeroCount/${featureList.length}');

          // Log feature value ranges for debugging (large values are expected, no normalization needed)
          if (maxVal.abs() > 1000.0 || meanVal.abs() > 1000.0) {
            print(
                'MotionStateInference: Feature value ranges - Max: ${maxVal.toStringAsFixed(2)}, Mean: ${meanVal.toStringAsFixed(2)}');
            print(
                'MotionStateInference: (Large values like bandsEnergy are expected - no normalization needed per ML engineer)');
          }
        }
      }

      // Log key features for diagnosis (first prediction only)
      // These features are critical for distinguishing walking from standing
      final featureOrder = await _loadFeatureOrder();
      _predictionCount++;
      if (_predictionCount == 1 &&
          featureOrder.length >= 561 &&
          featureList.length >= 561) {
        try {
          final bodyAccMeanXIdx = featureOrder.indexOf('tBodyAcc-mean()-X');
          final bodyAccStdXIdx = featureOrder.indexOf('tBodyAcc-std()-X');
          final bodyAccMagMeanIdx = featureOrder.indexOf('tBodyAccMag-mean()');
          final bodyAccMagStdIdx = featureOrder.indexOf('tBodyAccMag-std()');

          if (bodyAccMeanXIdx >= 0 &&
              bodyAccStdXIdx >= 0 &&
              bodyAccMagMeanIdx >= 0) {
            final stdX = featureList[bodyAccStdXIdx];
            final magMean = featureList[bodyAccMagMeanIdx];

            print(
                'MotionStateInference: Key features - tBodyAcc-mean()-X: ${featureList[bodyAccMeanXIdx].toStringAsFixed(6)}, tBodyAcc-std()-X: ${stdX.toStringAsFixed(6)}, tBodyAccMag-mean(): ${magMean.toStringAsFixed(6)}, tBodyAccMag-std(): ${bodyAccMagStdIdx >= 0 && bodyAccMagStdIdx < featureList.length ? featureList[bodyAccMagStdIdx].toStringAsFixed(6) : "N/A"}');
            print(
                'MotionStateInference: (For walking: std should be >0.1; for standing: std should be <0.1)');

            // Check if values suggest issue
            if (stdX < 0.05 && magMean < 0.1) {
              print(
                  'MotionStateInference: WARNING - Very low std/magnitude. Possible causes:');
              print(
                  '  1. Phone is stationary (not capturing movement during test)');
              print('  2. Feature extraction issue (check native code)');
              print('  3. Sensor data not being collected properly');
            }

            // Check raw feature map for comparison
            if (features.containsKey('tBodyAcc-std()-X')) {
              final rawStdX = features['tBodyAcc-std()-X']!;
              if ((rawStdX - stdX).abs() > 0.0001) {
                print(
                    'MotionStateInference: WARNING - Feature ordering mismatch! Raw: ${rawStdX.toStringAsFixed(6)}, Ordered: ${stdX.toStringAsFixed(6)}');
              }
            }
          }
        } catch (e) {
          // Ignore logging errors
        }
      }

      // Convert to Float32List - this is the exact input format the model expects
      final inputData = Float32List.fromList(featureList);

      // Validate input data before sending to model
      if (inputData.length != 561) {
        throw ArgumentError(
            'Input data length mismatch: expected 561, got ${inputData.length}');
      }

      // Log first few feature values being sent to model (for debugging)
      if (_predictionCount == 0) {
        final featureOrder = await _loadFeatureOrder();
        print(
            'MotionStateInference: First 5 feature values being sent to model:');
        for (int i = 0;
            i < 5 && i < featureOrder.length && i < inputData.length;
            i++) {
          print(
              '  Position $i (features.txt line ${i + 1}): ${featureOrder[i]} = ${inputData[i].toStringAsFixed(6)}');
        }
      }

      // Create input tensor with shape [1, 561] - exactly as model expects
      final inputTensor = await OrtValue.fromList(
        inputData,
        [1, 561],
      );

      // Prepare inputs - use exact input name the model expects
      final inputs = {'float_input': inputTensor};

      // Run inference (options is a named parameter)
      final runOptions = OrtRunOptions();
      final outputs = await _session!.run(inputs, options: runOptions);

      // Extract outputs from the map
      // Output 0: label (String or List<String>)
      // Output 1: probabilities/scores (Float32[1, 4])
      final outputKeys = outputs.keys.toList();
      final labelOutput = outputs[outputKeys[0]];
      final probsOutput = outputs[outputKeys[1]];

      // Release input tensor
      await inputTensor.dispose();

      // Get predicted label
      String predictedLabel = '';
      if (labelOutput != null) {
        final labelData = await labelOutput.asFlattenedList();
        // Handle label data - could be String or List
        if (labelData.isNotEmpty) {
          final firstElement = labelData[0];
          if (firstElement is String) {
            predictedLabel = firstElement;
          } else {
            // If it's a numeric index, map it to the label
            final index = (firstElement as num).toInt();
            if (index >= 0 && index < _classLabels.length) {
              predictedLabel = _classLabels[index];
            }
          }
        }
      }

      // Get probabilities/scores from model output
      // The model outputs probabilities (if probability=True) or decision scores
      List<double> probabilities = [];
      if (probsOutput != null) {
        final probsData = await probsOutput.asFlattenedList();
        // Handle nested list structure [1, 4]
        if (probsData.isNotEmpty && probsData[0] is List) {
          probabilities = List<double>.from(
              (probsData[0] as List).map((e) => e.toDouble()));
        } else {
          probabilities = List<double>.from(probsData.map((e) => e.toDouble()));
        }
      }

      // Log probabilities for first prediction to diagnose
      _probLogCount++;
      if (_probLogCount == 1) {
        print('MotionStateInference: === MODEL OUTPUT DIAGNOSTICS ===');
        print(
            'MotionStateInference: Label output type: ${labelOutput?.runtimeType}');
        print('MotionStateInference: Label output value: $predictedLabel');
        print(
            'MotionStateInference: Probabilities output type: ${probsOutput?.runtimeType}');
        print(
            'MotionStateInference: Probabilities length: ${probabilities.length}');
        if (probabilities.isNotEmpty) {
          print('MotionStateInference: Model output probabilities/scores:');
          for (int i = 0;
              i < _classLabels.length && i < probabilities.length;
              i++) {
            print(
                '  ${_classLabels[i]}: ${probabilities[i].toStringAsFixed(6)}');
          }
          // Find the class with highest score
          final maxIndex = probabilities
              .indexOf(probabilities.reduce((a, b) => a > b ? a : b));
          print(
              'MotionStateInference: Highest score class: ${_classLabels[maxIndex]} (index: $maxIndex)');

          // Calculate score differences to see how close other classes are
          final sortedScores = List<double>.from(probabilities)
            ..sort((a, b) => b.compareTo(a));
          if (sortedScores.length >= 2) {
            final diff = sortedScores[0] - sortedScores[1];
            print(
                'MotionStateInference: Score difference between top 2 classes: ${diff.toStringAsFixed(2)}');
            if (diff < 100000) {
              print(
                  'MotionStateInference: NOTE - Top 2 classes are close (diff < 100k), predictions may be uncertain');
            }
          }
        } else {
          print(
              'MotionStateInference: WARNING - No probabilities extracted from model output');
          if (probsOutput != null) {
            final probsData = await probsOutput.asFlattenedList();
            print(
                'MotionStateInference: ProbsOutput value type: ${probsData.runtimeType}');
            print('MotionStateInference: ProbsOutput value: $probsData');
          } else {
            print('MotionStateInference: ProbsOutput is null');
          }
        }
        print('MotionStateInference: === END MODEL OUTPUT DIAGNOSTICS ===');
      }

      // Use the text label from model output as the primary prediction
      // ML engineer confirmed the model returns text labels directly
      String finalPredictedLabel = predictedLabel;
      double confidence = 0.0;

      // Use probabilities/scores from model output directly (no calculations)
      if (probabilities.isNotEmpty &&
          probabilities.length == _classLabels.length) {
        // Find the index of the predicted label to get its confidence score
        final predictedIndex = _classLabels.indexOf(predictedLabel);
        if (predictedIndex >= 0 && predictedIndex < probabilities.length) {
          // Use model's raw score directly - no clamping or normalization
          confidence = probabilities[predictedIndex];
        } else {
          // Fallback: use the highest score if label index not found
          confidence = probabilities.reduce((a, b) => a > b ? a : b);
        }

        // Log model scores when movement is detected but STANDING is predicted
        // This helps diagnose why MOVING class isn't being selected
        final featureOrderForCheck = await _loadFeatureOrder();
        final bodyAccStdXIdx = featureOrderForCheck.indexOf('tBodyAcc-std()-X');
        final hasMovement = bodyAccStdXIdx >= 0 &&
            bodyAccStdXIdx < featureList.length &&
            featureList[bodyAccStdXIdx] > 0.3; // High stdX indicates movement

        if (hasMovement && finalPredictedLabel.toUpperCase() == 'STANDING') {
          print(
              'MotionStateInference: ⚠️ MOVEMENT DETECTED but STANDING predicted!');
          print(
              'MotionStateInference: stdX = ${featureList[bodyAccStdXIdx].toStringAsFixed(4)} (indicates movement)');
          print(
              'MotionStateInference: Model text output: $finalPredictedLabel');
          print('MotionStateInference: Model scores for all classes:');

          // Find index of predicted label for comparison
          final predictedIndex = _classLabels.indexOf(finalPredictedLabel);

          for (int i = 0;
              i < _classLabels.length && i < probabilities.length;
              i++) {
            final marker = i == predictedIndex ? ' ← PREDICTED' : '';
            print(
                '  ${_classLabels[i]}: ${probabilities[i].toStringAsFixed(2)}$marker');
          }
          final movIndex = _classLabels.indexOf('MOVING');
          if (movIndex >= 0 &&
              movIndex < probabilities.length &&
              predictedIndex >= 0) {
            final movScore = probabilities[movIndex];
            final standScore = probabilities[predictedIndex];
            final diff = standScore - movScore;
            print(
                'MotionStateInference: STANDING score (${standScore.toStringAsFixed(2)}) - MOVING score (${movScore.toStringAsFixed(2)}) = ${diff.toStringAsFixed(2)}');
            if (movScore < 0) {
              print(
                  'MotionStateInference: ⚠️ MOVING has NEGATIVE score even with movement!');
            }
          }
        }
      } else if (probabilities.isNotEmpty) {
        // Fallback: use predicted label from labelOutput if probabilities don't match
        final predictedIndex = _classLabels.indexOf(predictedLabel);
        if (predictedIndex >= 0 && predictedIndex < probabilities.length) {
          // Use model's raw score directly - no clamping
          confidence = probabilities[predictedIndex];
        } else {
          // Use highest score directly - no clamping
          confidence = probabilities.reduce((a, b) => a > b ? a : b);
        }
      }

      // Use text label from model output directly (as confirmed by ML engineer)
      // The model outputs labels in uppercase (LAYING, MOVING, SITTING, STANDING)
      // Convert to lowercase only for consistency with expected output format
      final outputLabel = finalPredictedLabel.toLowerCase();

      // Confidence is the raw decision score from the model
      // For SVC models, scores can be negative or outside [0,1] range
      // Return the score as-is directly from model output (no calculations)
      return MapEntry(outputLabel, confidence);
    } catch (e) {
      print('MotionStateInference: Error during prediction: $e');
      rethrow;
    }
  }

  /// Run inference on all motion data points and return aggregated motion state.
  ///
  /// Returns a MotionState object with:
  /// - state: List of predicted states for each window
  /// - major_state: Most common state
  /// - major_state_pct: Percentage of major state
  /// - ml_model: Model identifier
  /// - confidence: Average confidence (placeholder, can be enhanced)
  Future<MotionState> inferMotionState(List<MotionDataPoint> motionData) async {
    print(
        'MotionStateInference: Starting inference on ${motionData.length} data points');

    if (motionData.isEmpty) {
      print('MotionStateInference: No motion data provided');
      return MotionState(
        state: [],
        majorState: 'unknown',
        majorStatePct: 0.0,
        mlModel: 'motion_state_svc_classifier_v0.1',
        confidence: 0.0,
      );
    }

    if (!_isLoaded || _session == null) {
      print('MotionStateInference: ERROR - Model not loaded!');
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    // Run inference on each motion data point
    final List<String> states = [];
    final List<double> confidences = [];

    for (int i = 0; i < motionData.length; i++) {
      final dataPoint = motionData[i];
      try {
        // Get prediction directly from model
        final result = await _predictSingle(dataPoint.features);
        final predictedState = result.key;
        final confidence = result.value;

        states.add(predictedState);
        confidences.add(confidence);

        // Log all predictions to see what's happening
        print(
            'MotionStateInference: Data point ${i + 1}/${motionData.length} - Prediction: $predictedState (confidence: ${confidence.toStringAsFixed(3)})');

        // Log detailed diagnostics for first few data points to compare activities
        if (i < 3) {
          print(
              'MotionStateInference: Data point ${i + 1} - Feature count: ${dataPoint.features.length}');
          if (dataPoint.features.isEmpty) {
            print(
                'MotionStateInference: ERROR - Data point ${i + 1} has no features! Sensor data may not be collected.');
          } else {
            // Log key movement indicators
            final stdX = dataPoint.features['tBodyAcc-std()-X'];
            final stdY = dataPoint.features['tBodyAcc-std()-Y'];
            final stdZ = dataPoint.features['tBodyAcc-std()-Z'];
            final magMean = dataPoint.features['tBodyAccMag-mean()'];
            final magStd = dataPoint.features['tBodyAccMag-std()'];

            if (stdX != null && magMean != null) {
              print(
                  'MotionStateInference: Data point ${i + 1} key features - stdX: ${stdX.toStringAsFixed(4)}, stdY: ${stdY?.toStringAsFixed(4) ?? "N/A"}, stdZ: ${stdZ?.toStringAsFixed(4) ?? "N/A"}, magMean: ${magMean.toStringAsFixed(4)}, magStd: ${magStd?.toStringAsFixed(4) ?? "N/A"}');
              print(
                  'MotionStateInference: (Expected: stdX > 0.1 for walking/moving, < 0.1 for standing/sitting)');
            }
          }
        }
      } catch (e) {
        print(
            'MotionStateInference: ERROR predicting for data point ${i + 1}: $e');
        states.add('unknown');
        confidences.add(0.0);
      }
    }

    // Calculate major state (most common)
    final stateCounts = <String, int>{};
    for (final state in states) {
      stateCounts[state] = (stateCounts[state] ?? 0) + 1;
    }

    String majorState = 'unknown';
    int maxCount = 0;
    for (final entry in stateCounts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        majorState = entry.key;
      }
    }

    // Calculate percentage
    final majorStatePct = states.isNotEmpty ? maxCount / states.length : 0.0;

    // Use confidence from major state prediction directly (no calculations)
    // Get the confidence of the most common state from model outputs
    double confidence = 0.0;
    if (confidences.isNotEmpty && states.isNotEmpty) {
      // Find the confidence of the major state (most common prediction)
      final majorStateIndices = states
          .asMap()
          .entries
          .where((e) => e.value == majorState)
          .map((e) => e.key)
          .toList();

      if (majorStateIndices.isNotEmpty) {
        // Use the confidence from the first occurrence of major state
        // (raw model output, no averaging or calculations)
        final firstMajorStateIndex = majorStateIndices.first;
        if (firstMajorStateIndex < confidences.length) {
          confidence = confidences[firstMajorStateIndex];
        }
      } else {
        // Fallback: use first confidence if major state not found
        confidence = confidences.first;
      }
    }

    return MotionState(
      state: states,
      majorState: majorState,
      majorStatePct: majorStatePct,
      mlModel: 'motion_state_svc_classifier_v0.1',
      confidence: confidence,
    );
  }

  /// Export all 561 features as JSON for ML engineer review

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _isLoaded = false;
  }
}
