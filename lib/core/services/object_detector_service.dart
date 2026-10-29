import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Structured detection result containing label, confidence, bounding box, spatial position, and proximity.
class DetectedVisionItem {
  final String label;
  final double confidence;
  final Rect boundingBox;
  final String position; // 'left', 'center', or 'right'
  final String proximity; // 'close', 'near', or 'far'
  final String? cameraGuidance; // Guidance to center object e.g. "Move camera slightly to your left"
  final bool isHighConfidence;
  final bool isOverheadHazard;
  final double? estimatedDistanceMeters;
  final String clockPosition; // e.g. '10 o\'clock', '11 o\'clock', '12 o\'clock', '1 o\'clock', '2 o\'clock'

  const DetectedVisionItem({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.position,
    this.proximity = 'near',
    this.cameraGuidance,
    this.isHighConfidence = true,
    this.isOverheadHazard = false,
    this.estimatedDistanceMeters,
    this.clockPosition = "12 o'clock",
  });

  /// Formats natural relative phrasing with clock directions (Option C: Combined).
  /// e.g. "Keys on your left, 10 o'clock, about 1.2 meters away."
  String formatSpatialDescription({bool isKannada = false, String? customLabel}) {
    final displayLabel = customLabel ?? label;
    final distText = estimatedDistanceMeters != null
        ? (isKannada
            ? 'ಸುಮಾರು $estimatedDistanceMeters ಮೀಟರ್ ದೂರದಲ್ಲಿದೆ'
            : 'about $estimatedDistanceMeters meters away')
        : (isKannada ? 'ಸಮೀಪದಲ್ಲಿದೆ' : 'close by');

    if (isKannada) {
      if (position == 'center') {
        return '$displayLabel ನೇರವಾಗಿ ಮುಂದೆ, $distText.';
      } else {
        final posKn = position == 'left' ? 'ಎಡಕ್ಕೆ' : 'ಬಲಕ್ಕೆ';
        return '$displayLabel ನಿಮ್ಮ $posKn, $clockPosition ದಿಕ್ಕಿನಲ್ಲಿ, $distText.';
      }
    } else {
      if (position == 'center') {
        return '$displayLabel directly ahead, $distText.';
      } else {
        return '$displayLabel on your $position, $clockPosition, $distText.';
      }
    }
  }

  /// Formats concise front-loaded phrasing for rapid low-latency guidance.
  /// e.g. "Backpack: 10 o'clock, 1.5m" / "ಕುರ್ಚಿ: 12 ಗಂಟೆ, 1.5 ಮೀಟರ್"
  String formatConciseDescription({bool isKannada = false, String? customLabel}) {
    final displayLabel = customLabel ?? label;
    final distStr = estimatedDistanceMeters != null ? '${estimatedDistanceMeters}m' : '';

    if (isKannada) {
      final clockKn = clockPosition
          .replaceAll(" o'clock", ' ಗಂಟೆ')
          .replaceAll("o'clock", 'ಗಂಟೆ');
      final dText = estimatedDistanceMeters != null ? ', ಸುಮಾರು $estimatedDistanceMeters ಮೀಟರ್' : '';
      return '$displayLabel: $clockKn$dText';
    } else {
      return '$displayLabel: $clockPosition${distStr.isNotEmpty ? ', $distStr' : ''}';
    }
  }

  @override
  String toString() =>
      '$label ($position, ${(confidence * 100).toStringAsFixed(0)}%, clock: $clockPosition, dist: ${estimatedDistanceMeters ?? "N/A"}m${isOverheadHazard ? ", overhead" : ""})';
}

/// Genuine on-device object detection service using a COCO-trained MobileNet SSD model.
///
/// Supports 90 COCO classes including person, bottle, laptop, chair, book, cup, backpack, car, bicycle, and traffic light.
class ObjectDetectorService {
  static const String modelAssetPath = 'assets/models/ssd_mobilenet/detect.tflite';
  static const String labelAssetPath = 'assets/models/ssd_mobilenet/labelmap.txt';
  static const int inputSize = 300;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;
  bool _isAvailable = false;

  // Optional mock detections for testing
  List<DetectedVisionItem>? testMockDetections;

  bool get isInitialized => _isInitialized;
  bool get isAvailable => _isAvailable;
  List<String> get supportedLabels => List.unmodifiable(_labels);

