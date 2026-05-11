import 'package:flutter/material.dart';
import '../models/bpm_record.dart';
import '../services/api_service.dart';

class HealthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<BpmRecord> _history = [];
  BpmRecord? _latestRecord;
  bool _isLoading = false;

  List<BpmRecord> get history => _history;
  BpmRecord? get latestRecord => _latestRecord;
  bool get isLoading => _isLoading;

  Future<void> fetchHistory(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Load local records immediately
      final localHistory = await _apiService.getLocalHistory(userId);
      if (localHistory.isNotEmpty) {
        _history = localHistory;
        _latestRecord = localHistory.first;
        _isLoading = false;
        notifyListeners();
      }

      // 2. Fetch from server
      final serverHistory = await _apiService.getHistory(userId);
      _history = serverHistory;
      if (serverHistory.isNotEmpty) {
        _latestRecord = serverHistory.first;
      }
    } catch (e) {
      debugPrint('Error fetching history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addRecord(BpmRecord record) {
    // Add to top of list
    _history.insert(0, record);
    _latestRecord = record;
    notifyListeners();
  }

  Future<void> saveNewRecord(BpmRecord record) async {
    // Optimistically add to UI
    addRecord(record);
    
    // Save via API (handles local and server)
    await _apiService.saveBpm(record);
    
    // Re-fetch to ensure sync (optional)
    // await fetchHistory(record.userId);
  }
}
