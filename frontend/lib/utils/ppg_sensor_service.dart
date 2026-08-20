import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

/// PPG Sensor Measurement Data Result
class PpgMeasurementResult {
  final int bpm;
  final double hrvSdnnMs;
  final int breathRpm;
  final double measuredInhaleSec;
  final double measuredExhaleSec;
  final String signalQuality;

  /// Set when the reading came back from the server. The server owns this
  /// number, so when it is present the local formula below must not be used —
  /// two answers on one screen is worse than either answer alone.
  final double? serverConditionScore;

  PpgMeasurementResult({
    required this.bpm,
    required this.hrvSdnnMs,
    required this.breathRpm,
    required this.measuredInhaleSec,
    required this.measuredExhaleSec,
    this.signalQuality = 'Good',
    this.serverConditionScore,
  });

  /// Builds a result from an analysed server reading.
  ///
  /// Breathing pace is still derived here because the server does not return
  /// it — it is a presentation detail, not a measurement.
  factory PpgMeasurementResult.fromServer({
    required double hr,
    required double hrv,
    required double? conditionScore,
    required String quality,
  }) {
    final bpm = hr.round();
    final breathRpm = (bpm / 5.2).round().clamp(10, 20);
    return PpgMeasurementResult(
      bpm: bpm,
      hrvSdnnMs: double.parse(hrv.toStringAsFixed(1)),
      breathRpm: breathRpm,
      measuredInhaleSec:
          double.parse((60.0 / breathRpm * 0.42).clamp(1.8, 4.5).toStringAsFixed(1)),
      measuredExhaleSec:
          double.parse((60.0 / breathRpm * 0.58).clamp(2.0, 6.0).toStringAsFixed(1)),
      signalQuality: quality,
      serverConditionScore: conditionScore,
    );
  }

  /// Prefers the server's number. The local formula is a fallback for the web
  /// simulation samples, which never reach the server.
  int get conditionScore =>
      serverConditionScore?.round() ??
      (hrvSdnnMs * 1.4 + 40).clamp(50.0, 96.0).round();


  factory PpgMeasurementResult.defaultSample() {
    return PpgMeasurementResult(
      bpm: 76,
      hrvSdnnMs: 28.5,
      breathRpm: 14,
      measuredInhaleSec: 2.2,
      measuredExhaleSec: 2.2,
      signalQuality: 'Good',
    );
  }

  /// 5대 카테고리 시뮬레이션용 랜덤 결과 생성기 (웹/노트북 테스트용)
  factory PpgMeasurementResult.randomSample() {
    final rng = math.Random();
    final categoryIndex = rng.nextInt(5); // 0 ~ 4 (5대 카테고리 랜덤 생성)

    switch (categoryIndex) {
      case 0:
        // 1. 긴급 대처 (BPM 98~106, HRV 16~22ms) -> 생리학적 한숨
        return PpgMeasurementResult(
          bpm: 98 + rng.nextInt(9),
          hrvSdnnMs: 16.0 + rng.nextDouble() * 6.0,
          breathRpm: 22,
          measuredInhaleSec: 1.8,
          measuredExhaleSec: 2.0,
          signalQuality: 'Good',
        );
      case 1:
        // 2. 심리 이완 (BPM 85~92, HRV 18~28ms) -> 4-7-8 호흡
        return PpgMeasurementResult(
          bpm: 85 + rng.nextInt(8),
          hrvSdnnMs: 18.0 + rng.nextDouble() * 10.0,
          breathRpm: 16,
          measuredInhaleSec: 2.0,
          measuredExhaleSec: 2.2,
          signalQuality: 'Good',
        );
      case 2:
        // 3. 집중·몰입 (BPM 72~82, HRV 34~48ms) -> 4-4-4-4 박스 호흡
        return PpgMeasurementResult(
          bpm: 72 + rng.nextInt(11),
          hrvSdnnMs: 34.0 + rng.nextDouble() * 14.0,
          breathRpm: 14,
          measuredInhaleSec: 2.2,
          measuredExhaleSec: 2.2,
          signalQuality: 'Good',
        );
      case 3:
        // 4. 회복·밸런스 (BPM 64~72, HRV 58~72ms) -> 5.5-5.5 공진 호흡
        return PpgMeasurementResult(
          bpm: 64 + rng.nextInt(9),
          hrvSdnnMs: 58.0 + rng.nextDouble() * 14.0,
          breathRpm: 12,
          measuredInhaleSec: 2.6,
          measuredExhaleSec: 2.6,
          signalQuality: 'Good',
        );
      case 4:
      default:
        // 5. 에너지 각성 (BPM 52~58, HRV 42~58ms) -> 4-1-2-1 각성 호흡
        return PpgMeasurementResult(
          bpm: 52 + rng.nextInt(7),
          hrvSdnnMs: 42.0 + rng.nextDouble() * 16.0,
          breathRpm: 10,
          measuredInhaleSec: 2.8,
          measuredExhaleSec: 2.2,
          signalQuality: 'Good',
        );
    }
  }
}

