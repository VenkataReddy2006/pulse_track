# PulseTrack — Architecture Documentation

## System Overview

PulseTrack is a three-tier health monitoring application that uses remote Photoplethysmography (rPPG) to measure vital signs contactlessly via a smartphone camera.

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Flutter App    │────▶│  Python Backend   │     │  Node.js Backend │
│   (Presentation  │     │  (Signal          │     │  (Data &         │
│    + Capture)    │────▶│   Processing)     │     │   Authentication)│
└─────────────────┘     └──────────────────┘     └────────┬─────────┘
                                                          │
                                                          ▼
                                                 ┌──────────────────┐
                                                 │  MongoDB Atlas    │
                                                 │  (Persistence)    │
                                                 └──────────────────┘
```

---

## Component Architecture

### 1. Flutter App (Presentation + Camera Layer)

**Responsibility:** Camera capture, face detection, ROI extraction, UI rendering, and state management. The Flutter app does NOT perform scientific signal processing — it delegates that to the Python backend.

#### Entry Point

```
main.dart
├── dotenv.load()          # Load API keys from .env
├── Firebase.initializeApp()
└── MultiProvider
    ├── AuthProvider        # Auth state + user profile
    └── HealthProvider      # Health records + latest vitals
        └── PulseTrackApp → SplashScreen → MainNavScreen
```

#### Models Layer

```
lib/models/
├── bpm_record.dart        # BpmRecord: BPM, HRV, SDNN, stress, SpO2,
│                          #   BP, confidence, AI advice, timestamps
│                          #   Supports JSON packing for backward compat
└── user_model.dart        # UserModel: profile, goals, streaks, 2FA
```

**BpmRecord fields:**
| Field | Type | Source |
|-------|------|--------|
| `bpm` | `int` | FFT analysis (Python backend) |
| `hrv` | `double?` | RMSSD from R-R intervals |
| `sdnn` | `double?` | Standard deviation of NN intervals |
| `stressLevel` | `String?` | "Relaxed" / "Mild Stress" / "High Stress" |
| `confidenceScore` | `double?` | SNR-based signal quality (0.0–1.0) |
| `spo2` | `int?` | Ratio-of-ratios estimation (non-medical) |
| `systolic` / `diastolic` | `int?` | BPM+HRV correlation model (non-medical) |
| `isEstimated` | `bool` | True = camera-based estimate |
| `aiInsight` / `aiTips` / `aiWatchFor` | `String?` / `List<String>?` | Gemini AI analysis |

#### Services Layer

```
lib/services/
├── rppg_service.dart          # Signal buffer + analysis orchestrator
│   ├── addSignal(r, g, b)     # Collect RGB from camera frames
│   ├── analyzeSignals()       # → Calls Python backend
│   └── _onDeviceAnalysis()    # Fallback: peak detection (no Random)
│
├── rppg_backend_service.dart  # HTTP client for Python backend
│   ├── analyzeSignals()       # POST /api/rppg/analyze
│   └── isAvailable()          # GET /api/rppg/health
│
├── ai_advice_service.dart     # Gemini AI integration
│   ├── chatWithAi()           # Multi-turn conversation
│   ├── getAdvice()            # Structured JSON health advice
│   └── _offlineChat()         # Rule-based fallback
│
└── api_service.dart           # Node.js backend HTTP client
    ├── login() / register()   # Authentication
    ├── saveBpm() / getHistory()  # Health record CRUD
    ├── getLocalHistory()      # SharedPreferences cache
    └── uploadProfileImage()   # Multipart upload
```

**Data Flow — Scan Lifecycle:**

```
1. ScanScreen._initializeCamera()
       │
2. Camera frames → _processCameraImage()
       │
3. ML Kit FaceDetector → Face bounding box
       │
4. _extractRppgData() → YUV→RGB conversion → ROI averaging
       │
5. RppgService.addSignal(r, g, b) → Buffer (max 450 samples)
       │
6. Progress reaches 100% → _stopScan()
       │
7. RppgService.analyzeSignals()
       ├─── Try: RppgBackendService.analyzeSignals() → Python backend
       └─── Fallback: _onDeviceAnalysis() → Peak detection in Dart
       │
8. Build BpmRecord with HRV, stress, confidence
       │
9. AiAdviceService.getAdvice() → Gemini AI insights
       │
10. HealthProvider.saveNewRecord() → Local cache + API sync
       │
11. Navigate to ResultScreen
```

#### Providers Layer

```
lib/providers/
├── auth_provider.dart     # Firebase Auth + user profile management
│   ├── login() / register() / logout()
│   ├── syncUserWithServer()
│   └── getHealthStatus()
│
└── health_provider.dart   # Health data state management
    ├── fetchHistory()     # Load from local cache, then server
    ├── addRecord()        # Optimistic update + deduplication
    └── saveNewRecord()    # Add locally + save to API
