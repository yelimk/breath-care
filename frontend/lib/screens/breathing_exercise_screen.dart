import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/responsive.dart';
import '../utils/breathing_routine_model.dart';
import 'breathing_completion_screen.dart';

/// Guided Breathing Exercise Screen with Smooth Stable Cycle Animation & Adaptive Entrainment
class BreathingExerciseScreen extends StatefulWidget {
  final String title;
  final int totalCycles;
  final int targetDurationMinutes;
  final BreathingRoutineModel? routineModel;
  final double? initialInhaleSec;
  final double? initialExhaleSec;
  final String bgImagePath;
  final double? targetInhaleSec;
  final double? targetInhale2Sec;
  final double? targetHoldSec;
  final double? targetExhaleSec;
  final double? targetHold2Sec;
  final bool isAdaptiveRamp;
  final String? targetScheduleId;

  const BreathingExerciseScreen({
    super.key,
    required this.title,
    this.totalCycles = 20,
    this.targetDurationMinutes = 3,
    this.routineModel,
    this.initialInhaleSec,
    this.initialExhaleSec,
    this.bgImagePath = 'assets/images/bg_breath_box_4444.png',
    this.targetInhaleSec,
    this.targetInhale2Sec,
    this.targetHoldSec,
    this.targetExhaleSec,
    this.targetHold2Sec,
    this.isAdaptiveRamp = false,
    this.targetScheduleId,
  });

  @override
  State<BreathingExerciseScreen> createState() =>
      _BreathingExerciseScreenState();
}