/// PpgSensorService (카메라 PPG 센싱 및 실시간 붉은빛 명도 분석 서비스)
class PpgSensorService {
  static PpgMeasurementResult? latestResult;
  CameraController? _cameraController;
  bool _isInitializing = false;
  bool _isCameraAvailable = false;
  bool isFingerDetected = false;
  bool _isDisposed = false;

  double debugAvgY = 0.0;
  double debugAvgU = 0.0;
  double debugAvgV = 0.0;
  double debugDiff = 0.0;

  final StreamController<double> _ppgValueController =
      StreamController<double>.broadcast();
  final StreamController<bool> _fingerStateController =
      StreamController<bool>.broadcast();

  Stream<double> get ppgStream => _ppgValueController.stream;
  Stream<bool> get fingerStateStream => _fingerStateController.stream;

  double _prevY = 0.0;
  double _prevPrevY = 0.0;
  final List<double> _yHistory = [];

  final List<DateTime> _peakTimestamps = [];
  final List<double> _rrIntervalsMs = [];
  Timer? _simulationTimer;

  /// Every avgY sample taken while a finger was on the lens, in order.
  ///
  /// This is what gets uploaded — the server derives heart rate and HRV from
  /// it. Keep it raw: no smoothing, no trimming. The server's filter expects
  /// the untouched signal, and the stored copy is what we replay later when
  /// tuning the algorithm.
  final List<double> _waveform = [];
  DateTime? _captureStartedAt;
  DateTime? _captureEndedAt;

  /// The samples to upload. Empty until a finger is detected.
  List<double> get waveform => List.unmodifiable(_waveform);

  /// Wall-clock seconds spanned by [waveform].
  int get capturedDurationSec {
    final start = _captureStartedAt;
    final end = _captureEndedAt ?? DateTime.now();
    if (start == null) return 0;
    return end.difference(start).inMilliseconds ~/ 1000;
  }

  /// Frames actually delivered per second, measured rather than assumed.
  ///
  /// The camera does not honour a requested rate — it drops frames under load
  /// and slows down in dim light. Sending a nominal 30 when the real rate was
  /// 22 would stretch every interval the server computes and skew the heart
  /// rate by the same ratio.
  int get capturedFps {
    final seconds = capturedDurationSec;
    if (seconds <= 0 || _waveform.isEmpty) return 30;
    return (_waveform.length / seconds).round().clamp(10, 240);
  }

  bool get isCameraAvailable => _isCameraAvailable;

  /// True when the camera could not be opened on a real device. The screen
  /// should say so rather than pretending a measurement is running.
  bool cameraInitFailed = false;

  Future<void> initializeCamera() async {
    _isDisposed = false;
    isFingerDetected = false;
    if (!_fingerStateController.isClosed) {
      _fingerStateController.add(false);
    }
    _peakTimestamps.clear();
    _rrIntervalsMs.clear();
    _yHistory.clear();
    _waveform.clear();
    _captureStartedAt = null;
    _captureEndedAt = null;
    _prevY = 0.0;
    _prevPrevY = 0.0;

    if (_isInitializing || _cameraController != null) return;
    _isInitializing = true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _startSimulationFallback();
        return;
      }

      final rearCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        rearCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      try {
        await _cameraController!.setFlashMode(FlashMode.torch);
      } catch (e) {
        debugPrint('Flash torch not supported on device: $e');
      }

      try {
        await _cameraController!.setExposureMode(ExposureMode.locked);
      } catch (_) {}
      try {
        await _cameraController!.setFocusMode(FocusMode.locked);
      } catch (_) {}

