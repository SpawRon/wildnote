import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart' as cam;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as picker;

import '../theme/app_theme.dart';
import '../widgets/app_svg_icon.dart';

class GuidedPhotoCaptureResult {
  final picker.XFile file;
  final String label;
  final int stepIndex;

  const GuidedPhotoCaptureResult({
    required this.file,
    required this.label,
    this.stepIndex = 0,
  });
}

class GuidedPhotoCaptureScreen extends StatefulWidget {
  const GuidedPhotoCaptureScreen({super.key});

  @override
  State<GuidedPhotoCaptureScreen> createState() =>
      _GuidedPhotoCaptureScreenState();
}

class _GuidedPhotoCaptureScreenState extends State<GuidedPhotoCaptureScreen>
    with WidgetsBindingObserver {
  final picker.ImagePicker _picker = picker.ImagePicker();
  final List<GuidedPhotoCaptureResult> _results = <GuidedPhotoCaptureResult>[];

  cam.CameraController? _controller;
  List<cam.CameraDescription> _cameras = <cam.CameraDescription>[];

  int _currentStep = 0;
  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _cameraFailed = false;
  bool _torchEnabled = false;
  String? _errorText;

  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;

  static const List<_PhotoGuideStep> _steps = <_PhotoGuideStep>[
    _PhotoGuideStep(
      title: 'Общий вид растения',
      subtitle: 'Снимите растение целиком, чтобы было понятно расположение и форма.',
      iconAssetName: AppIconAssets.photoGeneral,
      fallbackIcon: Icons.local_florist_rounded,
    ),
    _PhotoGuideStep(
      title: 'Листья крупным планом',
      subtitle: 'Покажите форму листа, жилкование и край.',
      iconAssetName: AppIconAssets.photoLeaves,
      fallbackIcon: Icons.eco_rounded,
    ),
    _PhotoGuideStep(
      title: 'Цветок или плод',
      subtitle: 'Если цветка или плода нет, этот шаг можно пропустить.',
      iconAssetName: AppIconAssets.photoFlowerOrFruit,
      fallbackIcon: Icons.filter_vintage_rounded,
    ),
    _PhotoGuideStep(
      title: 'Место произрастания',
      subtitle: 'Снимите окружение: почву, камни, травостой или склон.',
      iconAssetName: AppIconAssets.photoHabitat,
      fallbackIcon: Icons.landscape_rounded,
    ),
  ];

  _PhotoGuideStep get _step => _steps[_currentStep];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized ?? false;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeCamera());
      return;
    }

    if (state == AppLifecycleState.resumed && !initialized && mounted) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;

    setState(() {
      _isInitializing = true;
      _cameraFailed = false;
      _errorText = null;
      _torchEnabled = false;
    });

    try {
      _cameras = await cam.availableCameras();

      if (_cameras.isEmpty) {
        throw cam.CameraException(
          'no_camera',
          'Камера на устройстве не найдена',
        );
      }

      final selected = _cameras.firstWhere(
            (description) =>
        description.lensDirection == cam.CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = cam.CameraController(
        selected,
        cam.ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: cam.ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      double minZoom = 1;
      double maxZoom = 1;

      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
      } catch (_) {
        minZoom = 1;
        maxZoom = 1;
      }

      maxZoom = math.max(minZoom, math.min(maxZoom, 6));

      try {
        await controller.setFlashMode(cam.FlashMode.off);
      } catch (_) {}

      try {
        await controller.setZoomLevel(minZoom);
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
        _cameraFailed = false;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _currentZoom = minZoom;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _cameraFailed = true;
        _errorText = 'Не удалось открыть встроенную камеру';
      });
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final next = !_torchEnabled;

    try {
      await controller.setFlashMode(
        next ? cam.FlashMode.torch : cam.FlashMode.off,
      );

      if (!mounted) return;

      setState(() => _torchEnabled = next);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фонарик недоступен на этом устройстве')),
      );
    }
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final zoom = value.clamp(_minZoom, _maxZoom);

    setState(() => _currentZoom = zoom);

    try {
      await controller.setZoomLevel(zoom);
    } catch (_) {}
  }

  Future<void> _focusAt(TapDownDetails details, BoxConstraints constraints) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final dx = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final dy = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);

    try {
      await controller.setFocusPoint(Offset(dx, dy));
      await controller.setExposurePoint(Offset(dx, dy));
    } catch (_) {}
  }

  Future<void> _takePhoto() async {
    final controller = _controller;

    if (_isCapturing) return;

    if (controller == null || !controller.value.isInitialized) {
      await _takeSystemPhoto();
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final captured = await controller.takePicture();
      await _acceptFile(picker.XFile(captured.path));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сделать фото. Попробуйте системную камеру.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _takeSystemPhoto() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final picked = await _picker.pickImage(
        source: picker.ImageSource.camera,
        imageQuality: 86,
        maxWidth: 2600,
        maxHeight: 2600,
      );

      if (picked != null) {
        await _acceptFile(picked);
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final picked = await _picker.pickImage(
        source: picker.ImageSource.gallery,
        imageQuality: 86,
        maxWidth: 2600,
        maxHeight: 2600,
      );

      if (picked != null) {
        await _acceptFile(picked);
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _acceptFile(picker.XFile file) async {
    if (!mounted) return;

    _results.add(
      GuidedPhotoCaptureResult(
        file: file,
        label: _step.title,
        stepIndex: _currentStep,
      ),
    );

    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      return;
    }

    Navigator.of(context).pop(_results);
  }

  void _skipStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      return;
    }

    Navigator.of(context).pop(_results);
  }

  void _finish() {
    Navigator.of(context).pop(_results);
  }

  void _removeResultAt(int index) {
    if (index < 0 || index >= _results.length) return;

    final removed = _results.removeAt(index);
    final stepIndex = removed.stepIndex.clamp(0, _steps.length - 1);

    setState(() => _currentStep = stepIndex);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);
    final fieldMode = colors.fieldMode;
    final progress = (_currentStep + 1) / _steps.length;

    return Scaffold(
      backgroundColor: colors.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

          // Нижняя панель больше не растягивается на весь остаток экрана.
          // Она занимает только нужную высоту под подсказку, кнопки и миниатюры,
          // а камера уходит под неё нахлёстом. Поэтому снизу нет пустой белой
          // половины и нет чёрного зазора между preview и панелью.
          final sheetHeight = (_results.isEmpty ? 176.0 : 242.0) + bottomSafe;
          final sheetTop = math.max(0.0, constraints.maxHeight - sheetHeight);
          const sheetOverlap = 30.0;

          final cameraHeight = math.max(
            constraints.maxWidth * 4 / 3,
            sheetTop + sheetOverlap,
          );

          return Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: cameraHeight,
                child: _CameraPreviewLayer(
                  controller: _controller,
                  isInitializing: _isInitializing,
                  cameraFailed: _cameraFailed,
                  errorText: _errorText,
                  onTapDown: _focusAt,
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: cameraHeight,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.58),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                        stops: const [0.0, 0.20, 0.76, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                    child: _TopBar(
                      currentStep: _currentStep,
                      totalSteps: _steps.length,
                      progress: progress,
                      torchEnabled: _torchEnabled,
                      onClose: () => Navigator.of(context).pop(_results),
                      onTorch: _toggleTorch,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: math.max(118, cameraHeight * 0.25),
                child: _ZoomControl(
                  minZoom: _minZoom,
                  maxZoom: _maxZoom,
                  currentZoom: _currentZoom,
                  enabled: !_cameraFailed &&
                      !_isInitializing &&
                      _controller != null &&
                      _maxZoom > _minZoom,
                  onChanged: _setZoom,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: sheetTop,
                bottom: 0,
                child: _CameraBottomSheet(
                  colors: colors,
                  step: _step,
                  currentStep: _currentStep,
                  totalSteps: _steps.length,
                  fieldMode: fieldMode,
                  bottomSafe: bottomSafe,
                  isCapturing: _isCapturing,
                  hasResults: _results.isNotEmpty,
                  canUseBuiltInCamera: !_cameraFailed,
                  results: _results,
                  onCapture: _takePhoto,
                  onSystemCamera: _takeSystemPhoto,
                  onGallery: _pickFromGallery,
                  onSkip: _skipStep,
                  onFinish: _finish,
                  onRemoveResult: _removeResultAt,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CameraPreviewLayer extends StatelessWidget {
  final cam.CameraController? controller;
  final bool isInitializing;
  final bool cameraFailed;
  final String? errorText;
  final void Function(TapDownDetails, BoxConstraints) onTapDown;

  const _CameraPreviewLayer({
    required this.controller,
    required this.isInitializing,
    required this.cameraFailed,
    required this.errorText,
    required this.onTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final camera = controller;

    if (cameraFailed) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(28),
        child: Text(
          errorText ?? 'Камера недоступна',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    if (isInitializing || camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = camera.value.previewSize;

        if (previewSize == null) {
          return GestureDetector(
            onTapDown: (details) => onTapDown(details, constraints),
            child: cam.CameraPreview(camera),
          );
        }

        return GestureDetector(
          onTapDown: (details) => onTapDown(details, constraints),
          child: ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: previewSize.height,
                  height: previewSize.width,
                  child: cam.CameraPreview(camera),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final double progress;
  final bool torchEnabled;
  final VoidCallback onClose;
  final VoidCallback onTorch;

  const _TopBar({
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
    required this.torchEnabled,
    required this.onClose,
    required this.onTorch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundOverlayButton(
          icon: Icons.close_rounded,
          onTap: onClose,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              Text(
                '${currentStep + 1} из $totalSteps',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _RoundOverlayButton(
          icon: torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          onTap: onTorch,
        ),
      ],
    );
  }
}

class _CameraBottomSheet extends StatelessWidget {
  final WildColors colors;
  final _PhotoGuideStep step;
  final int currentStep;
  final int totalSteps;
  final bool fieldMode;
  final double bottomSafe;
  final bool isCapturing;
  final bool hasResults;
  final bool canUseBuiltInCamera;
  final List<GuidedPhotoCaptureResult> results;
  final VoidCallback onCapture;
  final VoidCallback onSystemCamera;
  final VoidCallback onGallery;
  final VoidCallback onSkip;
  final VoidCallback onFinish;
  final ValueChanged<int> onRemoveResult;

  const _CameraBottomSheet({
    required this.colors,
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.fieldMode,
    required this.bottomSafe,
    required this.isCapturing,
    required this.hasResults,
    required this.canUseBuiltInCamera,
    required this.results,
    required this.onCapture,
    required this.onSystemCamera,
    required this.onGallery,
    required this.onSkip,
    required this.onFinish,
    required this.onRemoveResult,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 10 + bottomSafe),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InstructionCard(
                step: step,
                currentStep: currentStep,
                totalSteps: totalSteps,
                colors: colors,
              ),
              const SizedBox(height: 10),
              _BottomControls(
                isCapturing: isCapturing,
                fieldMode: fieldMode,
                hasResults: hasResults,
                canUseBuiltInCamera: canUseBuiltInCamera,
                onCapture: onCapture,
                onSystemCamera: onSystemCamera,
                onGallery: onGallery,
                onSkip: onSkip,
                onFinish: onFinish,
              ),
              if (results.isNotEmpty) ...[
                const SizedBox(height: 8),
                _CapturedStrip(
                  results: results,
                  onRemove: onRemoveResult,
                  colors: colors,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  final _PhotoGuideStep step;
  final int currentStep;
  final int totalSteps;
  final WildColors colors;

  const _InstructionCard({
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.softGreen,
              borderRadius: BorderRadius.circular(18),
            ),
            child: AppSvgIcon(
              step.iconAssetName,
              color: colors.primary,
              size: 24,
              fallbackIcon: step.fallbackIcon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primaryDark,
                    fontSize: 17,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  step.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  final bool isCapturing;
  final bool fieldMode;
  final bool hasResults;
  final bool canUseBuiltInCamera;
  final VoidCallback onCapture;
  final VoidCallback onSystemCamera;
  final VoidCallback onGallery;
  final VoidCallback onSkip;
  final VoidCallback onFinish;

  const _BottomControls({
    required this.isCapturing,
    required this.fieldMode,
    required this.hasResults,
    required this.canUseBuiltInCamera,
    required this.onCapture,
    required this.onSystemCamera,
    required this.onGallery,
    required this.onSkip,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);
    final captureSize = fieldMode ? 74.0 : 66.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SmallAction(
          icon: Icons.photo_library_outlined,
          label: 'Галерея',
          color: colors.primaryDark,
          onTap: isCapturing ? null : onGallery,
        ),
        GestureDetector(
          onTap: isCapturing ? null : onCapture,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: captureSize,
            height: captureSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface,
              border: Border.all(
                color: colors.primary,
                width: 4,
              ),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: captureSize - 18,
                height: captureSize - 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCapturing
                      ? colors.primary.withValues(alpha: 0.42)
                      : colors.primary,
                ),
                child: isCapturing
                    ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
                    : null,
              ),
            ),
          ),
        ),
        _SmallAction(
          icon: canUseBuiltInCamera
              ? Icons.skip_next_rounded
              : Icons.camera_alt_outlined,
          label: canUseBuiltInCamera ? 'Пропустить' : 'Системная',
          color: colors.primaryDark,
          onTap: isCapturing
              ? null
              : (canUseBuiltInCamera ? onSkip : onSystemCamera),
        ),
        if (hasResults)
          _SmallAction(
            icon: Icons.check_rounded,
            label: 'Готово',
            color: colors.primaryDark,
            onTap: isCapturing ? null : onFinish,
          ),
      ],
    );
  }
}

class _ZoomControl extends StatelessWidget {
  final double minZoom;
  final double maxZoom;
  final double currentZoom;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _ZoomControl({
    required this.minZoom,
    required this.maxZoom,
    required this.currentZoom,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    final value = currentZoom.clamp(minZoom, maxZoom);

    return RepaintBoundary(
      child: Container(
        width: 44,
        height: 178,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Text(
              '${value.toStringAsFixed(value < 2 ? 1 : 0)}x',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: minZoom,
                    max: maxZoom,
                    value: value,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundOverlayButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundOverlayButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.30),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SmallAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapturedStrip extends StatelessWidget {
  final List<GuidedPhotoCaptureResult> results;
  final ValueChanged<int> onRemove;
  final WildColors colors;

  const _CapturedStrip({
    required this.results,
    required this.onRemove,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: results.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final result = results[index];

          return SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(
                      File(result.file.path),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      cacheWidth: 128,
                      cacheHeight: 128,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -5,
                  right: -5,
                  child: Material(
                    color: colors.surface,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => onRemove(index),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: colors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoGuideStep {
  final String title;
  final String subtitle;
  final String iconAssetName;
  final IconData fallbackIcon;

  const _PhotoGuideStep({
    required this.title,
    required this.subtitle,
    required this.iconAssetName,
    required this.fallbackIcon,
  });
}