  /// Initializes the TFLite interpreter and loads the COCO label map.
  Future<bool> initialize() async {
    if (_isInitialized) return _isAvailable;

    try {
      // 1. Load label map from assets
      final labelData = await rootBundle.loadString(labelAssetPath);
      _labels = labelData
          .split('\n')
          .map((l) => l.trim().toLowerCase())
          .where((l) => l.isNotEmpty)
          .toList();
      debugPrint('[ObjectDetectorService] Loaded ${_labels.length} labels from $labelAssetPath');

      // 2. Load TFLite model
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(modelAssetPath, options: options);
      _interpreter!.allocateTensors();

      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      debugPrint('[ObjectDetectorService] Model loaded. Input: ${inputTensor.shape}, Output: ${outputTensor.shape}');

      _isAvailable = true;
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[ObjectDetectorService] Initialization error (safe fallback enabled): $e');
      _isAvailable = false;
      _isInitialized = true;
      return false;
    }
  }

  /// Runs real on-device inference directly on [imageBytes] without writing to disk.
  Future<List<DetectedVisionItem>> detectObjectsFromBytes(
    Uint8List imageBytes, {
    double imageWidth = 720.0,
    double imageHeight = 1280.0,
    double confidenceThreshold = 0.45,
  }) async {
    // Return mock detections if provided (for test environment)
    if (testMockDetections != null) {
      return testMockDetections!;
    }

    if (!_isInitialized) {
      await initialize();
    }

    if (!_isAvailable || _interpreter == null) {
      debugPrint('[ObjectDetectorService] Interpreter not available on this platform.');
      return [];
    }

    if (imageBytes.isEmpty) {
      return [];
    }

    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        debugPrint('[ObjectDetectorService] Failed to decode image bytes.');
        return [];
      }

      // 0. Correct EXIF orientation so frames are oriented right-side up
      final image = img.bakeOrientation(decoded);
      final actualWidth = image.width.toDouble();
      final actualHeight = image.height.toDouble();

      // 1. Aspect-ratio preserving letterbox resize to 300x300
      final double scale = inputSize / (actualWidth > actualHeight ? actualWidth : actualHeight);
      final int scaledW = (actualWidth * scale).round().clamp(1, inputSize);
      final int scaledH = (actualHeight * scale).round().clamp(1, inputSize);
      final resizedScaled = img.copyResize(image, width: scaledW, height: scaledH);

      final int padX = (inputSize - scaledW) ~/ 2;
      final int padY = (inputSize - scaledH) ~/ 2;

      // 2. Prepare uint8 input tensor [1, 300, 300, 3] with black letterbox padding
      final inputBytes = List.generate(
        1,
        (_) => List.generate(
          inputSize,
          (y) => List.generate(
            inputSize,
            (x) {
              if (x >= padX && x < padX + scaledW && y >= padY && y < padY + scaledH) {
                final pixel = resizedScaled.getPixel(x - padX, y - padY);
                return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
              }
              return [0, 0, 0];
            },
          ),
        ),
      );

      // 3. Prepare output tensors
      final locations = List.generate(
        1,
        (_) => List.generate(10, (_) => List.filled(4, 0.0)),
      );
      final classes = List.generate(1, (_) => List.filled(10, 0.0));
      final scores = List.generate(1, (_) => List.filled(10, 0.0));
      final numDetections = List.filled(1, 0.0);

      final outputs = {
        0: locations,
        1: classes,
        2: scores,
        3: numDetections,
      };

      // 4. Run inference
      final startTime = DateTime.now();
      _interpreter!.runForMultipleInputs([inputBytes], outputs);
      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[ObjectDetectorService] Inference complete in ${latencyMs}ms');

      final count = (numDetections[0] as num).toInt().clamp(0, 10);
      final List<DetectedVisionItem> results = [];
      final Set<String> seenPositionLabel = {};