```

#### Screens Layer (26 screens)

```
lib/screens/
├── splash_screen.dart         # Animated splash with particle effects
├── onboarding_screen.dart     # First-time user walkthrough
├── main_nav_screen.dart       # Bottom navigation (Home, Scan, History, Profile)
│
├── home_screen.dart           # Dashboard: BPM gauge, HRV, stress, goals
├── scan_screen.dart           # Camera + face detection + rPPG capture
├── result_screen.dart         # Vitals display + AI advice cards
├── history_screen.dart        # Historical records + charts
│
├── ai_chat_screen.dart        # Gemini AI chatbot
├── breathing_screen.dart      # Box breathing exercises
├── sleep_screen.dart          # Sleep quality tracking
│
├── login_screen.dart          # Email/password login
├── register_screen.dart       # Account registration
├── otp_screen.dart            # OTP verification
├── forgot_password_screen.dart
├── reset_password_screen.dart
│
├── profile_screen.dart        # User profile + settings
├── edit_personal_info_screen.dart
├── change_password_screen.dart
├── privacy_security_screen.dart  # 2FA toggle, data management
├── health_goals_screen.dart   # BPM targets, daily goals
│
├── how_it_works_screen.dart   # rPPG technology explainer
├── tips_screen.dart           # Health tips
├── faqs_screen.dart           # Frequently asked questions
├── help_support_screen.dart   # Contact and support
└── video_tutorials_screen.dart
```

---

### 2. Python Backend (Signal Processing Microservice)

**Responsibility:** Scientifically validated signal processing. Receives raw RGB signals, applies DSP algorithms, returns BPM, HRV, stress, and estimated vitals.

```
python_backend/
├── app.py                 # FastAPI server
│   ├── GET  /api/rppg/health     # Health check
│   └── POST /api/rppg/analyze    # Full rPPG pipeline
│
├── signal_processing.py   # Core DSP algorithms
│   ├── butterworth_bandpass()     # 3rd-order, 0.7-4.0 Hz, filtfilt
│   ├── normalize_signal()         # Zero-mean, unit-variance
│   ├── moving_average_smooth()    # Pre-filter noise reduction
│   ├── detect_motion_artifacts()  # Windowed variance detection
│   ├── compute_signal_quality()   # SNR-based confidence (0-1)
│   ├── extract_bpm_from_fft()     # FFT → dominant frequency → BPM
│   ├── estimate_spo2()            # R/B ratio-of-ratios method
│   ├── estimate_blood_pressure()  # BPM+HRV correlation model
│   └── process_rppg_signals()     # Main pipeline orchestrator
│
├── hrv_analysis.py        # Heart Rate Variability
│   ├── detect_rr_intervals()      # Peak detection → RR intervals
│   ├── compute_rmssd()            # Root Mean Square Successive Diff
│   ├── compute_sdnn()             # Standard Deviation of NN
│   ├── compute_pnn50()            # % of successive RR > 50ms
│   ├── estimate_stress()          # Composite score (HRV+BPM)
│   └── analyze_hrv()              # Full HRV pipeline
│
├── face_detection.py      # Server-side face processing (future use)
│   ├── extract_roi_from_landmarks()  # MediaPipe FaceMesh polygons
│   ├── extract_rgb_from_frame()      # Frame → ROI → RGB averages
│   └── get_face_roi_info()           # Debug face bounding boxes
│
├── models.py              # Pydantic schemas
│   ├── RppgAnalysisRequest        # Input: RGB arrays + timestamps
│   ├── RppgAnalysisResponse       # Output: BPM, HRV, stress, etc.
│   ├── HrvMetrics                 # RMSSD, SDNN, pNN50, mean_rr
│   ├── StressAssessment           # Level, score, description
│   └── ErrorResponse              # Standard error format
│
└── requirements.txt       # fastapi, numpy, scipy, mediapipe, etc.
```

**Signal Processing Pipeline (detailed):**

```
Input: green_signals[450], red_signals[450], blue_signals[450], timestamps[450]
                    │
                    ▼
    ┌───────────────────────────────────┐
    │ Estimate sample rate from         │
    │ timestamp deltas (median Δt)      │  fs ≈ 30 Hz
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ Motion artifact detection         │
    │ Window=15, threshold=3×σ²_global  │  Reject noisy windows
    │ Require ≥40% clean frames         │
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ Moving average smoothing          │
    │ Window = 3 samples                │  Reduce HF noise
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ Normalization                     │
    │ x' = (x - μ) / σ                 │  Standardize amplitude
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ Linear detrending                 │
    │ scipy.signal.detrend(type=linear) │  Remove baseline drift
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ Butterworth bandpass filter       │
    │ Order=3, [0.7, 4.0] Hz           │  Isolate cardiac freq
    │ scipy.signal.filtfilt (zero-phase)│
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ FFT analysis                      │
    │ scipy.fft.rfft → magnitude        │  Frequency spectrum
    │ Peak in [0.7, 4.0] Hz range       │
    │ BPM = peak_freq × 60             │
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ Signal quality (SNR)              │
    │ Power_peak_band / Power_total     │  Confidence score
    │ Mapped to [0, 1]                  │
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ HRV analysis                      │
    │ find_peaks() → RR intervals       │
    │ RMSSD = √(mean(ΔRR²))           │
    │ SDNN = std(RR)                    │
    │ pNN50 = %(|ΔRR| > 50ms)         │
    │ Stress = f(RMSSD, SDNN, BPM)     │
    └───────────────────┬───────────────┘
                        ▼
    ┌───────────────────────────────────┐
    │ Estimated vitals (non-medical)    │
    │ SpO2: R = (AC_r/DC_r)/(AC_b/DC_b)│
    │       SpO2 ≈ 110 - 25R            │
    │ BP: Baseline + f(BPM, HRV)        │
    └───────────────────────────────────┘
                        │
                        ▼
    Output: { bpm, confidence, hrv, stress, spo2, bp, signal_quality }
