"""
PulseTrack rPPG Signal Processing Backend

FastAPI microservice that receives batched RGB signals from the
Flutter app and returns scientifically processed vital signs.

Endpoints:
  POST /api/rppg/analyze  — Full rPPG analysis (BPM, HRV, SpO2, BP, Stress)
  GET  /api/rppg/health   — Health check

Run:
  uvicorn app:app --host 0.0.0.0 --port 8000 --reload
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import numpy as np
from scipy.signal import detrend

from models import RppgAnalysisRequest, RppgAnalysisResponse, ErrorResponse
from signal_processing import (
    process_rppg_signals,
    butterworth_bandpass,
    normalize_signal,
    moving_average_smooth,
)
from hrv_analysis import analyze_hrv

app = FastAPI(
    title="PulseTrack rPPG Backend",
    description="Scientific signal processing for remote photoplethysmography",
    version="1.0.0",
)

# CORS — allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/rppg/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "ok", "service": "pulsetrack-rppg-backend", "version": "1.0.0"}


@app.post("/api/rppg/analyze")
async def analyze_rppg(request: RppgAnalysisRequest):
    """
    Analyze batched RGB signals and return vital signs.

    The Flutter app extracts RGB channel averages from the facial ROI
    on-device using ML Kit face detection, then sends the accumulated
    signal arrays here for scientific processing.
    """
    # Validate input lengths match
    n = len(request.green_signals)
    if n != len(request.red_signals) or n != len(request.blue_signals):
        raise HTTPException(status_code=400, detail="Signal arrays must have equal length")

    if n < 60:
        return {
            "success": False, "bpm": 0, "bpm_raw": 0.0, "confidence": 0.0,
            "dominant_frequency_hz": 0.0, "signal_quality": "Poor",
            "samples_used": n,
            "message": f"Insufficient data: need 60+ samples, got {n}",
        }

    # ── Run the main signal processing pipeline ──────────────────────
    result = process_rppg_signals(
        red=request.red_signals,
        green=request.green_signals,
        blue=request.blue_signals,
        timestamps_ms=request.timestamps_ms,
        sample_rate=request.sample_rate,
    )

    if not result.get("success", False):
        return result

    # ── Run HRV analysis on the filtered signal ──────────────────────
    # Re-create the filtered signal for HRV peak detection
    green = np.array(request.green_signals, dtype=np.float64)
    fs = request.sample_rate
    if len(request.timestamps_ms) >= 2:
        median_dt = np.median(np.diff(request.timestamps_ms))
        if median_dt > 0:
            fs = 1000.0 / median_dt

    signal = moving_average_smooth(green, window=3)
    signal = normalize_signal(signal)
    signal = detrend(signal, type='linear')
    filtered = butterworth_bandpass(signal, fs)

    hrv_result = analyze_hrv(filtered, fs, result["bpm"])

    if hrv_result:
        result["hrv"] = hrv_result["hrv"]
        result["stress"] = hrv_result["stress"]

        # Refine BP estimate using HRV data
        from signal_processing import estimate_blood_pressure
        rmssd = hrv_result["hrv"]["rmssd_ms"]
        sys, dia = estimate_blood_pressure(result["bpm_raw"], rmssd)
        result["systolic_estimated"] = sys
        result["diastolic_estimated"] = dia

    return result


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)
