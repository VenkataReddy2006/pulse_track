import 'dart:math' as math;
import 'rppg_backend_service.dart';

/// Represents a single RGB sample extracted from the facial ROI.
class RppgSignal {
  final double r;
  final double g;
  final double b;
  final DateTime timestamp;

  RppgSignal({required this.r, required this.g, required this.b, required this.timestamp});
}

/// Result of the rPPG analysis pipeline.
class RppgResult {
  final bool success;
  final int bpm;
  final int spo2;
  final int systolic;
  final int diastolic;
  final double confidence;
  final double? hrv;        // RMSSD in ms
  final double? sdnn;       // SDNN in ms
  final String? stressLevel;
  final double? stressScore;
  final String signalQuality;
  final String message;

  RppgResult({
    required this.success,
    required this.bpm,
    this.spo2 = 0,
    this.systolic = 0,
    this.diastolic = 0,
    this.confidence = 0.0,
    this.hrv,
    this.sdnn,
    this.stressLevel,
    this.stressScore,
    this.signalQuality = 'Poor',
    this.message = '',
  });
}

/// rPPG signal collection and analysis service.
///
/// Collects RGB signals from camera frames on-device, then sends
/// the accumulated buffer to the Python backend for scientific
/// signal processing (Butterworth filter, FFT, HRV analysis).
///
/// If the Python backend is unavailable, falls back to an improved
/// on-device peak detection algorithm (no random values).
class RppgService {
  static final RppgService _instance = RppgService._internal();
  factory RppgService() => _instance;
  RppgService._internal();

  final List<RppgSignal> _buffer = [];
  static const int _maxBufferSize = 450; // ~15 seconds at 30fps