```

---

### 3. Node.js Backend (Data & Authentication)

**Responsibility:** User authentication, health record persistence, streak tracking, and profile management.

```
backend/
├── index.js               # Express server, CORS, route mounting
├── config/
│   └── db.js              # MongoDB Atlas connection (Mongoose)
│
├── controllers/
│   ├── authController.js  # Register, login, OTP, 2FA, password reset
│   ├── bpmController.js   # Add record, get history/latest/stats
│   │                      # + streak logic (daily goal tracking)
│   └── breathingController.js  # Breathing exercise records
│
├── models/
│   ├── User.js            # name, email, password (bcrypt),
│   │                      # healthGoals, scanStreak, breathingStreak
│   ├── BpmRecord.js       # userId, bpm, status, spo2, systolic,
│   │                      # diastolic, timestamp
│   └── BreathingRecord.js # userId, duration, timestamp
│
├── routes/
│   ├── authRoutes.js      # /api/auth/*
│   ├── bpmRoutes.js       # /api/bpm/*
│   └── breathingRoutes.js # /api/breathing/*
│
├── middleware/             # Auth middleware (JWT)
├── utils/                  # Email (Brevo), helpers
└── .env                    # MONGODB_URI, JWT_SECRET, BREVO keys
```

**API Routes:**

| Route | Method | Handler | Purpose |
|-------|--------|---------|---------|
| `/api/auth/register` | POST | `authController.register` | Create account |
| `/api/auth/login` | POST | `authController.login` | Authenticate user |
| `/api/auth/send-otp` | POST | `authController.sendOTP` | Email OTP |
| `/api/auth/verify-otp` | POST | `authController.verifyOTP` | Verify email |
| `/api/auth/forgot-password` | POST | `authController.forgotPassword` | Reset flow |
| `/api/auth/reset-password` | POST | `authController.resetPassword` | Set new password |
| `/api/auth/change-password` | POST | `authController.changePassword` | Authenticated change |
| `/api/auth/toggle-2fa` | POST | `authController.toggle2FA` | Enable/disable 2FA |
| `/api/auth/update-profile` | POST | `authController.updateProfile` | Edit name/DOB/gender |
| `/api/auth/update-profile-image` | POST | `authController.uploadImage` | Profile photo upload |
| `/api/auth/health-goals` | POST | `authController.updateHealthGoals` | Set daily targets |
| `/api/auth/health-status/:userId` | GET | `authController.getHealthStatus` | Daily progress |
| `/api/bpm/add` | POST | `bpmController.addRecord` | Save scan + streak |
| `/api/bpm/history/:userId` | GET | `bpmController.getHistory` | All records (sorted) |
| `/api/bpm/latest/:userId` | GET | `bpmController.getLatest` | Most recent record |
| `/api/bpm/stats/:userId` | GET | `bpmController.getStats` | Avg/Max/Min BPM |
| `/api/breathing/add` | POST | `breathingController.addRecord` | Save exercise |

---

## Data Flow Diagrams

### Scan → Save → Display

```
User taps "Start Scan"
        │
        ▼
┌─────────────────────────────┐
│     ScanScreen (Flutter)     │
│  Camera → Face Detection     │
│  → ROI → RGB Buffer (15s)   │
└──────────────┬──────────────┘
               │ analyzeSignals()
               ▼
┌─────────────────────────────┐      ┌───────────────────────┐
│   RppgBackendService        │─────▶│  Python FastAPI        │
│   POST /api/rppg/analyze    │◀─────│  BPM + HRV + Stress   │
└──────────────┬──────────────┘      └───────────────────────┘
               │ RppgResult
               ▼
