"""
Pydantic request/response models for the rPPG signal processing API.
"""

from pydantic import BaseModel, Field
from typing import List, Optional


class RppgAnalysisRequest(BaseModel):
    """
    Request payload from the Flutter app.
    Contains batched RGB signal averages extracted from facial ROI.
    """
    red_signals: List[float] = Field(..., description="Red channel average values from ROI")
    green_signals: List[float] = Field(..., description="Green channel average values from ROI")
    blue_signals: List[float] = Field(..., description="Blue channel average values from ROI")
    timestamps_ms: List[float] = Field(..., description="Timestamps in milliseconds for each sample")
    sample_rate: Optional[float] = Field(default=30.0, description="Estimated camera FPS")


class HrvMetrics(BaseModel):
    """Heart Rate Variability metrics calculated from RR intervals."""
    rmssd_ms: float = Field(..., description="Root Mean Square of Successive Differences (ms)")
    sdnn_ms: float = Field(..., description="Standard Deviation of NN intervals (ms)")
    pnn50_percent: float = Field(..., description="Percentage of successive RR intervals > 50ms apart")
    mean_rr_ms: float = Field(..., description="Mean RR interval in milliseconds")
    rr_intervals_ms: List[float] = Field(default_factory=list, description="Detected RR intervals")


class StressAssessment(BaseModel):
    """Stress estimation based on HRV metrics."""
    level: str = Field(..., description="Stress level: 'Relaxed', 'Mild Stress', or 'High Stress'")
    score: float = Field(..., description="Stress score from 0.0 (relaxed) to 1.0 (high stress)")
    description: str = Field(..., description="Human-readable stress description")


class RppgAnalysisResponse(BaseModel):
    """
    Complete rPPG analysis results returned to the Flutter app.
    """
    success: bool = Field(..., description="Whether the analysis completed successfully")
    bpm: int = Field(..., description="Estimated heart rate in beats per minute")
    bpm_raw: float = Field(..., description="Raw BPM value before rounding")
    confidence: float = Field(..., description="Signal quality confidence score (0.0 to 1.0)")

    # Estimated vitals (clearly marked as non-medical)
    spo2_estimated: Optional[int] = Field(None, description="Estimated SpO2 (non-medical, camera-based)")
    systolic_estimated: Optional[int] = Field(None, description="Estimated systolic BP (non-medical)")
    diastolic_estimated: Optional[int] = Field(None, description="Estimated diastolic BP (non-medical)")

    # HRV Analysis
    hrv: Optional[HrvMetrics] = Field(None, description="Heart Rate Variability metrics")

    # Stress
    stress: Optional[StressAssessment] = Field(None, description="Stress estimation")

    # Diagnostics
    dominant_frequency_hz: float = Field(..., description="Dominant pulse frequency from FFT")
    signal_quality: str = Field(..., description="'Good', 'Fair', or 'Poor'")
    samples_used: int = Field(..., description="Number of signal samples processed")
    message: str = Field(default="", description="Additional information or warnings")


class ErrorResponse(BaseModel):
    """Standard error response."""
    success: bool = False
    error: str
    message: str
