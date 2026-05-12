"""
Heart Rate Variability (HRV) Analysis Module

Computes time-domain HRV metrics from the filtered rPPG signal:
  - RMSSD: Root Mean Square of Successive Differences
  - SDNN: Standard Deviation of NN (normal-to-normal) intervals
  - pNN50: Percentage of successive RR intervals > 50ms apart

Stress estimation uses validated HRV thresholds:
  - High HRV (RMSSD > 40ms) → Relaxed (parasympathetic dominant)
  - Medium HRV (20-40ms) → Mild Stress
  - Low HRV (< 20ms) → High Stress (sympathetic dominant)

Reference:
  Shaffer & Ginsberg (2017): "An Overview of Heart Rate Variability
  Metrics and Norms", Frontiers in Public Health.
"""

import numpy as np
from scipy.signal import find_peaks
from typing import Dict, List, Optional, Tuple


def detect_rr_intervals(filtered_signal: np.ndarray, fs: float) -> List[float]:
    """
    Detect R-R intervals from the filtered rPPG signal using peak detection.

    Args:
        filtered_signal: Bandpass-filtered signal
        fs: Sampling frequency in Hz

    Returns:
        List of RR intervals in milliseconds
    """
    if len(filtered_signal) < 30:
        return []

    # Minimum distance between peaks: at 200 BPM → 0.3s → 0.3*fs samples
    min_distance = int(0.3 * fs)
    min_distance = max(min_distance, 3)

    # Find peaks with minimum prominence to reject noise peaks
    signal_range = np.max(filtered_signal) - np.min(filtered_signal)
    min_prominence = signal_range * 0.15

    peaks, properties = find_peaks(
        filtered_signal,
        distance=min_distance,
        prominence=min_prominence,
    )

    if len(peaks) < 3:
        return []

    # Convert peak indices to RR intervals in milliseconds
    rr_intervals_samples = np.diff(peaks)
    rr_intervals_ms = (rr_intervals_samples / fs) * 1000.0

    # Filter out physiologically impossible intervals
    # Normal RR: 300ms (200 BPM) to 1500ms (40 BPM)
    valid = (rr_intervals_ms >= 300) & (rr_intervals_ms <= 1500)
    rr_intervals_ms = rr_intervals_ms[valid]

    return rr_intervals_ms.tolist()


def compute_rmssd(rr_intervals: List[float]) -> float:
    """
    Root Mean Square of Successive Differences.
    Primary time-domain measure of parasympathetic (vagal) activity.
    """
    if len(rr_intervals) < 2:
        return 0.0
    diffs = np.diff(rr_intervals)
    return float(np.sqrt(np.mean(diffs ** 2)))


def compute_sdnn(rr_intervals: List[float]) -> float:
    """
    Standard Deviation of NN intervals.
    Reflects overall HRV (both sympathetic and parasympathetic).
    """
    if len(rr_intervals) < 2:
        return 0.0
    return float(np.std(rr_intervals, ddof=1))


def compute_pnn50(rr_intervals: List[float]) -> float:
    """
    Percentage of successive RR intervals differing by more than 50ms.
    Another parasympathetic activity marker.
    """
    if len(rr_intervals) < 2:
        return 0.0
    diffs = np.abs(np.diff(rr_intervals))
    return float(np.sum(diffs > 50) / len(diffs) * 100)


def estimate_stress(rmssd: float, sdnn: float, bpm: float) -> Dict:
    """
    Estimate stress level from HRV metrics and heart rate.

    Uses a composite scoring approach:
    - Low RMSSD/SDNN → higher sympathetic tone → more stress
    - Elevated resting heart rate → more stress

    Returns:
        Dict with level, score (0-1), and description
    """
    stress_score = 0.0

    # RMSSD component (weight: 40%)
    if rmssd > 0:
        if rmssd < 20:
            stress_score += 0.40
        elif rmssd < 30:
            stress_score += 0.28
        elif rmssd < 40:
            stress_score += 0.16
        elif rmssd < 60:
            stress_score += 0.08
        # rmssd >= 60: no stress contribution

    # SDNN component (weight: 30%)
    if sdnn > 0:
        if sdnn < 30:
            stress_score += 0.30
        elif sdnn < 50:
            stress_score += 0.20
        elif sdnn < 80:
            stress_score += 0.10

    # BPM component (weight: 30%)
    if bpm > 100:
        stress_score += 0.30
    elif bpm > 90:
        stress_score += 0.20
    elif bpm > 80:
        stress_score += 0.10
    elif bpm > 70:
        stress_score += 0.05

    stress_score = min(stress_score, 1.0)

    if stress_score >= 0.6:
        level = "High Stress"
        desc = "Your HRV indicates elevated sympathetic nervous system activity. Consider deep breathing or meditation."
    elif stress_score >= 0.35:
        level = "Mild Stress"
        desc = "Moderate stress indicators detected. A short break or relaxation exercise may help."
    else:
        level = "Relaxed"
        desc = "Your HRV indicates good parasympathetic activity. You appear calm and relaxed."

    return {
        "level": level,
        "score": round(stress_score, 3),
        "description": desc,
    }


def analyze_hrv(filtered_signal: np.ndarray, fs: float, bpm: float) -> Optional[Dict]:
    """
    Full HRV analysis pipeline.

    Args:
        filtered_signal: Bandpass-filtered rPPG signal
        fs: Sampling frequency
        bpm: Calculated heart rate

    Returns:
        Dict with HRV metrics, stress assessment, and RR intervals,
        or None if insufficient peaks detected
    """
    rr_intervals = detect_rr_intervals(filtered_signal, fs)

    if len(rr_intervals) < 3:
        return None

    rmssd = compute_rmssd(rr_intervals)
    sdnn = compute_sdnn(rr_intervals)
    pnn50 = compute_pnn50(rr_intervals)
    mean_rr = float(np.mean(rr_intervals))

    stress = estimate_stress(rmssd, sdnn, bpm)

    return {
        "hrv": {
            "rmssd_ms": round(rmssd, 2),
            "sdnn_ms": round(sdnn, 2),
            "pnn50_percent": round(pnn50, 2),
            "mean_rr_ms": round(mean_rr, 2),
            "rr_intervals_ms": [round(r, 1) for r in rr_intervals],
        },
        "stress": stress,
    }
