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

  List<BpmRecord> _deduplicate(List<BpmRecord> records) {
    final Map<String, BpmRecord> unique = {};
    for (var r in records) {
      // Key: userId + BPM + Year + Month + Day + Hour + Minute
      // This hides duplicates within the same minute with the same BPM
      final key = '${r.userId}_${r.bpm}_${r.timestamp.year}${r.timestamp.month}${r.timestamp.day}${r.timestamp.hour}${r.timestamp.minute}';
      if (!unique.containsKey(key)) {
        unique[key] = r;
      } else {
        // If we have a choice, keep the one with more data (Oxygen/BP)
        final existing = unique[key]!;
        bool currentHasMoreData = (r.spo2 != null && r.spo2! > 0) || (r.systolic != null && r.systolic! > 0);
        bool existingHasMoreData = (existing.spo2 != null && existing.spo2! > 0) || (existing.systolic != null && existing.systolic! > 0);
        if (currentHasMoreData && !existingHasMoreData) {
          unique[key] = r;
        }
      }
    }
    final list = unique.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<void> fetchHistory(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Load local records immediately
      final localHistory = await _apiService.getLocalHistory(userId);
      if (localHistory.isNotEmpty) {
        _history = _deduplicate(localHistory);
        _latestRecord = _history.first;
        _isLoading = false;
        notifyListeners();
      }

      // 2. Fetch from server
      final serverHistory = await _apiService.getHistory(userId);
      _history = _deduplicate(serverHistory);
      if (_history.isNotEmpty) {
        _latestRecord = _history.first;
      }
    } catch (e) {
      debugPrint('Error fetching history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addRecord(BpmRecord record) {
    // Add and deduplicate
    final newList = List<BpmRecord>.from(_history)..insert(0, record);
    _history = _deduplicate(newList);
    _latestRecord = _history.first;
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