      _isCameraAvailable = true;
      await _cameraController!.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      // Only fake a pulse where there is no camera to begin with. On a real
      // phone this path is reached by a denied permission or a camera another
      // app is holding, and the fallback reports isFingerDetected = true with
      // invented intervals — the user would see a clean "measurement" and the
      // made-up numbers would be uploaded as a genuine reading.
      if (kIsWeb || kDebugMode) {
        _startSimulationFallback();
      } else {
        cameraInitFailed = true;
      }
    } finally {
      _isInitializing = false;
    }
  }

  int _fingerOnFrames = 0;
  int _fingerOffFrames = 0;

  /// Process individual camera frame image with Bulletproof YUV Finger Contact Detection
  void _processCameraFrame(CameraImage image) {
    if (_isDisposed || _cameraController == null) return;

    double ySum = 0;
    double uSum = 0;
    double vSum = 0;
    int sampleCount = 0;

    if (image.planes.length >= 3) {
      final yBytes = image.planes[0].bytes;
      final uBytes = image.planes[1].bytes;
      final vBytes = image.planes[2].bytes;

      final int step = math.max(1, yBytes.length ~/ 200);
      final int uStride = image.planes[1].bytesPerPixel ?? 1;
      final int vStride = image.planes[2].bytesPerPixel ?? 1;

      for (int i = 0; i < yBytes.length; i += step) {
        final y = yBytes[i].toDouble();
        final uIdx = math.min((i ~/ 4) * uStride, uBytes.length - 1);
        final vIdx = math.min((i ~/ 4) * vStride, vBytes.length - 1);

        final u = uBytes[uIdx].toDouble();
        final v = vBytes[vIdx].toDouble();

        ySum += y;
        uSum += u;
        vSum += v;
        sampleCount++;
      }
    } else if (image.planes.length == 2) {
      final yBytes = image.planes[0].bytes;
      final uvBytes = image.planes[1].bytes;
      final int step = math.max(1, yBytes.length ~/ 200);

      for (int i = 0; i < yBytes.length; i += step) {
        final y = yBytes[i].toDouble();
        final uvIdx = math.min(i, uvBytes.length - 2);
        final u = uvBytes[uvIdx].toDouble();
        final v = uvBytes[uvIdx + 1].toDouble();

        ySum += y;
        uSum += u;
        vSum += v;
        sampleCount++;
      }
    } else if (image.planes.isNotEmpty) {
      final yBytes = image.planes[0].bytes;
      final step = math.max(1, yBytes.length ~/ 200);
      for (int i = 0; i < yBytes.length; i += step) {
        ySum += yBytes[i].toDouble();
        sampleCount++;
      }
      uSum = 128.0 * sampleCount;
      vSum = 128.0 * sampleCount;
    }

    if (sampleCount == 0) return;

    final avgY = ySum / sampleCount;
    final avgU = uSum / sampleCount;
    final avgV = vSum / sampleCount;
    final chromDiff = avgV - avgU;

    debugAvgY = avgY;
    debugAvgU = avgU;
    debugAvgV = avgV;
    debugDiff = chromDiff;

    // Bulletproof Finger Contact Condition across all Android cameras:
    // Finger covering torch LED yields strong V chrominance over U without room light false positives
    final detected = (chromDiff > 18.0 && avgV > 130.0) || kIsWeb;

    if (detected) {
      _fingerOnFrames++;
      _fingerOffFrames = 0;
    } else {
      _fingerOffFrames++;
      _fingerOnFrames = 0;
    }

    bool nextState = isFingerDetected;
    if (_fingerOnFrames >= 3) {
      nextState = true;
    } else if (_fingerOffFrames >= 3) {
      nextState = false;
    }

    if (nextState != isFingerDetected) {
      isFingerDetected = nextState;
      if (!_fingerStateController.isClosed && !_isDisposed) {
        _fingerStateController.add(isFingerDetected);
      }
    }

    // Convert YUV to true RGB Red channel intensity (Y + 1.402 * (V - 128))
    // Invert signal (255 - red) so cardiac blood surge corresponds to positive pulse peak
    final redValue = (255.0 - (avgY + 1.402 * (avgV - 128.0))).clamp(0.0, 255.0);

    if (isFingerDetected && !_ppgValueController.isClosed && !_isDisposed) {
      final now = DateTime.now();
      _ppgValueController.add(redValue);

      _captureStartedAt ??= now;
      _captureEndedAt = now;
      // The server rejects anything past 30,000 samples, so stop growing at the
      // cap instead of building a request that is guaranteed to be refused.
      if (_waveform.length < 30000) {
        _waveform.add(redValue);
      }

      // Track moving average of redValue
      _yHistory.add(redValue);
      if (_yHistory.length > 20) _yHistory.removeAt(0);
      final movingAvgY =
          _yHistory.reduce((a, b) => a + b) / _yHistory.length;

      // Local maximum peak detection (rising -> falling transition) above moving average
      final bool isPeak =
          _prevY > _prevPrevY && _prevY > avgY && _prevY > (movingAvgY + 0.08);

      if (_peakTimestamps.isNotEmpty) {
        final diffMs = now.difference(_peakTimestamps.last).inMilliseconds;
        if (diffMs > 500 && diffMs < 1200 && isPeak) {
          _peakTimestamps.add(now);
          _rrIntervalsMs.add(diffMs.toDouble());
        } else if (diffMs >= 1200) {
          // Update reference timestamp when finger released for >= 1200ms
          _peakTimestamps.add(now);
        }
      } else if (isPeak) {
        _peakTimestamps.add(now);
      }

      _prevPrevY = _prevY;
      _prevY = avgY;
    }
  }

  void _startSimulationFallback() {
    _isCameraAvailable = false;
    isFingerDetected = true;
    if (!_fingerStateController.isClosed && !_isDisposed) {
      _fingerStateController.add(true);
    }
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      if (_peakTimestamps.isNotEmpty) {
        final diffMs = now.difference(_peakTimestamps.last).inMilliseconds;
        if (diffMs >= 550) {
          _peakTimestamps.add(now);
          _rrIntervalsMs.add(550.0 + (math.Random().nextDouble() * 180.0));
        }
      } else {
        _peakTimestamps.add(now);
      }
      if (!_ppgValueController.isClosed && !_isDisposed) {
        _ppgValueController.add(120.0 + math.sin(now.millisecondsSinceEpoch / 200.0) * 15.0);
      }
    });
  }

  PpgMeasurementResult computeResults() {
    int bpm = 75;
    double hrvSdnn = 28.5;
    int breathRpm = 14;

    if (_rrIntervalsMs.length >= 3) {
      final avgIntervalMs =
          _rrIntervalsMs.reduce((a, b) => a + b) / _rrIntervalsMs.length;
      bpm = (60000 / avgIntervalMs).round().clamp(55, 130);

      final mean = avgIntervalMs;
      final variance = _rrIntervalsMs
              .map((x) => math.pow(x - mean, 2))
              .reduce((a, b) => a + b) /
          _rrIntervalsMs.length;
      hrvSdnn = math.sqrt(variance).clamp(12.0, 65.0);
      breathRpm = (bpm / 5.2).round().clamp(10, 20);
    }

    final inhaleSec = (60.0 / breathRpm * 0.42).clamp(1.8, 4.5);
    final exhaleSec = (60.0 / breathRpm * 0.58).clamp(2.0, 6.0);

    final result = PpgMeasurementResult(
      bpm: bpm,
      hrvSdnnMs: double.parse(hrvSdnn.toStringAsFixed(1)),
      breathRpm: breathRpm,
      measuredInhaleSec: double.parse(inhaleSec.toStringAsFixed(1)),
      measuredExhaleSec: double.parse(exhaleSec.toStringAsFixed(1)),
      signalQuality: _rrIntervalsMs.length >= 3 ? 'Good' : 'Measuring',
    );

    latestResult = result;
    return result;
  }

  Future<void> stopCamera() async {
    _isDisposed = true;
    _simulationTimer?.cancel();
    if (_cameraController != null) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (_) {}
      await _cameraController!.dispose();
      _cameraController = null;
    }
    isFingerDetected = false;
    if (!_fingerStateController.isClosed) {
      _fingerStateController.add(false);
    }
  }

  void dispose() {
    stopCamera();
    if (!_ppgValueController.isClosed) _ppgValueController.close();
    if (!_fingerStateController.isClosed) _fingerStateController.close();
  }
}
