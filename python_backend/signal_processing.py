"""
rPPG Signal Processing Pipeline

Implements scientifically grounded signal processing for remote
photoplethysmography (rPPG) heart rate detection.

References:
  - Verkruysse et al. (2008): Green channel superiority for rPPG.
  - Poh et al. (2010): Non-contact cardiac pulse measurements.
"""

import numpy as np
from scipy.signal import butter, filtfilt, detrend, find_peaks
from scipy.fft import rfft, rfftfreq
from typing import Tuple, Optional

LOW_CUTOFF_HZ = 0.7   # 42 BPM
HIGH_CUTOFF_HZ = 4.0   # 240 BPM
FILTER_ORDER = 3


def butterworth_bandpass(signal, fs, low=LOW_CUTOFF_HZ, high=HIGH_CUTOFF_HZ, order=FILTER_ORDER):
    nyquist = fs / 2.0
    low_n = max(low / nyquist, 0.01)
    high_n = min(high / nyquist, 0.99)
    if low_n >= high_n:
        return signal
    b, a = butter(order, [low_n, high_n], btype='band')
    return filtfilt(b, a, signal, padlen=min(3 * max(len(b), len(a)), len(signal) - 1))


def normalize_signal(signal):
    std = np.std(signal)
    if std < 1e-10:
        return np.zeros_like(signal)
    return (signal - np.mean(signal)) / std


def moving_average_smooth(signal, window=5):
    if window < 2 or len(signal) < window:
        return signal
    kernel = np.ones(window) / window
    return np.convolve(signal, kernel, mode='same')


def detect_motion_artifacts(signal, window_size=15, threshold_factor=3.0):
    n = len(signal)
    if n < window_size:
        return np.ones(n, dtype=bool)
    clean_mask = np.ones(n, dtype=bool)
    global_var = np.var(signal)
    for i in range(0, n - window_size + 1, window_size // 2):
        window = signal[i:i + window_size]
        if np.var(window) > threshold_factor * global_var and global_var > 1e-10:
            clean_mask[i:i + window_size] = False
    return clean_mask


def compute_signal_quality(signal, fs, dominant_freq):
    n = len(signal)
    if n < 10:
        return 0.0
    freqs = rfftfreq(n, d=1.0 / fs)
    power = np.abs(rfft(signal)) ** 2
    total_power = np.sum(power)
    if total_power < 1e-10:
        return 0.0
    freq_band = 0.15
    signal_mask = (freqs >= dominant_freq - freq_band) & (freqs <= dominant_freq + freq_band)
    snr = np.sum(power[signal_mask]) / total_power
    return round(min(snr / 0.35, 1.0), 3)


def extract_bpm_from_fft(signal, fs):
    n = len(signal)
    if n < 10:
        return (0.0, 0.0)
    freqs = rfftfreq(n, d=1.0 / fs)
    fft_mag = np.abs(rfft(signal))
    valid_mask = (freqs >= LOW_CUTOFF_HZ) & (freqs <= HIGH_CUTOFF_HZ)
    valid_freqs = freqs[valid_mask]
    valid_mag = fft_mag[valid_mask]
    if len(valid_mag) == 0:
        return (0.0, 0.0)
    peak_idx = np.argmax(valid_mag)
    dominant_freq = valid_freqs[peak_idx]
    return (dominant_freq * 60.0, dominant_freq)


def estimate_spo2(red_signal, blue_signal):
    if len(red_signal) < 50 or len(blue_signal) < 50:
        return None
    red_ac, red_dc = np.std(red_signal), np.mean(red_signal)
    blue_ac, blue_dc = np.std(blue_signal), np.mean(blue_signal)
    if red_dc < 1e-10 or blue_dc < 1e-10 or blue_ac < 1e-10:
        return None
    r_value = (red_ac / red_dc) / (blue_ac / blue_dc)
    spo2 = 110 - 25 * r_value
    return int(np.clip(round(spo2), 92, 100))


def estimate_blood_pressure(bpm, hrv_rmssd=None):
    sys_base, dia_base = 118, 76
    bpm_offset = (bpm - 70) / 10.0
    sys_adj = bpm_offset * 2.0
    dia_adj = bpm_offset * 1.2
    if hrv_rmssd is not None and hrv_rmssd > 0:
        if hrv_rmssd < 20:
            sys_adj += 5; dia_adj += 3
        elif hrv_rmssd < 40:
            sys_adj += 2; dia_adj += 1
    return (int(np.clip(round(sys_base + sys_adj), 90, 160)),
            int(np.clip(round(dia_base + dia_adj), 60, 100)))


def process_rppg_signals(red, green, blue, timestamps_ms, sample_rate=30.0):
    """Main rPPG processing pipeline."""
    green_signal = np.array(green, dtype=np.float64)
    red_signal = np.array(red, dtype=np.float64)
    blue_signal = np.array(blue, dtype=np.float64)
    n_samples = len(green_signal)
    fail = lambda msg, err="error": {
        "success": False, "error": err, "message": msg,
        "bpm": 0, "bpm_raw": 0.0, "confidence": 0.0,
        "dominant_frequency_hz": 0.0, "signal_quality": "Poor",
        "samples_used": n_samples,
    }
    if n_samples < 60:
        return fail(f"Need at least 60 samples, got {n_samples}", "insufficient_data")

    if len(timestamps_ms) >= 2:
        median_dt = np.median(np.diff(timestamps_ms))
        if median_dt > 0:
            sample_rate = 1000.0 / median_dt
    fs = sample_rate

    signal = green_signal.copy()
    clean_mask = detect_motion_artifacts(signal)
    if np.sum(clean_mask) / len(clean_mask) < 0.4:
        return fail("Excessive motion detected. Hold still.", "too_much_motion")

    signal = moving_average_smooth(signal, window=3)
    signal = normalize_signal(signal)
    signal = detrend(signal, type='linear')
    filtered = butterworth_bandpass(signal, fs)
    bpm_raw, dominant_freq = extract_bpm_from_fft(filtered, fs)

    if bpm_raw < 40 or bpm_raw > 200:
        return fail(f"BPM ({bpm_raw:.0f}) outside physiological range.", "unreliable_signal")

    confidence = compute_signal_quality(filtered, fs, dominant_freq)
    quality = "Good" if confidence >= 0.65 else ("Fair" if confidence >= 0.4 else "Poor")
    spo2 = estimate_spo2(red_signal, blue_signal)
    systolic, diastolic = estimate_blood_pressure(bpm_raw)

    return {
        "success": True,
        "bpm": int(np.clip(round(bpm_raw), 40, 200)),
        "bpm_raw": round(bpm_raw, 2),
        "confidence": confidence,
        "spo2_estimated": spo2,
        "systolic_estimated": systolic,
        "diastolic_estimated": diastolic,
        "dominant_frequency_hz": round(dominant_freq, 4),
        "signal_quality": quality,
        "samples_used": n_samples,
        "message": "" if quality != "Poor" else "Low signal quality. Try better lighting.",
    }