class _BreathingExerciseScreenState extends State<BreathingExerciseScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Stopwatch _cycleStopwatch;
  Timer? _durationTimer;

  int elapsedSeconds = 0;
  int currentCycle = 1;
  bool isPlaying = true;
  int averageHrvBpmChange = -8;

  // Audio Player & Mute State
  AudioPlayer? _audioPlayer;
  bool _isMuted = false;

  // Stable cycle timings locked during active cycle pass (prevents mid-cycle path shifting/jumping)
  late double _activeInhaleSec;
  late double _activeInhale2Sec;
  late double _activeHoldSec;
  late double _activeExhaleSec;
  late double _activeHold2Sec;

  static const double _adaptiveRampSeconds = 90.0;

  double _overlayOpacity = 1.0;
  Timer? _overlayTimer;

  // Target timing specs based on routine
  double get _targetInhale {
    if (widget.targetInhaleSec != null) return widget.targetInhaleSec!;
    if (widget.routineModel != null) return widget.routineModel!.targetInhale;
    if (widget.title.contains('한숨')) return 2.0;
    if (widget.title.contains('5-5') || widget.title.contains('5.5') || widget.title.contains('공진')) return 5.0;
    if (widget.title.contains('4-4-4-4') || widget.title.contains('박스')) return 4.0;
    return 4.0;
  }

  double get _targetInhale2 {
    if (widget.targetInhale2Sec != null) return widget.targetInhale2Sec!;
    if (widget.title.contains('한숨')) return 1.0;
    return 0.0;
  }

  double get _targetHold {
    if (widget.targetHoldSec != null) return widget.targetHoldSec!;
    if (widget.routineModel != null) return widget.routineModel!.targetHold1;
    if (widget.title.contains('한숨') || widget.title.contains('5-5') || widget.title.contains('5.5') || widget.title.contains('공진') || widget.title.contains('4-6')) return 0.0;
    if (widget.title.contains('4-4-4-4')) return 4.0;
    if (widget.title.contains('4-2-4-2') || widget.title.contains('세미')) return 2.0;
    return 7.0;
  }

  double get _targetExhale {
    if (widget.targetExhaleSec != null) return widget.targetExhaleSec!;
    if (widget.routineModel != null) return widget.routineModel!.targetExhale;
    if (widget.title.contains('한숨')) return 6.0;
    if (widget.title.contains('5-5') || widget.title.contains('5.5') || widget.title.contains('공진')) return 5.0;
    if (widget.title.contains('4-4-4-4') || widget.title.contains('4-2-4-2') || widget.title.contains('세미')) return 4.0;
    if (widget.title.contains('4-6')) return 6.0;
    return 8.0;
  }

  double get _targetHold2 {
    if (widget.targetHold2Sec != null) return widget.targetHold2Sec!;
    if (widget.routineModel != null) return widget.routineModel!.targetHold2;
    if (widget.title.contains('4-4-4-4')) return 4.0;
    if (widget.title.contains('4-2-4-2') || widget.title.contains('세미')) return 2.0;
    if (widget.title.contains('4-1-2-1') || widget.title.contains('각성')) return 1.0;
    return 0.0;
  }

  int _lastCycleElapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _cycleStopwatch = Stopwatch()..start();
    _updateActiveCycleTimings();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _startTimer();
    _initAudioPlayer();

    // 5초간 유지 후 1초간 부드럽게 스르륵 투명해져 사라지는 Fade-Out 팝업 오버레이
    if (widget.isAdaptiveRamp) {
      _overlayTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() {
          _overlayOpacity = 0.0;
        });
      });
    }
  }

  void _initAudioPlayer() async {
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.loop);

      String soundAsset = 'audio/singing_bowl.mp3';
      final title = widget.title;

      if (title.contains('공진') || title.contains('5-5') || title.contains('5.5') || title.contains('회복') || title.contains('리프레시')) {
        soundAsset = 'audio/ocean_528hz.mp3';
      } else if (title.contains('박스') || title.contains('4-4-4-4') || title.contains('집중') || title.contains('몰입')) {
        soundAsset = 'audio/focus_rain.mp3';
      } else if (title.contains('각성') || title.contains('4-1-2-1') || title.contains('에너지') || title.contains('모닝')) {
        soundAsset = 'audio/morning_refresh.mp3';
      } else {
        // 생리학적 한숨, 4-7-8 호흡, 심리 이완, 숙면 등
        soundAsset = 'audio/singing_bowl.mp3';
      }

      await _audioPlayer!.play(AssetSource(soundAsset));
    } catch (e) {
      debugPrint('Audio play fallback error: $e');
      try {
        await _audioPlayer?.play(AssetSource('audio/singing_bowl.mp3'));
      } catch (err) {
        debugPrint('Fallback audio failed: $err');
      }
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _audioPlayer?.setVolume(0.0);
      } else {
        _audioPlayer?.setVolume(1.0);
      }
    });
  }

  /// Lock active cycle timing (Fixed for Breathing Management vs Adaptive Ramp for Camera Measurement)
  void _updateActiveCycleTimings() {
    if (!widget.isAdaptiveRamp || widget.initialInhaleSec == null) {
      // 1. 호흡 관리 화면에서 직접 진입 시: 처음 0초부터 100% 고정 정석 템포
      _activeInhaleSec = _targetInhale;
      _activeInhale2Sec = _targetInhale2;
      _activeHoldSec = _targetHold;
      _activeExhaleSec = _targetExhale;
      _activeHold2Sec = _targetHold2;
    } else {
      // 2. 카메라 측정 결과 화면 추천으로 진입 시 (isAdaptiveRamp: true): 내 측정 호흡에서 90초간 부드럽게 주기 단위 점진 유도 (Cycle-Locked Ramp)
      final ramp = (elapsedSeconds / _adaptiveRampSeconds).clamp(0.0, 1.0);
      final initInhale = widget.initialInhaleSec!;
      final initExhale = widget.initialExhaleSec ?? widget.initialInhaleSec!;
      _activeInhaleSec = initInhale + (_targetInhale - initInhale) * ramp;
      _activeInhale2Sec = _targetInhale2 == 0.0 ? 0.0 : (0.0 + (_targetInhale2 - 0.0) * ramp);
      _activeHoldSec = _targetHold == 0.0 ? 0.0 : (0.0 + (_targetHold - 0.0) * ramp);
      _activeExhaleSec = initExhale + (_targetExhale - initExhale) * ramp;
      _activeHold2Sec = _targetHold2 == 0.0 ? 0.0 : (0.0 + (_targetHold2 - 0.0) * ramp);
    }
  }

  void _checkCycleRollover() {
    final activeCycleSec = _activeInhaleSec + _activeInhale2Sec + _activeHoldSec + _activeExhaleSec + _activeHold2Sec;
    final activeCycleMs = (activeCycleSec * 1000).round();
    if (activeCycleMs <= 0) return;

    final currentElapsedMs = _cycleStopwatch.elapsedMilliseconds;
    final cycleDeltaMs = currentElapsedMs - _lastCycleElapsedMs;

    if (cycleDeltaMs >= activeCycleMs) {
      _lastCycleElapsedMs += activeCycleMs;
      if (currentCycle < widget.totalCycles) {
        currentCycle++;
      }
      // Lock next cycle's ramped timings ONCE at the start of the new cycle!
      _updateActiveCycleTimings();
    }
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (isPlaying) {
        setState(() {
          elapsedSeconds++;
        });
      }
    });
  }

  void _finishExercise() {
    _durationTimer?.cancel();
    _overlayTimer?.cancel();
    _cycleStopwatch.stop();
    _animController.stop();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => BreathingCompletionScreen(
          title: widget.title,
          bgImagePath: widget.bgImagePath,
          durationString: _formattedTime,
          cycleCount: currentCycle,
          hrvChange: '$averageHrvBpmChange bpm',
          targetScheduleId: widget.targetScheduleId,
        ),
      ),
    );
  }

  void _togglePlayPause() {
    setState(() {
      isPlaying = !isPlaying;
      if (isPlaying) {
        _cycleStopwatch.start();
        _animController.repeat();
        if (!_isMuted) _audioPlayer?.resume();
      } else {
        _cycleStopwatch.stop();
        _animController.stop();
        _audioPlayer?.pause();
      }
    });
  }

  void _restartExercise() {
    setState(() {
      elapsedSeconds = 0;
      currentCycle = 1;
      isPlaying = true;
      _lastCycleElapsedMs = 0;
      _updateActiveCycleTimings();
      _overlayOpacity = widget.isAdaptiveRamp ? 1.0 : 0.0;
    });
    if (widget.isAdaptiveRamp) {
      _overlayTimer?.cancel();
      _overlayTimer = Timer(const Duration(milliseconds: 2800), () {
        if (!mounted) return;
        setState(() {
          _overlayOpacity = 0.0;
        });
      });
    }
    _cycleStopwatch.reset();
    _cycleStopwatch.start();
    _animController.repeat();
    if (!_isMuted) _audioPlayer?.resume();
  }

  void _showRestartDialog() {
    final wasPlayingBeforeModal = isPlaying;
    setState(() {
      isPlaying = false;
    });
    _cycleStopwatch.stop();
    _animController.stop();
    _audioPlayer?.pause();

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(90),
      builder: (dialogContext) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: const Alignment(0, -0.2),
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: const Color(0xFF27282C),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(100),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top 3D Image Icon matching screenshot
                Image.asset(
                  'assets/images/ic_restart_modal.png',
                  width: 76,
                  height: 76,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        color: Color(0xFF35363B),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.published_with_changes_rounded,
                        color: AppColors.lightMint,
                        size: 40,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Main Title: 처음부터 다시 시작할까요?
                const Text(
                  '처음부터 다시 시작할까요?',
                  style: TextStyle(
                    fontFamily: AppFonts.pretendard,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: AppColors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle Description: 지금까지의 Ritual 기록은 저장되지 않아요.
                Text(
                  '지금까지의 Ritual 기록은\n저장되지 않아요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.pretendard,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.white.withAlpha(125),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons Row: 취소하기 vs 다시하기
                Row(
                  children: [
                    // 1. 취소하기 Button
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          if (wasPlayingBeforeModal) {
                            setState(() {
                              isPlaying = true;
                            });
                            _cycleStopwatch.start();
                            _animController.repeat();
                            if (!_isMuted) _audioPlayer?.resume();
                          }
                        },
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1D20),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '취소하기',
                            style: TextStyle(
                              fontFamily: AppFonts.pretendard,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w400,
                              color: AppColors.white.withAlpha(110),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 2. 다시하기 Button
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _restartExercise();
                        },
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2FBB1),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '다시하기',
                            style: TextStyle(
                              fontFamily: AppFonts.pretendard,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF1C1D20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

  String get _formattedTime {
    final mins = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  double get _cycleProgress {
    _checkCycleRollover();
    final activeCycleSec = _activeInhaleSec + _activeInhale2Sec + _activeHoldSec + _activeExhaleSec + _activeHold2Sec;
    if (activeCycleSec <= 0) return 0.0;
    final activeCycleMs = (activeCycleSec * 1000).round();
    if (activeCycleMs <= 0) return 0.0;

    final cycleMs = (_cycleStopwatch.elapsedMilliseconds - _lastCycleElapsedMs).clamp(0, activeCycleMs);
    return cycleMs / activeCycleMs;
  }

  String get _currentPhaseLabel {
    final totalSec = _activeInhaleSec + _activeInhale2Sec + _activeHoldSec + _activeExhaleSec + _activeHold2Sec;
    if (totalSec <= 0) return '들숨';

    final totalMs = (totalSec * 1000).round();
    if (totalMs <= 0) return '들숨';

    final cycleMs = (_cycleStopwatch.elapsedMilliseconds - _lastCycleElapsedMs).clamp(0, totalMs);
    final inhale1Ms = (_activeInhaleSec * 1000).round();
    final inhale2Ms = (_activeInhale2Sec * 1000).round();
    final hold1Ms = (_activeHoldSec * 1000).round();
    final exhaleMs = (_activeExhaleSec * 1000).round();

    if (_activeInhale2Sec > 0.01) {
      if (cycleMs < inhale1Ms) {
        return '들숨';
      } else if (cycleMs < (inhale1Ms + inhale2Ms)) {
        return '추가들숨';
      } else {
        return '날숨';
      }
    }

    if (_activeHoldSec <= 0.1 && _activeHold2Sec <= 0.1) {
      return cycleMs < inhale1Ms ? '들숨' : '날숨';
    }

    if (cycleMs < inhale1Ms) {
      return '들숨';
    } else if (cycleMs < (inhale1Ms + hold1Ms)) {
      return '숨 참기';
    } else if (cycleMs < (inhale1Ms + hold1Ms + exhaleMs)) {
      return '날숨';
    } else {
      return '숨 참기';
    }
  }

  String get _guideSubtext {
    if (widget.isAdaptiveRamp && elapsedSeconds < 90) {
      return '회원님의 컨디션에 맞춰 1분 30초간 조율 중이에요';
    } else {
      return '안정적인 ${widget.title}이 진행 중이에요';
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _overlayTimer?.cancel();
    _cycleStopwatch.stop();
    _animController.dispose();
    try {
      _audioPlayer?.stop();
      _audioPlayer?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.asset(
            widget.bgImagePath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2C3440), Color(0xFF1E2228)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              );
            },
          ),

          // Dark Overlay for readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withAlpha(120),
                  Colors.black.withAlpha(170),
                  Colors.black.withAlpha(220),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          SafeArea(
            child: ResponsiveContainer(
              maxWidth: 600,
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 16),

                  Expanded(
                    child: Stack(
                      children: [
                        // Wave, Dotted Lines & Glowing Ball Painter (100% Synced)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _animController,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: _BreathingWavePainter(
                                  progress: _cycleProgress,
                                  phaseLabel: _currentPhaseLabel,
                                  inhaleSec: _activeInhaleSec,
                                  inhale2Sec: _activeInhale2Sec,
                                  holdSec: _activeHoldSec,
                                  exhaleSec: _activeExhaleSec,
                                  hold2Sec: _activeHold2Sec,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _guideSubtext,
                      key: ValueKey<String>(_guideSubtext),
                      style: const TextStyle(
                        fontFamily: AppFonts.pretendard,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFFB0B4BC),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 18),

                  Text(
                    _formattedTime,
                    style: GoogleFonts.outfit(
                      fontSize: 38,
                      fontWeight: FontWeight.w400,
                      color: AppColors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 22),

                  _buildBottomToolbar(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // 3초 후 부드럽게 스르륵 사라지는(Fade-Out) 측정 수치 맞춤 조율 브리핑 오버레이 팝업
          if (widget.isAdaptiveRamp)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _overlayOpacity == 0.0,
                child: AnimatedOpacity(
                  opacity: _overlayOpacity,
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOut,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24.0),
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(205),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.lightMint.withAlpha(120),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.lightMint.withAlpha(50),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '나만의 맞춤 호흡 시작',
                            style: TextStyle(
                              fontFamily: AppFonts.pretendard,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: AppColors.lightMint,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '회원님의 측정 호흡(들숨 ${widget.initialInhaleSec?.toStringAsFixed(1) ?? "2.8"}s / 날숨 ${widget.initialExhaleSec?.toStringAsFixed(1) ?? "3.4"}s)을 감지했습니다.\n1분 30초간 ${widget.title} 목표 템포로 부드럽게 맞춤 조율됩니다.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppFonts.pretendard,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400,
                              color: AppColors.white,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.white,
              size: 20,
            ),
          ),
        ),

        Text(
          widget.title,
          style: const TextStyle(
            fontFamily: AppFonts.pretendard,
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: AppColors.white,
            letterSpacing: 0.2,
          ),
        ),

        Row(
          children: [
            GestureDetector(
              onTap: _toggleMute,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: _isMuted ? AppColors.slateGray : AppColors.lightMint,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showRestartDialog,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomToolbar() {
    return SizedBox(
      height: 64,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(60),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha(80),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.white,
                  size: 32,
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _finishExercise,
              child: const Padding(
                padding: EdgeInsets.only(right: 12.0),
                child: Text(
                  '종료하기',
                  style: TextStyle(
                    fontFamily: AppFonts.pretendard,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



/// 1-Minute Scientific Adaptive Wave & Glowing Ball Painter
class _BreathingWavePainter extends CustomPainter {
  final double progress;
  final String phaseLabel;
  final double inhaleSec;
  final double inhale2Sec;
  final double holdSec;
  final double exhaleSec;
  final double hold2Sec;

  _BreathingWavePainter({
    required this.progress,
    required this.phaseLabel,
    required this.inhaleSec,
    this.inhale2Sec = 0.0,
    required this.holdSec,
    required this.exhaleSec,
    this.hold2Sec = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final yBottom = h * 0.68;
    final yTop = h * 0.28;
    final yMid = yBottom + (yTop - yBottom) * 0.75;
    final cycleW = w * 2.0;

    final totalSec = inhaleSec + inhale2Sec + holdSec + exhaleSec + hold2Sec;
    if (totalSec <= 0) return;

    final inhale1Ms = (inhaleSec * 1000).round();
    final inhale2Ms = (inhale2Sec * 1000).round();
    final hold1Ms = (holdSec * 1000).round();
    final exhaleMs = (exhaleSec * 1000).round();
    final hold2Ms = (hold2Sec * 1000).round();
    final totalMs = inhale1Ms + inhale2Ms + hold1Ms + exhaleMs + hold2Ms;

    final cycleMs = ((progress * totalMs).round()) % (totalMs > 0 ? totalMs : 9000);

    final rInhale1 = inhaleSec / totalSec;
    final rInhale2 = (inhaleSec + inhale2Sec) / totalSec;
    final rHold1 = (inhaleSec + inhale2Sec + holdSec) / totalSec;
    final rExhale = (inhaleSec + inhale2Sec + holdSec + exhaleSec) / totalSec;

    // Time-based Exact Phase Interpolation
    Offset rawBallPos;
    if (inhale2Sec > 0.01) {
      // Physiological Sigh (들숨 2s -> 추가들숨 1s -> 날숨 6s)
      final x1 = cycleW * rInhale1;
      final x2 = cycleW * rInhale2;

      if (cycleMs < inhale1Ms) {
        // Phase 1: 들숨 (0 ~ 2s, yBottom -> yMid 75% 상승)
        final t = inhale1Ms > 0 ? cycleMs / inhale1Ms : 0.0;
        rawBallPos = Offset(x1 * t, yBottom + (yMid - yBottom) * t);
      } else if (cycleMs < (inhale1Ms + inhale2Ms)) {
        // Phase 2: 추가들숨 (2s ~ 3s, yMid -> yTop 100% 추가 상승)
        final t = inhale2Ms > 0 ? (cycleMs - inhale1Ms) / inhale2Ms : 0.0;
        rawBallPos = Offset(x1 + (x2 - x1) * t, yMid + (yTop - yMid) * t);
      } else {
        // Phase 3: 날숨 (3s ~ 9s, yTop -> yBottom 6초 하강)
        final t = exhaleMs > 0 ? (cycleMs - (inhale1Ms + inhale2Ms)) / exhaleMs : 0.0;
        rawBallPos = Offset(x2 + (cycleW - x2) * t, yTop + (yBottom - yTop) * t);
      }
    } else if (hold2Sec > 0.01) {
      // 4-Phase Box Routine (Inhale 4s -> Hold1 4s -> Exhale 4s -> Hold2 4s)
      final x1 = cycleW * rInhale1;
      final x2 = cycleW * rHold1;
      final x3 = cycleW * rExhale;

      if (cycleMs < inhale1Ms) {
        // Phase 1: 들숨 (0 ~ 4s, 상승)
        final t = inhale1Ms > 0 ? cycleMs / inhale1Ms : 0.0;
        rawBallPos = Offset(x1 * t, yBottom + (yTop - yBottom) * t);
      } else if (cycleMs < (inhale1Ms + hold1Ms)) {
        // Phase 2: 참기 (4s ~ 8s, 상단 수평선 100% FLAT RESTING AT yTop)
        final t = hold1Ms > 0 ? (cycleMs - inhale1Ms) / hold1Ms : 0.0;
        rawBallPos = Offset(x1 + (x2 - x1) * t, yTop);
      } else if (cycleMs < (inhale1Ms + hold1Ms + exhaleMs)) {
        // Phase 3: 날숨 (8s ~ 12s, 하강)
        final t = exhaleMs > 0 ? (cycleMs - (inhale1Ms + hold1Ms)) / exhaleMs : 0.0;
        rawBallPos = Offset(x2 + (x3 - x2) * t, yTop + (yBottom - yTop) * t);
      } else {
        // Phase 4: 참기 (12s ~ 16s, 바닥 수평선 100% FLAT RESTING AT yBottom)
        final t = hold2Ms > 0 ? (cycleMs - (inhale1Ms + hold1Ms + exhaleMs)) / hold2Ms : 0.0;
        rawBallPos = Offset(x3 + (cycleW - x3) * t, yBottom);
      }
    } else if (holdSec <= 0.01) {
      // 2-Phase Routine (Inhale & Exhale e.g. 5-5 공진 호흡)
      if (cycleMs < inhale1Ms) {
        final t = inhale1Ms > 0 ? cycleMs / inhale1Ms : 0.0;
        rawBallPos = Offset(
          cycleW * rInhale1 * t,
          yBottom + (yTop - yBottom) * t,
        );
      } else {
        final t = exhaleMs > 0 ? (cycleMs - inhale1Ms) / exhaleMs : 0.0;
        rawBallPos = Offset(
          cycleW * rInhale1 + (cycleW - cycleW * rInhale1) * t,
          yTop + (yBottom - yTop) * t,
        );
      }
    } else {
      // 3-Phase Routine (1단계 들숨 4s -> 2단계 참기 7s -> 3단계 날숨 8s)
      final x1 = cycleW * rInhale1;
      final x2 = cycleW * rHold1;

      if (cycleMs < inhale1Ms) {
        // Phase 1: 들숨 (0ms ~ 4000ms: EXACT 4.0 seconds)
        final t = inhale1Ms > 0 ? cycleMs / inhale1Ms : 0.0;
        rawBallPos = Offset(
          x1 * t,
          yBottom + (yTop - yBottom) * t,
        );
      } else if (cycleMs < (inhale1Ms + hold1Ms)) {
        // Phase 2: 숨 참기 (4000ms ~ 11000ms: EXACT 7.0 seconds 100% FLAT RESTING AT yTop!)
        final t = hold1Ms > 0 ? (cycleMs - inhale1Ms) / hold1Ms : 0.0;
        rawBallPos = Offset(
          x1 + (x2 - x1) * t,
          yTop,
        );
      } else {
        // Phase 3: 날숨 (11000ms ~ 19000ms: EXACT 8.0 seconds)
        final t = exhaleMs > 0 ? (cycleMs - (inhale1Ms + hold1Ms)) / exhaleMs : 0.0;
        rawBallPos = Offset(
          x2 + (cycleW - x2) * t,
          yTop + (yBottom - yTop) * t,
        );
      }
    }

    final ballScreenX = w * 0.42;
    final cameraOffsetX = ballScreenX - rawBallPos.dx;
    final screenBallPos = Offset(ballScreenX, rawBallPos.dy);

    // Multi-Cycle Path
    final multiCyclePath = Path();
    bool isFirst = true;

    for (int cycle = -1; cycle <= 2; cycle++) {
      final originX = cycle * cycleW;
      final k0 = Offset(originX, yBottom);

      if (inhale2Sec > 0.01) {
        final k1 = Offset(originX + cycleW * rInhale1, yMid);
        final k2 = Offset(originX + cycleW * rInhale2, yTop);
        final k3 = Offset(originX + cycleW, yBottom);

        if (isFirst) {
          multiCyclePath.moveTo(k0.dx, k0.dy);
          isFirst = false;
        } else {
          multiCyclePath.lineTo(k0.dx, k0.dy);
        }
        multiCyclePath.lineTo(k1.dx, k1.dy);
        multiCyclePath.lineTo(k2.dx, k2.dy);
        multiCyclePath.lineTo(k3.dx, k3.dy);
      } else if (hold2Sec > 0.01) {
        final k1 = Offset(originX + cycleW * rInhale1, yTop);
        final k2 = Offset(originX + cycleW * rHold1, yTop);
        final k3 = Offset(originX + cycleW * rExhale, yBottom);
        final k4 = Offset(originX + cycleW, yBottom);

        if (isFirst) {
          multiCyclePath.moveTo(k0.dx, k0.dy);
          isFirst = false;
        } else {
          multiCyclePath.lineTo(k0.dx, k0.dy);
        }
        multiCyclePath.lineTo(k1.dx, k1.dy);
        multiCyclePath.lineTo(k2.dx, k2.dy);
        multiCyclePath.lineTo(k3.dx, k3.dy);
        multiCyclePath.lineTo(k4.dx, k4.dy);
      } else {
        final k1 = Offset(originX + cycleW * rInhale1, yTop);
        final k2 = Offset(originX + cycleW * rHold1, yTop);
        final k3 = Offset(originX + cycleW, yBottom);

        if (isFirst) {
          multiCyclePath.moveTo(k0.dx, k0.dy);
          isFirst = false;
        } else {
          multiCyclePath.lineTo(k0.dx, k0.dy);
        }
        multiCyclePath.lineTo(k1.dx, k1.dy);
        multiCyclePath.lineTo(k2.dx, k2.dy);
        multiCyclePath.lineTo(k3.dx, k3.dy);
      }
    }

    final multiMetrics = multiCyclePath.computeMetrics().first;
    final multiLength = multiMetrics.length;
    final ballMultiDist = multiLength * (progress + 1.0) / 4.0;

    canvas.save();
    canvas.translate(cameraOffsetX, 0);

    // Dotted Stage Lines & Labels attached to wave peaks
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(50)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const textStyleHeader = TextStyle(
      fontFamily: AppFonts.pretendard,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Colors.white,
    );



    for (int cycle = -1; cycle <= 2; cycle++) {
      final originX = cycle * cycleW;
      final x0 = originX;

      if (inhale2Sec > 0.01) {
        // Physiological Sigh (들숨 + 추가들숨 - 날숨)
        final x1 = originX + cycleW * rInhale1;
        final x2 = originX + cycleW * rInhale2;
        final x3 = originX + cycleW;

        _drawDottedVerticalLine(canvas, Offset(x1, yTop - 35), h * 0.45, linePaint);
        _drawDottedVerticalLine(canvas, Offset(x2, yTop - 35), h * 0.45, linePaint);

        // 1단계 [들숨] (x0 ~ x1)
        final tpInhale = TextPainter(
          text: const TextSpan(text: '들숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midInhaleX = (x0 + x1) / 2;
        tpInhale.paint(canvas, Offset(midInhaleX - tpInhale.width / 2, yTop - 30));

        // 2단계 [추가들숨] (x1 ~ x2)
        final tpInhale2 = TextPainter(
          text: const TextSpan(text: '추가들숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midInhale2X = (x1 + x2) / 2;
        tpInhale2.paint(canvas, Offset(midInhale2X - tpInhale2.width / 2, yTop - 30));

        // 3단계 [날숨] (x2 ~ x3)
        final tpExhale = TextPainter(
          text: const TextSpan(text: '날숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midExhaleX = (x2 + x3) / 2;
        tpExhale.paint(canvas, Offset(midExhaleX - tpExhale.width / 2, yTop - 30));
      } else if (hold2Sec > 0.01) {
        // 4-Phase Box Routine (들숨 -> 참기 -> 날숨 -> 참기)
        final x1 = originX + cycleW * rInhale1;
        final x2 = originX + cycleW * rHold1;
        final x3 = originX + cycleW * rExhale;
        final x4 = originX + cycleW;

        _drawDottedVerticalLine(canvas, Offset(x1, yTop - 35), h * 0.45, linePaint);
        _drawDottedVerticalLine(canvas, Offset(x2, yTop - 35), h * 0.45, linePaint);
        _drawDottedVerticalLine(canvas, Offset(x3, yTop - 35), h * 0.45, linePaint);

        // 1단계 [들숨] (x0 ~ x1)
        final tpInhale = TextPainter(
          text: const TextSpan(text: '들숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midInhaleX = (x0 + x1) / 2;
        tpInhale.paint(canvas, Offset(midInhaleX - tpInhale.width / 2, yTop - 30));

        // 2단계 [숨 참기] (x1 ~ x2)
        final tpHold = TextPainter(
          text: const TextSpan(text: '숨 참기', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midHoldX = (x1 + x2) / 2;
        tpHold.paint(canvas, Offset(midHoldX - tpHold.width / 2, yTop - 30));

        // 3단계 [날숨] (x2 ~ x3)
        final tpExhale = TextPainter(
          text: const TextSpan(text: '날숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midExhaleX = (x2 + x3) / 2;
        tpExhale.paint(canvas, Offset(midExhaleX - tpExhale.width / 2, yTop - 30));

        // 4단계 [숨 참기] (x3 ~ x4)
        final tpHold2 = TextPainter(
          text: const TextSpan(text: '숨 참기', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midHold2X = (x3 + x4) / 2;
        tpHold2.paint(canvas, Offset(midHold2X - tpHold2.width / 2, yTop - 30));
      } else if (rHold1 > rInhale1 + 0.01) {
        // 3-Phase Routine (들숨 -> 숨 참기 -> 날숨)
        final x1 = originX + cycleW * rInhale1;
        final x2 = originX + cycleW * rHold1;
        final x3 = originX + cycleW;
        _drawDottedVerticalLine(canvas, Offset(x1, yTop - 35), h * 0.45, linePaint);
        _drawDottedVerticalLine(canvas, Offset(x2, yTop - 35), h * 0.45, linePaint);

        // 1단계 [들숨] (0 ~ x1)
        final tpInhale = TextPainter(
          text: const TextSpan(text: '들숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midInhaleX = (x0 + x1) / 2;
        tpInhale.paint(canvas, Offset(midInhaleX - tpInhale.width / 2, yTop - 30));

        // 2단계 [숨 참기] (x1 ~ x2)
        final tpHold = TextPainter(
          text: const TextSpan(text: '숨 참기', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midHoldX = (x1 + x2) / 2;
        tpHold.paint(canvas, Offset(midHoldX - tpHold.width / 2, yTop - 30));

        // 3단계 [날숨] (x2 ~ x3)
        final tpExhale = TextPainter(
          text: const TextSpan(text: '날숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midExhaleX = (x2 + x3) / 2;
        tpExhale.paint(canvas, Offset(midExhaleX - tpExhale.width / 2, yTop - 30));
      } else {
        // 2-Phase Routine (들숨 -> 날숨)
        final x1 = originX + cycleW * rInhale1;
        final x3 = originX + cycleW;
        _drawDottedVerticalLine(canvas, Offset(x1, yTop - 35), h * 0.45, linePaint);

        // 1단계 [들숨] (x0 ~ x1)
        final tpInhale = TextPainter(
          text: const TextSpan(text: '들숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midInhaleX = (x0 + x1) / 2;
        tpInhale.paint(canvas, Offset(midInhaleX - tpInhale.width / 2, yTop - 30));

        // 2단계 [날숨] (x1 ~ x3)
        final tpExhale = TextPainter(
          text: const TextSpan(text: '날숨', style: textStyleHeader),
          textDirection: TextDirection.ltr,
        )..layout();
        final midExhaleX = (x1 + x3) / 2;
        tpExhale.paint(canvas, Offset(midExhaleX - tpExhale.width / 2, yTop - 30));
      }
    }

    // Base Track Paint
    final baseTrackPaint = Paint()
      ..color = const Color(0xFF4A5248).withAlpha(80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(multiCyclePath, baseTrackPaint);

    // Active Glowing Ribbon
    const backWindow = 280.0;
    const forwardWindow = 200.0;
    final startDist = (ballMultiDist - backWindow).clamp(0.0, multiLength);
    final endDist = (ballMultiDist + forwardWindow).clamp(0.0, multiLength);

    if (endDist > startDist) {
      final activeRibbonPath = multiMetrics.extractPath(startDist, endDist);
      final activePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF5A6657).withAlpha(0),
            const Color(0xFF86AB80).withAlpha(200),
            const Color(0xFFE2FFDA),
            const Color(0xFF86AB80).withAlpha(160),
            const Color(0xFF5A6657).withAlpha(0),
          ],
          stops: const [0.0, 0.35, 0.55, 0.80, 1.0],
        ).createShader(Rect.fromLTWH(
          rawBallPos.dx - backWindow,
          0,
          backWindow + forwardWindow,
          h,
        ));

      canvas.drawPath(activeRibbonPath, activePaint);
    }

    canvas.restore();

    // Outer Radial Halo Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE2FFDA).withAlpha(230),
          const Color(0xFF98E285).withAlpha(110),
          const Color(0xFF98E285).withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: screenBallPos, radius: 28));
    canvas.drawCircle(screenBallPos, 28, glowPaint);

    // Inner Bright Core Ball
    final ballCorePaint = Paint()
      ..color = const Color(0xFFE2FFDA)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenBallPos, 10, ballCorePaint);

    // Phase Label Pill Beside Ball
    final textPainter = TextPainter(
      text: TextSpan(
        text: phaseLabel,
        style: const TextStyle(
          fontFamily: AppFonts.pretendard,
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: Color(0xFFE2FFDA),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + 16;
    final pillHeight = textPainter.height + 8;
    final pillOffset = Offset(screenBallPos.dx + 16, screenBallPos.dy - 10);

    final pillRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillOffset.dx, pillOffset.dy, pillWidth, pillHeight),
      const Radius.circular(12),
    );
    final pillBgPaint = Paint()
      ..color = const Color(0xFF1F221E)
      ..style = PaintingStyle.fill;
    final pillBorderPaint = Paint()
      ..color = const Color(0xFF98E285).withAlpha(140)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawRRect(pillRRect, pillBgPaint);
    canvas.drawRRect(pillRRect, pillBorderPaint);

    textPainter.paint(
      canvas,
      Offset(pillOffset.dx + 8, pillOffset.dy + 4),
    );
  }

  void _drawDottedVerticalLine(Canvas canvas, Offset start, double height, Paint paint) {
    const dashHeight = 4.0;
    const dashSpace = 4.0;
    double startY = start.dy;
    final endY = start.dy + height;

    while (startY < endY) {
      canvas.drawLine(
        Offset(start.dx, startY),
        Offset(start.dx, (startY + dashHeight).clamp(startY, endY)),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _BreathingWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phaseLabel != phaseLabel ||
        oldDelegate.inhaleSec != inhaleSec ||
        oldDelegate.holdSec != holdSec ||
        oldDelegate.exhaleSec != exhaleSec;
  }
}
