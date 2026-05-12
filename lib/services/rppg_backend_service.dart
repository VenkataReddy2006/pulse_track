import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for communicating with the Python rPPG signal processing backend.
///
/// Sends batched RGB signals from the Flutter app to the FastAPI backend
/// for scientific processing (FFT, bandpass filter, HRV analysis).
class RppgBackendService {
  static final RppgBackendService _instance = RppgBackendService._internal();
  factory RppgBackendService() => _instance;
  RppgBackendService._internal();

  /// Backend URL — configurable for local dev vs production
  /// In production, set via environment variable or config
  static const String _defaultUrl = 'http://10.0.2.2:8000'; // Android emulator
  static const String _webUrl = 'http://localhost:8000';

  String get _baseUrl => kIsWeb ? _webUrl : _defaultUrl;

  /// Send accumulated RGB signals to the Python backend for analysis.
  ///
  /// Returns a Map with keys: success, bpm, confidence, spo2_estimated,
  /// systolic_estimated, diastolic_estimated, hrv, stress, etc.
  Future<Map<String, dynamic>> analyzeSignals({
    required List<double> redSignals,
    required List<double> greenSignals,
    required List<double> blueSignals,
    required List<double> timestampsMs,
    double sampleRate = 30.0,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/rppg/analyze');
      final body = jsonEncode({
        'red_signals': redSignals,
        'green_signals': greenSignals,
        'blue_signals': blueSignals,
        'timestamps_ms': timestampsMs,
        'sample_rate': sampleRate,
      });

      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        debugPrint('rPPG backend error: ${response.statusCode} ${response.body}');
        return _errorResponse('Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('rPPG backend unreachable: $e');
      return _errorResponse('Backend unreachable: $e');
    }
  }

  /// Check if the Python backend is running.
  Future<bool> isAvailable() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/rppg/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _errorResponse(String message) {
    return {
      'success': false,
      'error': 'backend_error',
      'message': message,
      'bpm': 0,
      'bpm_raw': 0.0,
      'confidence': 0.0,
      'dominant_frequency_hz': 0.0,
      'signal_quality': 'Poor',
      'samples_used': 0,
    };
  }
}
