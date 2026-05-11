import 'package:flutter/foundation.dart';

class BpmRecord {
  final String? id;
  final String userId;
  final int bpm;
  final String status;
  final int? spo2;
  final int? systolic;
  final int? diastolic;
  final DateTime timestamp;
  
  // AI Advice Fields
  final String? aiInsight;
  final List<String>? aiTips;
  final List<String>? aiWatchFor;

  BpmRecord({
    this.id,
    required this.userId,
    required this.bpm,
    required this.status,
    required this.timestamp,
    this.spo2,
    this.systolic,
    this.diastolic,
    this.aiInsight,
    this.aiTips,
    this.aiWatchFor,
  });

  factory BpmRecord.fromJson(Map<String, dynamic> json) {
    String rawStatus = json['status']?.toString() ?? 'Normal';
    int? packedSpo2;
    int? packedSys;
    int? packedDia;

    // AI advice fields from JSON
    String? insight = json['aiInsight']?.toString();
    List<String>? tips;
    if (json['aiTips'] is List) {
      tips = (json['aiTips'] as List).map((e) => e.toString()).toList();
    }
    List<String>? watchFor;
    if (json['aiWatchFor'] is List) {
      watchFor = (json['aiWatchFor'] as List).map((e) => e.toString()).toList();
    }

    // Smart Unpacking: Check if status contains packed vitals [V:spo2,sys,dia]
    if (rawStatus.contains('[V:')) {
      try {
        final parts = rawStatus.split('[V:');
        final data = parts[1].replaceAll(']', '').split(',');
        if (data.length >= 3) {
          packedSpo2 = int.tryParse(data[0].trim());
          packedSys = int.tryParse(data[1].trim());
          packedDia = int.tryParse(data[2].trim());
        }
        rawStatus = parts[0].trim();
      } catch (e) {
        debugPrint('Error unpacking vitals: $e');
      }
    }

    // Comprehensive Field Mapping
    int? sys = packedSys ?? 
               (json['systolic'] as int? ?? 
                json['systolicBP'] as int? ?? 
                int.tryParse(json['systolic']?.toString() ?? json['systolicBP']?.toString() ?? ''));
                
    int? dia = packedDia ?? 
               (json['diastolic'] as int? ?? 
                json['diastolicBP'] as int? ?? 
                int.tryParse(json['diastolic']?.toString() ?? json['diastolicBP']?.toString() ?? ''));

    int? ox = packedSpo2 ?? 
              (json['spo2'] as int? ?? 
               json['oxygenLevel'] as int? ?? 
               int.tryParse(json['spo2']?.toString() ?? json['oxygenLevel']?.toString() ?? ''));

    return BpmRecord(
      id: json['_id']?.toString() ?? json['id']?.toString(),
      userId: json['userId']?.toString() ?? '',
      bpm: json['bpm'] is int ? json['bpm'] : int.tryParse(json['bpm']?.toString() ?? '0') ?? 0,
      status: rawStatus,
      spo2: ox,
      systolic: sys,
      diastolic: dia,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']).toLocal() 
          : DateTime.now(),
      aiInsight: insight,
      aiTips: tips,
      aiWatchFor: watchFor,
    );
  }

  Map<String, dynamic> toJson() {
    String finalStatus = status;
    if (spo2 != null || systolic != null || diastolic != null) {
      finalStatus = '$status [V:${spo2 ?? 0},${systolic ?? 0},${diastolic ?? 0}]';
    }

    return {
      'userId': userId,
      'bpm': bpm,
      'status': finalStatus,
      'spo2': spo2,
      'systolic': systolic,
      'systolicBP': systolic,
      'diastolic': diastolic,
      'diastolicBP': diastolic,
      'aiInsight': aiInsight,
      'aiTips': aiTips,
      'aiWatchFor': aiWatchFor,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