  /// Add an RGB sample from the facial ROI.
  void addSignal(double r, double g, double b) {
    _buffer.add(RppgSignal(
      r: r,
      g: g,
      b: b,
      timestamp: DateTime.now(),
    ));

    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }
  }

  void clearBuffer() {
    _buffer.clear();
  }

  List<RppgSignal> get buffer => List.unmodifiable(_buffer);

  /// Analyze collected signals using the Python backend.
  /// Falls back to on-device processing if backend is unreachable.
  Future<RppgResult> analyzeSignals() async {
    if (_buffer.length < 90) {
      return RppgResult(
        success: false,
        bpm: 0,
        message: 'Insufficient data. Need at least 3 seconds of signal.',
      );
    }

    // Prepare signal arrays for the backend
    final redSignals = _buffer.map((s) => s.r).toList();
    final greenSignals = _buffer.map((s) => s.g).toList();
    final blueSignals = _buffer.map((s) => s.b).toList();
    final timestamps = _buffer
        .map((s) => s.timestamp.millisecondsSinceEpoch.toDouble())
        .toList();

    // Try Python backend first
    final backend = RppgBackendService();
    final result = await backend.analyzeSignals(
      redSignals: redSignals,
      greenSignals: greenSignals,
      blueSignals: blueSignals,
      timestampsMs: timestamps,
    );

    if (result['success'] == true) {
      return _parseBackendResult(result);
    }

    // Fallback: on-device processing (no random values)
    return _onDeviceAnalysis();
  }

  /// Parse the response from the Python backend into an RppgResult.
  RppgResult _parseBackendResult(Map<String, dynamic> data) {
    final hrv = data['hrv'] as Map<String, dynamic>?;
    final stress = data['stress'] as Map<String, dynamic>?;

    return RppgResult(
      success: true,
      bpm: (data['bpm'] as num?)?.toInt() ?? 0,
      spo2: (data['spo2_estimated'] as num?)?.toInt() ?? 0,
      systolic: (data['systolic_estimated'] as num?)?.toInt() ?? 0,
      diastolic: (data['diastolic_estimated'] as num?)?.toInt() ?? 0,
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
      hrv: (hrv?['rmssd_ms'] as num?)?.toDouble(),
      sdnn: (hrv?['sdnn_ms'] as num?)?.toDouble(),
      stressLevel: stress?['level'] as String?,
      stressScore: (stress?['score'] as num?)?.toDouble(),
      signalQuality: data['signal_quality'] as String? ?? 'Poor',
      message: data['message'] as String? ?? '',
    );
  }

  /// On-device fallback analysis using improved peak detection.
  /// Does NOT use random values — returns 0 if signal is unusable.
  RppgResult _onDeviceAnalysis() {
    if (_buffer.length < 90) {
      return RppgResult(success: false, bpm: 0, message: 'Insufficient data');
    }

    // Extract green channel
    final greenSignals = _buffer.map((s) => s.g).toList();

    // Normalize
    double mean = greenSignals.reduce((a, b) => a + b) / greenSignals.length;
    double stdDev = _stdDev(greenSignals, mean);
    if (stdDev < 0.001) {
      return RppgResult(success: false, bpm: 0, message: 'Signal too flat');
    }
    List<double> normalized = greenSignals.map((v) => (v - mean) / stdDev).toList();

    // Simple moving average smoothing (window=5)
    List<double> smoothed = _movingAverage(normalized, 5);

    // Peak detection with minimum distance and prominence
    double durationMs = _buffer.last.timestamp
        .difference(_buffer.first.timestamp)
        .inMilliseconds
        .toDouble();
    if (durationMs < 2000) {
      return RppgResult(success: false, bpm: 0, message: 'Scan too short');
    }
    double estimatedFs = _buffer.length / (durationMs / 1000.0);

    int minPeakDistance = (estimatedFs * 0.3).round(); // min 300ms between beats
    if (minPeakDistance < 3) minPeakDistance = 3;

    List<int> peaks = _findPeaks(smoothed, minPeakDistance, 0.15);

    if (peaks.length < 3) {
      return RppgResult(success: false, bpm: 0, message: 'Could not detect pulse peaks');
    }

    // Calculate BPM from inter-peak intervals
    List<double> intervals = [];
    for (int i = 1; i < peaks.length; i++) {
      double intervalMs = (peaks[i] - peaks[i - 1]) / estimatedFs * 1000.0;
      if (intervalMs >= 300 && intervalMs <= 1500) {
        intervals.add(intervalMs);
      }
    }

    if (intervals.isEmpty) {
      return RppgResult(success: false, bpm: 0, message: 'Unreliable peak intervals');
    }

    double meanInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    double bpmRaw = 60000.0 / meanInterval;
    int bpm = bpmRaw.round().clamp(40, 200);

    // Simple HRV: RMSSD from peak intervals
    double? rmssd;
    if (intervals.length >= 3) {
      double sumSqDiffs = 0;
      for (int i = 1; i < intervals.length; i++) {
        double diff = intervals[i] - intervals[i - 1];
        sumSqDiffs += diff * diff;
      }
      rmssd = math.sqrt(sumSqDiffs / (intervals.length - 1));
    }

    // Simple SpO2 (R/B ratio method — non-medical)
    int spo2 = 0;
    if (_buffer.length >= 50) {
      double sumR = 0, sumB = 0;
      for (var s in _buffer) { sumR += s.r; sumB += s.b; }
      double avgR = sumR / _buffer.length;
      double avgB = sumB / _buffer.length;
      if (avgB > 0.001) {
        double ratio = avgR / avgB;
        spo2 = (110 - (15 * ratio)).round().clamp(92, 100);
      }
    }

    // Stress from HRV
    String? stressLevel;
    if (rmssd != null) {
      if (rmssd < 20) {
        stressLevel = 'High Stress';
      } else if (rmssd < 40) {
        stressLevel = 'Mild Stress';
      } else {
        stressLevel = 'Relaxed';
      }
    }

    // BP estimate (deterministic — no random jitter)
    double bpmFactor = (bpm - 70) / 10.0;
    int systolic = (118 + bpmFactor * 2).round().clamp(90, 160);
    int diastolic = (76 + bpmFactor * 1.2).round().clamp(60, 100);

    return RppgResult(
      success: true,
      bpm: bpm,
      spo2: spo2,
      systolic: systolic,
      diastolic: diastolic,
      confidence: 0.5, // On-device analysis gets moderate confidence
      hrv: rmssd,
      stressLevel: stressLevel,
      signalQuality: 'Fair',
      message: 'Analyzed on-device (backend unavailable)',
    );
  }

  double _stdDev(List<double> data, double mean) {
    double sum = 0;
    for (var v in data) { sum += (v - mean) * (v - mean); }
    return math.sqrt(sum / data.length);
  }

  List<double> _movingAverage(List<double> data, int window) {
    List<double> result = List.filled(data.length, 0.0);
    int half = window ~/ 2;
    for (int i = 0; i < data.length; i++) {
      int start = (i - half).clamp(0, data.length - 1);
      int end = (i + half + 1).clamp(0, data.length);
      double sum = 0;
      for (int j = start; j < end; j++) sum += data[j];
      result[i] = sum / (end - start);
    }
    return result;
  }

  List<int> _findPeaks(List<double> data, int minDistance, double minProminence) {
    List<int> peaks = [];
    double range = data.reduce(math.max) - data.reduce(math.min);
    double threshold = range * minProminence;

    for (int i = 1; i < data.length - 1; i++) {
      if (data[i] > data[i - 1] && data[i] > data[i + 1] && data[i] > threshold) {
        if (peaks.isEmpty || (i - peaks.last) >= minDistance) {
          peaks.add(i);
        }
      }
    }
    return peaks;
  }
}