┌─────────────────────────────┐      ┌───────────────────────┐
│   AiAdviceService           │─────▶│  Gemini API           │
│   getAdvice(bpm, status)    │◀─────│  Personalized insight │
└──────────────┬──────────────┘      └───────────────────────┘
               │ BpmRecord
               ▼
┌─────────────────────────────┐      ┌───────────────────────┐
│   HealthProvider            │      │  SharedPreferences    │
│   saveNewRecord()           │─────▶│  (Local cache)        │
│   addRecord() → UI update   │      └───────────────────────┘
└──────────────┬──────────────┘
               │                     ┌───────────────────────┐
               └────────────────────▶│  Node.js Backend      │
                                     │  POST /api/bpm/add    │
                                     │  → MongoDB Atlas      │
                                     └───────────────────────┘
               │
               ▼
┌─────────────────────────────┐
│   ResultScreen (Flutter)     │
│   BPM + SpO2 + BP + AI      │
│   (non-medical labels)       │
└─────────────────────────────┘
```

### Authentication Flow

```
┌──────────┐    Register     ┌──────────────┐    Save User    ┌────────────┐
│  Flutter  │───────────────▶│  Node.js API  │──────────────▶│  MongoDB    │
│  App      │                │  /auth/register│               │  Users      │
└──────────┘                └──────┬───────┘                └────────────┘
     │                             │
     │     Send OTP Email          │    ┌──────────────┐
     │◀────────────────────────────┼───▶│  Brevo Email  │
     │                             │    └──────────────┘
     │                             │
     │     Verify OTP              │
     │────────────────────────────▶│
     │                             │
     │     Login (email+pass)      │
     │────────────────────────────▶│    ┌──────────────┐
     │     JWT + User JSON         │───▶│  bcrypt verify│
     │◀────────────────────────────│    └──────────────┘
     │                             │
     │     Firebase Auth (Google)  │
     │────────────────────────────▶│
```

---

## Security Architecture

```
┌──────────────────────────────────────────────────────┐
│                   SECRETS MANAGEMENT                  │
│                                                       │
│  Flutter App:                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │  .env (gitignored)                              │  │
│  │  ├── GEMINI_API_KEY=...                         │  │
│  │  └── RPPG_BACKEND_URL=...                       │  │
│  │                                                  │  │
│  │  Loaded via flutter_dotenv at app startup        │  │
│  │  Accessed: dotenv.env['GEMINI_API_KEY']          │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  Node.js Backend:                                     │
│  ┌─────────────────────────────────────────────────┐  │
│  │  backend/.env (gitignored)                      │  │
│  │  ├── MONGODB_URI=...                            │  │
│  │  ├── JWT_SECRET=...                             │  │
│  │  ├── BREVO_API_KEY=...                          │  │
│  │  └── PORT=5000                                  │  │
│  │                                                  │  │
│  │  Loaded via dotenv at server startup             │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  .gitignore entries:                                  │
│  ├── .env                                             │
│  ├── *.env                                            │
│  ├── backend/.gitignore                               │
│  └── python_backend/__pycache__/                      │
└──────────────────────────────────────────────────────┘
```

---

## Deployment Architecture

```
┌──────────────────┐          ┌─────────────────────────────┐
│  Android / iOS    │   HTTPS  │   Render.com                │
│  Flutter App      │─────────▶│   Node.js Backend           │
│                   │          │   pulse-track-backend.onrender│
└──────────────────┘          └─────────────┬───────────────┘
        │                                    │
        │ HTTP (local/cloud)                 │
        ▼                                    ▼
┌──────────────────┐          ┌─────────────────────────────┐
│  Python Backend   │          │   MongoDB Atlas              │
│  (localhost:8000   │          │   Cluster098                │
│   or cloud deploy) │          │                             │
└──────────────────┘          └─────────────────────────────┘
```

**Production deployment options for Python backend:**
- Render (free tier with Docker)
- Railway
- AWS Lambda (with Mangum adapter)
- Google Cloud Run

---

## Technology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Signal processing language | Python | SciPy/NumPy ecosystem is the gold standard for DSP |
| Flutter ↔ Python communication | HTTP/REST | Simple, debuggable, works on all platforms |
| On-device face detection | ML Kit | Native performance, no network latency, offline capable |
| Server-side face detection | MediaPipe | 468-point FaceMesh for precise ROI landmarks |
| HRV method | Time-domain (RMSSD/SDNN) | Most reliable for short recordings (15s) |
| BPM method | FFT peak detection | More robust than peak counting for noisy signals |
| Bandpass filter | Butterworth (order 3) | Good tradeoff between roll-off and phase linearity |
| State management | Provider | Simple, sufficient for this app's complexity |
| Secret management | flutter_dotenv | Industry standard for Flutter env vars |