      for (int i = 0; i < count; i++) {
        final score = scores[0][i].toDouble();
        if (score < confidenceThreshold) continue;

        // Label offset fix: TensorFlow SSD models output detection classes starting from 0 (0 = person).
        final rawClassIdx = classes[0][i].toInt();
        const int labelOffset = 1;
        final classIdx = rawClassIdx + labelOffset;
        String label = 'object';
        if (classIdx >= 0 && classIdx < _labels.length) {
          final mapped = _labels[classIdx];
          if (mapped != '???') {
            label = mapped;
          }
        }

        // Bounding box in letterboxed tensor normalized coordinates [ymin, xmin, ymax, xmax]
        final tYmin = locations[0][i][0].toDouble().clamp(0.0, 1.0);
        final tXmin = locations[0][i][1].toDouble().clamp(0.0, 1.0);
        final tYmax = locations[0][i][2].toDouble().clamp(0.0, 1.0);
        final tXmax = locations[0][i][3].toDouble().clamp(0.0, 1.0);

        // Map back to original unpadded image coordinates
        final xminNorm = (((tXmin * inputSize) - padX) / scaledW).clamp(0.0, 1.0);
        final yminNorm = (((tYmin * inputSize) - padY) / scaledH).clamp(0.0, 1.0);
        final xmaxNorm = (((tXmax * inputSize) - padX) / scaledW).clamp(0.0, 1.0);
        final ymaxNorm = (((tYmax * inputSize) - padY) / scaledH).clamp(0.0, 1.0);

        final boxRect = Rect.fromLTRB(
          xminNorm * actualWidth,
          yminNorm * actualHeight,
          xmaxNorm * actualWidth,
          ymaxNorm * actualHeight,
        );

        final centerX = (xminNorm + xmaxNorm) / 2.0;
        final String position;
        final String cameraGuidance;

        if (centerX < 0.35) {
          position = 'left';
          cameraGuidance = centerX < 0.20
              ? 'Move camera slightly to your left to center $label.'
              : '$label is to your left.';
        } else if (centerX > 0.65) {
          position = 'right';
          cameraGuidance = centerX > 0.80
              ? 'Move camera slightly to your right to center $label.'
              : '$label is to your right.';
        } else {
          position = 'center';
          cameraGuidance = '$label is directly in front of you.';
        }

        // Fine-grained clock position based on horizontal center
        final String clockPosition;
        if (centerX < 0.25) {
          clockPosition = "10 o'clock";
        } else if (centerX < 0.42) {
          clockPosition = "11 o'clock";
        } else if (centerX <= 0.58) {
          clockPosition = "12 o'clock";
        } else if (centerX <= 0.75) {
          clockPosition = "1 o'clock";
        } else {
          clockPosition = "2 o'clock";
        }

        // Describe visual prominence in frame and estimate physically grounded distance
        final boxHeightRatio = ymaxNorm - yminNorm;
        final String proximity;
        if (boxHeightRatio > 0.45) {
          proximity = 'close';
        } else if (boxHeightRatio > 0.20) {
          proximity = 'near';
        } else {
          proximity = 'far';
        }

        // Pinhole camera focal distance estimation (meters)
        final double estimatedDist = (0.65 / boxHeightRatio).clamp(0.5, 8.0);

        // Detect overhead/head-level hazards: suspended in top half of frame, not touching ground
        final bool isOverhead = yminNorm < 0.28 && ymaxNorm < 0.65 && centerX >= 0.25 && centerX <= 0.75;
        final String finalGuidance = isOverhead
            ? 'Head-level obstacle ahead: low clearance for $label.'
            : cameraGuidance;

        // Avoid duplicate announcements of identical item in the same sector
        final dedupeKey = '$label-$position';
        if (seenPositionLabel.contains(dedupeKey)) {
          continue;
        }
        seenPositionLabel.add(dedupeKey);

        results.add(DetectedVisionItem(
          label: label,
          confidence: score,
          boundingBox: boxRect,
          position: position,
          proximity: proximity,
          cameraGuidance: finalGuidance,
          isHighConfidence: score >= 0.60,
          isOverheadHazard: isOverhead,
          estimatedDistanceMeters: double.parse(estimatedDist.toStringAsFixed(1)),
          clockPosition: clockPosition,
        ));
      }

      debugPrint('[ObjectDetectorService] Detected ${results.length} valid objects: $results');
      return results;
    } catch (e) {
      debugPrint('[ObjectDetectorService] Inference error: $e');
      return [];
    }
  }

  /// Runs real on-device inference on [imagePath] by reading bytes and delegating to [detectObjectsFromBytes].
  Future<List<DetectedVisionItem>> detectObjectsFromPath(
    String imagePath, {
    double imageWidth = 720.0,
    double imageHeight = 1280.0,
    double confidenceThreshold = 0.45,
  }) async {
    // Return mock detections if provided (for test environment)
    if (testMockDetections != null) {
      return testMockDetections!;
    }

    final file = File(imagePath);
    if (!file.existsSync()) {
      debugPrint('[ObjectDetectorService] Image file not found: $imagePath');
      return [];
    }
    final bytes = await file.readAsBytes();
    return detectObjectsFromBytes(
      bytes,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      confidenceThreshold: confidenceThreshold,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _isAvailable = false;
  }
}
