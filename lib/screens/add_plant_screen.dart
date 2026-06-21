import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
//noinspection SpellCheckingInspection
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/database_helper.dart';
import '../services/geoportal_sync_service.dart';
import '../services/explorer_service.dart';
import '../services/location_capture_service.dart';
import '../services/session_manager.dart';
import '../services/location_accuracy_settings.dart';
import '../services/gauss_kruger_service.dart';
import '../services/app_logger.dart';
import '../services/taxon_name_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wild_page_header.dart';
import '../widgets/app_svg_icon.dart';
import 'guided_photo_capture_screen.dart';

void _showWildTopMessage(BuildContext context, String text) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);

  if (overlay == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
    return;
  }

  final media = MediaQuery.maybeOf(context);
  final top = (media?.viewPadding.top ?? 0) + 12;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      final colors = WildColors.of(context);

      return Positioned(
        top: top,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, -10 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryDark,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.surface,
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);

  Future<void>.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) {
      entry.remove();
    }
  });
}



enum _QualitySeverity { good, warning, problem }

class _QualityItem {
  final String title;
  final String subtitle;
  final _QualitySeverity severity;

  const _QualityItem({
    required this.title,
    required this.subtitle,
    required this.severity,
  });
}

class _ObservationQualityReport {
  final int score;
  final List<_QualityItem> items;

  const _ObservationQualityReport({
    required this.score,
    required this.items,
  });

  bool get hasProblems =>
      items.any((item) => item.severity == _QualitySeverity.problem);

  bool get hasWarnings => items.any(
        (item) =>
    item.severity == _QualitySeverity.warning ||
        item.severity == _QualitySeverity.problem,
  );
}

class _NearbyObservationHit {
  final String name;
  final String source;
  final double distanceMeters;
  final String? createdAt;

  const _NearbyObservationHit({
    required this.name,
    required this.source,
    required this.distanceMeters,
    this.createdAt,
  });
}

class AddPlantScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;
  final VoidCallback? onSaved;
  final int? editObservationId;


  const AddPlantScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
    this.onSaved,
    this.editObservationId,
  });

  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen>
    with WidgetsBindingObserver {
  final List<File> _images = [];
  final List<String> _imageLabels = [];
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();

  final TextEditingController _nameController = TextEditingController();
  final FocusNode _taxonNameFocusNode = FocusNode();
  Timer? _taxonNameSearchDebounce;
  List<TaxonNameSuggestion> _taxonNameSuggestions = const <TaxonNameSuggestion>[];
  TaxonNameSuggestion? _selectedTaxonName;
  bool _isTaxonNameSearching = false;
  String? _taxonNameSearchError;
  final TextEditingController _descriptionController =
  TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  final TextEditingController _identificationStatusController =
  TextEditingController();
  final TextEditingController _habitatController = TextEditingController();
  final TextEditingController _soilTypeController = TextEditingController();
  final TextEditingController _moistureController = TextEditingController();
  final TextEditingController _lightConditionController =
  TextEditingController();
  final TextEditingController _lifeStageController = TextEditingController();
  final TextEditingController _phenophaseController = TextEditingController();
  final TextEditingController _plantConditionController =
  TextEditingController();
  final TextEditingController _abundanceCategoryController =
  TextEditingController();
  final TextEditingController _individualCountController =
  TextEditingController();
  final TextEditingController _areaOccupiedController = TextEditingController();
  final TextEditingController _anthropogenicImpactController =
  TextEditingController();
  final TextEditingController _threatFactorController = TextEditingController();
  final TextEditingController _protectionStatusController =
  TextEditingController();

  final Map<String, List<String>> _selectedAttributeTags = <String, List<String>>{};
  final Map<String, Set<String>> _sharedAttributeTags = <String, Set<String>>{};
  final LocationCaptureService _locationService = LocationCaptureService();
  final GaussKrugerService _gaussKrugerService = GaussKrugerService();
  final Distance _distance = const Distance();
  final MapController _manualMapController = MapController();
  final ValueNotifier<int> _photoIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _photoRevisionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _locationRevisionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _manualMapRevisionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _attributesRevisionNotifier = ValueNotifier<int>(0);
  LatLng? _manualPoint;
  bool _updatingManualControllers = false;
  int _currentPhotoIndex = 0;

  String _geoStatus = "Инициализация ГЛОНАСС...";
  String _coordinatesLabel = "Ожидание данных...";
  bool _isLocationFixed = false;
  bool _isManualEntry = false;
  bool _isSaving = false;
  Position? _currentPosition;
  double? _editLatitude;
  double? _editLongitude;
  double? _editAccuracy;

  bool get _isEditMode => widget.editObservationId != null;

  StreamSubscription<PreciseLocationProgress>? _locationSubscription;
  Timer? _manualPointDebounce;
  PreciseLocationProgress? _locationProgress;
  bool _isLocating = false;
  DateTime? _lastLocationUiUpdate;
  double _targetAccuracyMeters =
      LocationAccuracySettings.defaultTargetAccuracyMeters;

  String? _expandedAttributeKey;

  static const List<String> _attributeOrder = <String>[
    PlantAttributeKeys.identificationStatus,
    PlantAttributeKeys.habitat,
    PlantAttributeKeys.soilType,
    PlantAttributeKeys.moisture,
    PlantAttributeKeys.lightCondition,
    PlantAttributeKeys.lifeStage,
    PlantAttributeKeys.phenophase,
    PlantAttributeKeys.plantCondition,
    PlantAttributeKeys.abundanceCategory,
    PlantAttributeKeys.individualCount,
    PlantAttributeKeys.areaOccupied,
    PlantAttributeKeys.anthropogenicImpact,
    PlantAttributeKeys.threatFactor,
    PlantAttributeKeys.protectionStatus,
  ];



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _latController.addListener(_syncManualPointFromText);
    _lngController.addListener(_syncManualPointFromText);
    unawaited(_loadTargetAccuracy());
    unawaited(TaxonNameService.instance.warmUp());
    if (_isEditMode) {
      unawaited(_loadObservationForEdit());
    } else {
      _startLocationCapture(reset: true);
    }
    if (!widget.isGuest) {
      unawaited(
        GeoportalSyncService.instance.syncAttributeOptions(
          userLogin: widget.userLogin,
        ),
      );
    }
  }

  Future<void> _loadObservationForEdit() async {
    final id = widget.editObservationId;
    if (id == null) return;

    try {
      final item = await DatabaseHelper.instance.getObservationById(id);
      if (item == null) {
        if (mounted) _showMessage('Запись для редактирования не найдена');
        return;
      }

      final attributes = item['attributes'] is Map
          ? Map<String, Object?>.from(item['attributes'] as Map)
          : <String, Object?>{};

      String scalarText(Object? value) {
        if (value == null) return '';
        if (value is List) return value.join(', ');
        return value.toString();
      }

      void setText(String key, TextEditingController controller) {
        controller.text = scalarText(attributes[key]);
      }

      void setTags(String key, TextEditingController controller) {
        final raw = attributes[key];
        final values = <String>[];

        if (raw is Iterable) {
          for (final item in raw) {
            final value = item.toString().trim();
            if (value.isNotEmpty && !values.contains(value)) values.add(value);
          }
        } else if (raw != null) {
          final value = raw.toString().trim();
          if (value.isNotEmpty) values.add(value);
        }

        controller.clear();
        if (values.isEmpty) {
          _selectedAttributeTags.remove(key);
        } else {
          _selectedAttributeTags[key] = values;
        }
      }

      final latitude = _asFiniteDouble(item['latitude']);
      final longitude = _asFiniteDouble(item['longitude']);
      final accuracy = _asFiniteDouble(item['accuracy']);
      final isManual = _toInt(item['is_manual']) == 1;

      final photoRows = item['photos'] is List
          ? List<Map<String, dynamic>>.from(item['photos'] as List)
          : <Map<String, dynamic>>[];

      final loadedImages = <File>[];
      for (final photo in photoRows) {
        final path = photo['file_path']?.toString().trim();
        if (path == null || path.isEmpty) continue;
        final file = File(path);
        if (await file.exists()) loadedImages.add(file);
      }

      final existingName = scalarText(attributes[PlantAttributeKeys.plantName]);
      final existingTaxonId = scalarText(attributes['taxon_id']);
      final existingScientificName = scalarText(attributes['taxon_scientific_name']);
      final existingTaxonGroup = scalarText(attributes['taxon_group']);
      final existingTaxonSource = scalarText(attributes['taxon_source']);
      final existingTaxon = existingName.trim().isEmpty
          ? null
          : TaxonNameSuggestion(
        id: existingTaxonId.trim().isNotEmpty
            ? existingTaxonId.trim()
            : 'legacy:${TaxonNameService.normalizeSearchQuery(existingName)}',
        acceptedNameRu: TaxonNameService.normalizeDisplayName(existingName),
        scientificName: existingScientificName.trim(),
        group: existingTaxonGroup.trim().isNotEmpty
            ? existingTaxonGroup.trim()
            : 'plant',
        source: existingTaxonSource.trim().isNotEmpty
            ? existingTaxonSource.trim()
            : 'Ранее сохранённая запись',
        priority: 0,
        synonymsRu: const <String>[],
      );

      if (!mounted) return;

      setState(() {
        _images
          ..clear()
          ..addAll(loadedImages);
        _imageLabels
          ..clear()
          ..addAll(List<String>.filled(loadedImages.length, ''));
        _setCurrentPhotoIndex(0);

        _selectedTaxonName = existingTaxon;
        _nameController.text = existingTaxon?.acceptedNameRu ?? existingName;
        _taxonNameSuggestions = const <TaxonNameSuggestion>[];
        _taxonNameSearchError = null;
        _isTaxonNameSearching = false;
        _descriptionController.text = scalarText(attributes[PlantAttributeKeys.description]);
        setTags(PlantAttributeKeys.identificationStatus, _identificationStatusController);
        setTags(PlantAttributeKeys.habitat, _habitatController);
        setTags(PlantAttributeKeys.soilType, _soilTypeController);
        setTags(PlantAttributeKeys.moisture, _moistureController);
        setTags(PlantAttributeKeys.lightCondition, _lightConditionController);
        setTags(PlantAttributeKeys.lifeStage, _lifeStageController);
        setTags(PlantAttributeKeys.phenophase, _phenophaseController);
        setTags(PlantAttributeKeys.plantCondition, _plantConditionController);
        setTags(PlantAttributeKeys.abundanceCategory, _abundanceCategoryController);
        setText(PlantAttributeKeys.individualCount, _individualCountController);
        setText(PlantAttributeKeys.areaOccupied, _areaOccupiedController);
        setTags(PlantAttributeKeys.anthropogenicImpact, _anthropogenicImpactController);
        setTags(PlantAttributeKeys.threatFactor, _threatFactorController);
        setTags(PlantAttributeKeys.protectionStatus, _protectionStatusController);

        _editLatitude = latitude;
        _editLongitude = longitude;
        _editAccuracy = accuracy;
        _isManualEntry = isManual;
        _isLocationFixed = latitude != null && longitude != null;

        if (latitude != null && longitude != null) {
          _latController.text = latitude.toStringAsFixed(7);
          _lngController.text = longitude.toStringAsFixed(7);
          _manualPoint = LatLng(latitude, longitude);
          _coordinatesLabel = 'Шир: ${latitude.toStringAsFixed(7)}, Долг: ${longitude.toStringAsFixed(7)}';
          _geoStatus = isManual
              ? 'Координаты введены вручную'
              : 'Используются сохранённые координаты';
        }
      });

      _notifyPhotoListChanged();
      _notifyLocationChanged();
      _notifyManualMapChanged();
      _notifyAttributesChanged();
    } catch (e, st) {
      AppLogger.instance.error(
        'AddPlantScreen',
        'Load observation for edit failed',
        error: e,
        stackTrace: st,
        data: {'observationId': id},
      );

      if (mounted) _showMessage('Не удалось открыть запись для редактирования');
    }
  }

  double? _asFiniteDouble(dynamic value) {
    if (value == null) return null;
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value.toString().replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _locationSubscription?.cancel();
    _manualPointDebounce?.cancel();
    _taxonNameSearchDebounce?.cancel();
    unawaited(_locationService.dispose());
    _latController.removeListener(_syncManualPointFromText);
    _lngController.removeListener(_syncManualPointFromText);

    _taxonNameFocusNode.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _latController.dispose();
    _lngController.dispose();

    _identificationStatusController.dispose();
    _habitatController.dispose();
    _soilTypeController.dispose();
    _moistureController.dispose();
    _lightConditionController.dispose();
    _lifeStageController.dispose();
    _phenophaseController.dispose();
    _plantConditionController.dispose();
    _abundanceCategoryController.dispose();
    _individualCountController.dispose();
    _areaOccupiedController.dispose();
    _anthropogenicImpactController.dispose();
    _threatFactorController.dispose();
    _protectionStatusController.dispose();
    _photoIndexNotifier.dispose();
    _photoRevisionNotifier.dispose();
    _locationRevisionNotifier.dispose();
    _manualMapRevisionNotifier.dispose();
    _attributesRevisionNotifier.dispose();
    _pageController.dispose();

    super.dispose();
  }

  void _setCurrentPhotoIndex(int index) {
    _currentPhotoIndex = index;
    _photoIndexNotifier.value = index;
  }

  void _notifyPhotoListChanged() {
    _photoRevisionNotifier.value++;
  }

  void _notifyLocationChanged() {
    if (!mounted) return;
    _locationRevisionNotifier.value++;
  }

  void _notifyManualMapChanged() {
    if (!mounted) return;
    _manualMapRevisionNotifier.value++;
  }

  void _notifyAttributesChanged() {
    if (!mounted) return;
    _attributesRevisionNotifier.value++;
  }

  Future<void> _loadTargetAccuracy() async {
    final value = await LocationAccuracySettings.loadTargetAccuracyMeters();

    if (!mounted) return;

    _targetAccuracyMeters = value;
    _notifyLocationChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isManualEntry) {
      _startLocationCapture(reset: false);
    }
  }

  LatLng? _manualPointFromControllers() {
    final lat = double.tryParse(_latController.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lngController.text.replaceAll(',', '.'));

    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    return LatLng(lat, lng);
  }

  void _moveManualMap(LatLng point) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _manualMapController.move(point, 15);
      } catch (_) {
        // карта может быть ещё не готова
      }
    });
  }

  void _syncManualPointFromText() {
    if (!_isManualEntry || _updatingManualControllers) {
      _manualPointDebounce?.cancel();
      return;
    }

    _manualPointDebounce?.cancel();
    _manualPointDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || !_isManualEntry || _updatingManualControllers) return;

      final point = _manualPointFromControllers();
      if (point == null) return;

      final current = _manualPoint;
      if (current != null &&
          (current.latitude - point.latitude).abs() < 0.0000001 &&
          (current.longitude - point.longitude).abs() < 0.0000001) {
        return;
      }

      _manualPoint = point;
      _notifyLocationChanged();
      _notifyManualMapChanged();
      _moveManualMap(point);
    });
  }

  void _setManualPointFromMap(LatLng point) {
    if (!_isValidManualPoint(point)) return;

    _updatingManualControllers = true;
    _latController.text = point.latitude.toStringAsFixed(7);
    _lngController.text = point.longitude.toStringAsFixed(7);
    _updatingManualControllers = false;

    _manualPoint = point;
    _isLocationFixed = true;
    _coordinatesLabel =
    'Шир: ${point.latitude.toStringAsFixed(7)}, Долг: ${point.longitude.toStringAsFixed(7)}';
    _geoStatus = 'Координаты выбраны на карте';
    _notifyLocationChanged();
    _notifyManualMapChanged();

    _moveManualMap(point);
  }

  bool _isValidManualPoint(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    _showWildTopMessage(context, text);
  }

  Future<File> _persistPickedImage(XFile pickedFile) async {
    final source = File(pickedFile.path);
    final documentsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(
      p.join(documentsDir.path, 'observation_photos'),
    );

    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }

    final extension = p.extension(pickedFile.path).toLowerCase();
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${_images.length}$safeExtension';
    final target = File(p.join(photosDir.path, fileName));

    return source.copy(target.path);
  }


  Future<void> _addPickedImage(
      XFile pickedFile, {
        required String source,
        String? label,
      }) async {
    final savedFile = await _persistPickedImage(pickedFile);
    if (!mounted) return;

    _images.add(savedFile);
    _imageLabels.add(
      label?.trim().isNotEmpty == true
          ? label!.trim()
          : source == ImageSource.gallery.name
          ? 'Фото из галереи'
          : 'Фото наблюдения',
    );

    _setCurrentPhotoIndex(_images.length - 1);
    _notifyPhotoListChanged();

    AppLogger.instance.info(
      'AddPlantScreen',
      'Photo added',
      data: {
        'source': source,
        'photoCount': _images.length,
        'path': savedFile.path,
        'label': _imageLabels.last,
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _images.isNotEmpty) {
        _pageController.jumpToPage(_images.length - 1);
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          imageQuality: 70,
          maxWidth: 1600,
          maxHeight: 1600,
        );

        if (pickedFiles.isEmpty || !mounted) return;

        for (final pickedFile in pickedFiles) {
          await _addPickedImage(
            pickedFile,
            source: source.name,
            label: 'Фото из галереи',
          );
        }

        if (!mounted) return;
        _showMessage('Добавлено фото: ${pickedFiles.length}');
        return;
      }

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (pickedFile == null || !mounted) return;

      await _addPickedImage(
        pickedFile,
        source: source.name,
        label: 'Фото наблюдения',
      );
    } catch (e) {
      debugPrint("Ошибка выбора фото: $e");

      AppLogger.instance.error(
        'AddPlantScreen',
        'Pick image failed',
        error: e,
      );

      _showMessage("Не удалось выбрать фото");
    }
  }

  Future<void> _openGuidedPhotoCapture() async {
    try {
      final results = await Navigator.of(context).push<List<GuidedPhotoCaptureResult>>(
        MaterialPageRoute(
          builder: (_) => const GuidedPhotoCaptureScreen(),
        ),
      );

      if (!mounted || results == null || results.isEmpty) return;

      for (final result in results) {
        await _addPickedImage(
          result.file,
          source: 'guided_camera',
          label: result.label,
        );
      }

      if (!mounted) return;
      _showMessage('Добавлено фото по чек-листу: ${results.length}');
    } catch (e, st) {
      AppLogger.instance.error(
        'AddPlantScreen',
        'Guided photo capture failed',
        error: e,
        stackTrace: st,
      );

      if (mounted) {
        _showMessage('Не удалось открыть чек-лист фотографий');
      }
    }
  }

  Future<void> _toggleManualEntry(bool value) async {
    if (value == _isManualEntry) return;

    if (value) {
      // Ручной режим включается сразу, без ожидания остановки GPS-потока.
      _isManualEntry = true;
      _isLocating = false;
      _isLocationFixed = true;
      _geoStatus = "Ручной ввод координат";

      if (_currentPosition != null) {
        _latController.text = _currentPosition!.latitude.toStringAsFixed(7);
        _lngController.text = _currentPosition!.longitude.toStringAsFixed(7);
        _manualPoint = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      } else {
        final existingPoint = _manualPointFromControllers();
        _manualPoint =
            existingPoint ?? _manualPoint ?? const LatLng(68.9707, 33.0749);

        _latController.text = _manualPoint!.latitude.toStringAsFixed(7);
        _lngController.text = _manualPoint!.longitude.toStringAsFixed(7);
      }

      _coordinatesLabel =
      'Шир: ${_manualPoint!.latitude.toStringAsFixed(7)}, '
          'Долг: ${_manualPoint!.longitude.toStringAsFixed(7)}';

      _notifyLocationChanged();
      _notifyManualMapChanged();
      _moveManualMap(_manualPoint!);

      unawaited(
        _locationService.stopAndKeepBest(
          reason: 'Переключено на ручной ввод.',
        ),
      );

      return;
    }

    _isManualEntry = false;
    _isLocationFixed = false;
    _isLocating = true;
    _currentPosition = null;
    _locationProgress = null;
    _coordinatesLabel = "Ожидание данных...";
    _geoStatus = "Идёт точная фиксация координат...";
    _lastLocationUiUpdate = null;

    _notifyLocationChanged();

    await _loadTargetAccuracy();
    await _startLocationCapture(reset: true);
  }

  bool _validateManualCoordinates() {
    final lat = double.tryParse(_latController.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lngController.text.replaceAll(',', '.'));

    if (lat == null || lng == null) {
      _showMessage('Введите координаты в числовом формате');
      return false;
    }

    if (lat < -90 || lat > 90) {
      _showMessage('Широта должна быть от -90 до 90');
      return false;
    }

    if (lng < -180 || lng > 180) {
      _showMessage('Долгота должна быть от -180 до 180');
      return false;
    }

    return true;
  }

  Future<void> _startLocationCapture({bool reset = false}) async {
    if (!mounted || _isManualEntry) return;

    await _loadTargetAccuracy();

    await _locationSubscription?.cancel();

    _locationSubscription = _locationService.progressStream.listen((progress) {
      if (!mounted) return;

      void applyProgress() {
        _locationProgress = progress;
        _isLocating = progress.isRunning;
        _geoStatus = progress.message;

        if (progress.latitude != null && progress.longitude != null) {
          _coordinatesLabel =
          "Шир: ${progress.latitude}, Долг: ${progress.longitude}";
        } else {
          _coordinatesLabel = "Ожидание данных...";
        }

        if (progress.latitude != null &&
            progress.longitude != null &&
            progress.accuracy != null) {
          _currentPosition = Position(
            longitude: progress.longitude!,
            latitude: progress.latitude!,
            timestamp: DateTime.now(),
            accuracy: progress.accuracy!,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        }

        _isLocationFixed = progress.isUsable;
      }

      final now = DateTime.now();
      final previousLocationReady = _isLocationFixed;
      final previousRunning = _isLocating;
      final shouldRebuild =
          _lastLocationUiUpdate == null ||
              now.difference(_lastLocationUiUpdate!).inMilliseconds >= 900 ||
              progress.isUsable != previousLocationReady ||
              progress.isRunning != previousRunning;

      if (shouldRebuild) {
        _lastLocationUiUpdate = now;
        applyProgress();
        _notifyLocationChanged();
      } else {
        applyProgress();
      }
    });

    try {
      _isLocating = true;
      if (reset) {
        _isLocationFixed = false;
        _currentPosition = null;
        _locationProgress = null;
        _coordinatesLabel = "Ожидание данных...";
        _geoStatus = "Идёт точная фиксация координат...";
      }
      _notifyLocationChanged();

      await _locationService.startCapture(reset: reset);
    } catch (e, st) {
      AppLogger.instance.error(
        'AddPlantScreen',
        'Location capture start failed',
        error: e,
        stackTrace: st,
      );

      if (!mounted) return;
      _isLocating = false;
      _geoStatus = e.toString();
      _notifyLocationChanged();
    }
  }

  Future<void> _stopAndAcceptCurrentLocation() async {
    final progress = await _locationService.stopAndKeepBest(
      reason: 'Фиксация остановлена пользователем.',
    );

    if (!mounted) return;

    _isLocating = false;
    _locationProgress = progress;
    _geoStatus = progress.message;

    if (progress.latitude != null &&
        progress.longitude != null &&
        progress.accuracy != null) {
      _currentPosition = Position(
        longitude: progress.longitude!,
        latitude: progress.latitude!,
        timestamp: DateTime.now(),
        accuracy: progress.accuracy!,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      _coordinatesLabel =
      "Шир: ${progress.latitude}, Долг: ${progress.longitude}";
    }

    _isLocationFixed = progress.isUsable;
    _notifyLocationChanged();

    if (!progress.isUsable) {
      _showMessage(
        'Текущая точность пока слабая. Можно продолжить поиск или ввести координаты вручную.',
      );
    }
  }

  Future<void> _restartLocationCapture() async {
    await _locationService.stopAndKeepBest(
      reason: 'Перезапуск фиксации...',
    );
    await _startLocationCapture(reset: true);
  }

  int _countFilledPlantAttributes(Map<String, Object?> attributes) {
    int filled = 0;

    for (final key in _attributeOrder) {
      final value = attributes[key];
      if (value == null) continue;

      if (value is Iterable) {
        if (value.any((item) => item.toString().trim().isNotEmpty)) {
          filled++;
        }
        continue;
      }

      if (value.toString().trim().isNotEmpty) {
        filled++;
      }
    }

    return filled;
  }

  bool _hasFilledAttribute(
      Map<String, Object?> attributes,
      String key,
      ) {
    final value = attributes[key];
    if (value == null) return false;

    if (value is Iterable) {
      return value.any((item) => item.toString().trim().isNotEmpty);
    }

    return value.toString().trim().isNotEmpty;
  }

  double? _finiteDouble(dynamic value) {
    if (value == null) return null;

    double? parsed;
    if (value is double) {
      parsed = value;
    } else if (value is int) {
      parsed = value.toDouble();
    } else if (value is num) {
      parsed = value.toDouble();
    } else {
      parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    }

    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  String _formatNearbyDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.trim();

    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}';
  }

  Future<List<_NearbyObservationHit>> _findNearbyObservationHits({
    required double latitude,
    required double longitude,
    required double? accuracy,
  }) async {
    final center = LatLng(latitude, longitude);
    final radiusMeters = (accuracy == null || !accuracy.isFinite)
        ? 25.0
        : (accuracy * 2.0).clamp(20.0, 50.0).toDouble();

    final hits = <_NearbyObservationHit>[];

    try {
      final localRows = await DatabaseHelper.instance.getObservations(
        userLogin: widget.userLogin,
      );

      for (final row in localRows) {
        final lat = _finiteDouble(row['latitude']);
        final lon = _finiteDouble(row['longitude']);
        if (lat == null || lon == null) continue;

        final distance = _distance.as(
          LengthUnit.Meter,
          center,
          LatLng(lat, lon),
        );

        if (!distance.isFinite || distance > radiusMeters) continue;

        hits.add(
          _NearbyObservationHit(
            name: row['name']?.toString().trim().isNotEmpty == true
                ? row['name'].toString().trim()
                : 'Локальная запись',
            source: 'история',
            distanceMeters: distance,
            createdAt: row['created_at']?.toString(),
          ),
        );
      }
    } catch (e, st) {
      AppLogger.instance.warning(
        'AddPlantScreen',
        'Nearby local observation check failed',
        error: e,
        stackTrace: st,
      );
    }

    if (!widget.isGuest) {
      try {
        final session = await SessionManager.instance.getSession();
        if (session != null && !session.isGuest && session.accessToken != null) {
          final remote = await ExplorerService.instance
              .loadPointsByRadius(
            session: session,
            centerLatitude: latitude,
            centerLongitude: longitude,
            radiusMeters: radiusMeters,
          )
              .timeout(
            const Duration(seconds: 4),
            onTimeout: () => const <ExplorerPoint>[],
          );

          for (final point in remote) {
            final distance = _distance.as(
              LengthUnit.Meter,
              center,
              point.latLng,
            );

            if (!distance.isFinite || distance > radiusMeters) continue;

            hits.add(
              _NearbyObservationHit(
                name: point.name.trim().isNotEmpty
                    ? point.name.trim()
                    : 'Точка геопортала',
                source: point.userLogin == widget.userLogin.toLowerCase()
                    ? 'геопортал, ваш слой'
                    : 'геопортал, ${point.userLogin}',
                distanceMeters: distance,
                createdAt: point.createdAt,
              ),
            );
          }
        }
      } catch (e, st) {
        AppLogger.instance.warning(
          'AddPlantScreen',
          'Nearby remote observation check failed',
          error: e,
          stackTrace: st,
        );
      }
    }

    hits.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    final unique = <_NearbyObservationHit>[];
    final seen = <String>{};

    for (final hit in hits) {
      final key = [
        hit.name.toLowerCase(),
        hit.source.toLowerCase(),
        hit.distanceMeters.round(),
      ].join('|');

      if (seen.add(key)) {
        unique.add(hit);
      }

      if (unique.length >= 5) break;
    }

    return unique;
  }

  _ObservationQualityReport _buildObservationQualityReport({
    required double? latitude,
    required double? longitude,
    required double? accuracy,
    required Map<String, Object?> attributes,
    required List<_NearbyObservationHit> nearbyHits,
  }) {
    final items = <_QualityItem>[];
    int score = 0;

    void add({
      required String title,
      required String subtitle,
      required _QualitySeverity severity,
      required int points,
    }) {
      items.add(
        _QualityItem(
          title: title,
          subtitle: subtitle,
          severity: severity,
        ),
      );
      score += points;
    }

    final hasCoordinates = latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite;

    if (!hasCoordinates) {
      add(
        title: 'Координаты',
        subtitle: 'Координаты не определены.',
        severity: _QualitySeverity.problem,
        points: 0,
      );
    } else if (_isManualEntry) {
      add(
        title: 'Координаты',
        subtitle: 'Ручной ввод. Координаты сохранены, но точность не оценивалась датчиком.',
        severity: _QualitySeverity.warning,
        points: 22,
      );
    } else if (accuracy == null || !accuracy.isFinite) {
      add(
        title: 'Координаты',
        subtitle: 'Координаты есть, но точность не рассчитана.',
        severity: _QualitySeverity.warning,
        points: 18,
      );
    } else if (accuracy <= _targetAccuracyMeters) {
      add(
        title: 'Координаты',
        subtitle:
        'Итоговая точность ±${accuracy.toStringAsFixed(1)} м. Цель выполнена.',
        severity: _QualitySeverity.good,
        points: 30,
      );
    } else if (accuracy <= _targetAccuracyMeters * 2) {
      add(
        title: 'Координаты',
        subtitle:
        'Точность ±${accuracy.toStringAsFixed(1)} м. Пригодно, но можно уточнить лучше.',
        severity: _QualitySeverity.warning,
        points: 23,
      );
    } else {
      add(
        title: 'Координаты',
        subtitle:
        'Точность ±${accuracy.toStringAsFixed(1)} м. Для редких растений лучше уточнить.',
        severity: _QualitySeverity.problem,
        points: 12,
      );
    }

    final rejectedSpatialOutliers =
        _locationProgress?.rejectedSpatialOutlierCount ?? 0;
    final lastRejectedDistance =
        _locationProgress?.lastRejectedSpatialDistanceMeters;

    if (!_isManualEntry && rejectedSpatialOutliers > 0) {
      final distanceText = lastRejectedDistance == null
          ? ''
          : ' Последний скачок: ${lastRejectedDistance.toStringAsFixed(1)} м.';

      add(
        title: 'Антискачок координат',
        subtitle:
        'Отклонено $rejectedSpatialOutliers пространственных выбросов.$distanceText',
        severity: _QualitySeverity.good,
        points: 0,
      );
    }

    if (nearbyHits.isEmpty) {
      add(
        title: 'Похожие точки рядом',
        subtitle: 'В радиусе проверки похожих записей не найдено.',
        severity: _QualitySeverity.good,
        points: 5,
      );
    } else {
      final nearest = nearbyHits.first;
      final details = nearbyHits.take(3).map((hit) {
        final date = _formatNearbyDate(hit.createdAt);
        final datePart = date.isEmpty ? '' : ', $date';
        return '${hit.name} — ${hit.distanceMeters.toStringAsFixed(1)} м (${hit.source}$datePart)';
      }).join('; ');

      add(
        title: 'Похожие точки рядом',
        subtitle:
        'Найдено рядом: ${nearbyHits.length}. Ближайшая ${nearest.distanceMeters.toStringAsFixed(1)} м. Проверьте, это новая особь или повторная запись. $details',
        severity: _QualitySeverity.warning,
        points: 1,
      );
    }

    if (_images.isEmpty) {
      add(
        title: 'Фотографии',
        subtitle: 'Фото не добавлены. Проверить запись позже будет сложнее.',
        severity: _QualitySeverity.problem,
        points: 0,
      );
    } else if (_images.length == 1) {
      add(
        title: 'Фотографии',
        subtitle: 'Добавлено 1 фото. Лучше иметь общий вид и крупный план.',
        severity: _QualitySeverity.warning,
        points: 13,
      );
    } else {
      add(
        title: 'Фотографии',
        subtitle: 'Добавлено ${_images.length} фото. Этого достаточно для проверки.',
        severity: _QualitySeverity.good,
        points: 20,
      );
    }

    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      add(
        title: 'Описание',
        subtitle: 'Свободное описание пустое. Можно оставить так, если атрибутов хватает.',
        severity: _QualitySeverity.warning,
        points: 4,
      );
    } else if (description.length < 20) {
      add(
        title: 'Описание',
        subtitle: 'Описание короткое. При необходимости добавьте детали наблюдения.',
        severity: _QualitySeverity.warning,
        points: 7,
      );
    } else {
      add(
        title: 'Описание',
        subtitle: 'Описание заполнено.',
        severity: _QualitySeverity.good,
        points: 10,
      );
    }

    final filledAttributes = _countFilledPlantAttributes(attributes);
    final attributePoints = ((filledAttributes / _attributeOrder.length) * 25)
        .round()
        .clamp(0, 25)
        .toInt();

    if (filledAttributes >= 9) {
      add(
        title: 'Атрибуты',
        subtitle: 'Заполнено $filledAttributes из ${_attributeOrder.length} характеристик.',
        severity: _QualitySeverity.good,
        points: attributePoints,
      );
    } else if (filledAttributes >= 5) {
      add(
        title: 'Атрибуты',
        subtitle: 'Заполнено $filledAttributes из ${_attributeOrder.length}. Можно добавить ещё важные признаки.',
        severity: _QualitySeverity.warning,
        points: attributePoints,
      );
    } else {
      add(
        title: 'Атрибуты',
        subtitle: 'Заполнено только $filledAttributes из ${_attributeOrder.length}. Запись будет менее полезной.',
        severity: _QualitySeverity.problem,
        points: attributePoints,
      );
    }

    final keyFields = <String>[
      PlantAttributeKeys.habitat,
      PlantAttributeKeys.lifeStage,
      PlantAttributeKeys.plantCondition,
      PlantAttributeKeys.abundanceCategory,
    ];
    final filledKeyFields = keyFields
        .where((key) => _hasFilledAttribute(attributes, key))
        .length;

    if (filledKeyFields == keyFields.length) {
      add(
        title: 'Ключевые признаки',
        subtitle: 'Местообитание, стадия, состояние и численность заполнены.',
        severity: _QualitySeverity.good,
        points: 15,
      );
    } else if (filledKeyFields >= 2) {
      add(
        title: 'Ключевые признаки',
        subtitle: 'Заполнено $filledKeyFields из ${keyFields.length} ключевых признаков.',
        severity: _QualitySeverity.warning,
        points: 9,
      );
    } else {
      add(
        title: 'Ключевые признаки',
        subtitle: 'Заполните хотя бы местообитание, состояние или численность.',
        severity: _QualitySeverity.problem,
        points: 3,
      );
    }

    return _ObservationQualityReport(
      score: score.clamp(0, 100).toInt(),
      items: items,
    );
  }

  Color _qualityScoreColor(
      BuildContext context,
      _ObservationQualityReport report,
      ) {
    final colors = WildColors.of(context);

    if (report.score >= 80 && !report.hasProblems) {
      return AppColors.success;
    }
    if (report.score >= 55) {
      return AppColors.warning;
    }
    return colors.danger;
  }

  IconData _qualityIcon(_QualitySeverity severity) {
    switch (severity) {
      case _QualitySeverity.good:
        return Icons.check_circle_rounded;
      case _QualitySeverity.warning:
        return Icons.info_rounded;
      case _QualitySeverity.problem:
        return Icons.warning_amber_rounded;
    }
  }

  Color _qualityItemColor(
      BuildContext context,
      _QualitySeverity severity,
      ) {
    final colors = WildColors.of(context);

    switch (severity) {
      case _QualitySeverity.good:
        return AppColors.success;
      case _QualitySeverity.warning:
        return AppColors.warning;
      case _QualitySeverity.problem:
        return colors.danger;
    }
  }

  Widget _qualityItemTile(_QualityItem item) {
    final colors = WildColors.of(context);
    final color = _qualityItemColor(context, item.severity);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_qualityIcon(item.severity), color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.28,
                    fontWeight: FontWeight.w600,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showObservationQualityPassport(
      _ObservationQualityReport report,
      ) async {
    if (!mounted) return false;

    FocusScope.of(context).unfocus();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = WildColors.of(context);
        final scoreColor = _qualityScoreColor(context, report);
        final actionLabel = report.hasWarnings ? 'Отправить' : 'Продолжить';

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sheet),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scoreColor.withValues(alpha: 0.13),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${report.score}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: scoreColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Паспорт качества наблюдения',
                                style: TextStyle(
                                  fontSize: 22,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  color: colors.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                report.hasWarnings
                                    ? 'Проверьте предупреждения перед сохранением.'
                                    : 'Запись выглядит готовой к сохранению.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                  color: colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: colors.border),
                    const SizedBox(height: 4),
                    ...report.items.map(_qualityItemTile),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(report.hasWarnings ? 'Доработать' : 'Вернуться'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(actionLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _saveObservation() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      AppLogger.instance.info(
        'AddPlantScreen',
        'Save observation started',
        data: {
          'userLogin': widget.userLogin,
          'isGuest': widget.isGuest,
          'isManual': _isManualEntry,
          'photoCount': _images.length,
          'hasName': _nameController.text.trim().isNotEmpty,
        },
      );

      if (_selectedTaxonName == null || _nameController.text.trim().isEmpty) {
        AppLogger.instance.warning(
          'AddPlantScreen',
          'Save blocked: plant name is not selected from dictionary',
        );
        _showMessage('Выберите название из справочника');
        return;
      }

      double? latitude;
      double? longitude;
      double? accuracy;

      if (_isManualEntry) {
        if (!_validateManualCoordinates()) {
          AppLogger.instance.warning(
            'AddPlantScreen',
            'Save blocked: invalid manual coordinates',
          );
          return;
        }

        latitude = double.parse(_latController.text.replaceAll(',', '.'));
        longitude = double.parse(_lngController.text.replaceAll(',', '.'));
        accuracy = null;

        setState(() {
          _isLocationFixed = true;
          _coordinatesLabel = "Шир: $latitude, Долг: $longitude";
          _geoStatus = "Координаты введены вручную";
        });
      } else {
        if (_currentPosition == null) {
          if (_isEditMode && _editLatitude != null && _editLongitude != null) {
            latitude = _editLatitude;
            longitude = _editLongitude;
            accuracy = _editAccuracy;
          } else {
            AppLogger.instance.warning(
              'AddPlantScreen',
              'Save blocked: current position is null',
            );
            _showMessage('Сначала дождитесь определения геолокации');
            return;
          }
        } else {
          latitude = _currentPosition!.latitude;
          longitude = _currentPosition!.longitude;
          accuracy = _currentPosition!.accuracy;
        }
      }

      if (!_isManualEntry && !_isLocationFixed && !_isEditMode) {
        AppLogger.instance.warning(
          'AddPlantScreen',
          'Save blocked: accuracy is not enough',
          data: {
            'accuracy': accuracy,
            'isLocationFixed': _isLocationFixed,
            'progressIsUsable': _locationProgress?.isUsable,
          },
        );

        _showMessage(
          'Точность пока недостаточная. Продолжите фиксацию, нажмите "Остановить и принять текущее" или введите координаты вручную.',
        );
        return;
      }

      if (latitude == null || longitude == null) {
        AppLogger.instance.warning(
          'AddPlantScreen',
          'Save blocked: coordinates are null after location branch',
          data: {
            'latitude': latitude,
            'longitude': longitude,
            'isManual': _isManualEntry,
            'isEditMode': _isEditMode,
          },
        );
        _showMessage('Не удалось получить координаты наблюдения');
        return;
      }

      final saveLatitude = latitude;
      final saveLongitude = longitude;

      final attributes = _collectAttributes();
      final nearbyHits = await _findNearbyObservationHits(
        latitude: saveLatitude,
        longitude: saveLongitude,
        accuracy: accuracy,
      );

      final qualityReport = _buildObservationQualityReport(
        latitude: saveLatitude,
        longitude: saveLongitude,
        accuracy: accuracy,
        attributes: attributes,
        nearbyHits: nearbyHits,
      );

      final shouldContinue = await _showObservationQualityPassport(qualityReport);
      if (!shouldContinue) {
        AppLogger.instance.info(
          'AddPlantScreen',
          'Save cancelled from quality passport',
          data: {
            'score': qualityReport.score,
            'hasWarnings': qualityReport.hasWarnings,
          },
        );
        return;
      }

      double? gaussX;
      double? gaussY;
      int? zone;

      try {
        final gk = await _gaussKrugerService.transform(
          latitude: saveLatitude,
          longitude: saveLongitude,
        );

        gaussX = gk.x;
        gaussY = gk.y;
        zone = gk.zone;

        AppLogger.instance.info(
          'AddPlantScreen',
          'Gauss-Kruger transform completed',
          data: {
            'zone': zone,
            'gaussX': gaussX,
            'gaussY': gaussY,
          },
        );
      } catch (e, st) {
        debugPrint('Ошибка преобразования Гаусса–Крюгера: $e');

        AppLogger.instance.warning(
          'AddPlantScreen',
          'Gauss-Kruger transform failed',
          error: e,
          stackTrace: st,
        );
      }

      final nowIso = DateTime.now().toIso8601String();
      final createdAt = _isEditMode ? null : nowIso;

      final observation = <String, Object?>{
        'user_login': widget.userLogin,
        'name': _selectedTaxonName?.acceptedNameRu ?? _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'latitude': saveLatitude,
        'longitude': saveLongitude,
        'is_manual': _isManualEntry ? 1 : 0,
        'accuracy': accuracy,
        'status': widget.isGuest
            ? ObservationStatus.localOnly
            : ObservationStatus.queued,
        'gauss_x': gaussX,
        'gauss_y': gaussY,
        'zone': zone,
        'remote_feature_id': null,
        'remote_folder': widget.isGuest
            ? 'local_only'
            : '/users/${widget.userLogin}/WildNote',
        'sync_error': null,
        'synced_at': null,
      };

      if (createdAt != null) {
        observation['created_at'] = createdAt;
      }

      final photoPaths = _images.map((e) => e.path).toList();

      AppLogger.instance.info(
        'AddPlantScreen',
        'Inserting observation into local database',
        data: {
          'userLogin': widget.userLogin,
          'isManual': _isManualEntry,
          'accuracy': accuracy,
          'photoCount': photoPaths.length,
          'createdAt': createdAt,
        },
      );

      late final int observationId;

      if (_isEditMode) {
        observationId = widget.editObservationId!;
        await DatabaseHelper.instance.updateObservation(
          id: observationId,
          observation: observation,
          photoPaths: photoPaths,
          attributes: attributes,
        );

        AppLogger.instance.info(
          'AddPlantScreen',
          'Observation updated in local database',
          data: {
            'localObservationId': observationId,
            'photoCount': photoPaths.length,
          },
        );
      } else {
        observationId = await DatabaseHelper.instance.insertObservation(
          observation: observation,
          photoPaths: photoPaths,
          attributes: attributes,
        );

        AppLogger.instance.info(
          'AddPlantScreen',
          'Observation inserted into local database',
          data: {
            'localObservationId': observationId,
            'photoCount': photoPaths.length,
          },
        );
      }

      String message = _isEditMode
          ? (widget.isGuest ? 'Изменения сохранены локально' : 'Изменения сохранены и добавлены в очередь')
          : (widget.isGuest
          ? 'Запись сохранена локально'
          : 'Запись добавлена в очередь на отправку');

      if (!widget.isGuest) {
        await _publishMarkedAttributeOptions();

        AppLogger.instance.info(
          'AddPlantScreen',
          'Starting sync after local save',
          data: {
            'localObservationId': observationId,
          },
        );

        final syncResult =
        await GeoportalSyncService.instance.sendObservationById(observationId);

        AppLogger.instance.info(
          'AddPlantScreen',
          'Sync after local save completed',
          data: {
            'localObservationId': observationId,
            'success': syncResult.success,
            'message': syncResult.message,
          },
        );

        if (syncResult.success) {
          message = _isEditMode
              ? 'Изменения отправлены на геопортал'
              : 'Запись отправлена на геопортал';
        } else {
          message = _isEditMode
              ? 'Изменения сохранены локально. ${syncResult.message}'
              : 'Сохранено локально. ${syncResult.message}';
        }
      }

      if (!mounted) return;

      _showWildTopMessage(context, message);

      widget.onSaved?.call();
      if (_isEditMode) {
        Navigator.of(context).pop(true);
      } else {
        _clearForm();
      }
    } catch (e, st) {
      debugPrint("Ошибка сохранения в БД: $e");

      AppLogger.instance.error(
        'AddPlantScreen',
        'Save observation failed',
        error: e,
        stackTrace: st,
      );

      if (mounted) {
        _showMessage("Не удалось сохранить запись");
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _clearForm() {
    setState(() {
      _images.clear();
      _imageLabels.clear();
      _setCurrentPhotoIndex(0);
      _selectedTaxonName = null;
      _taxonNameSuggestions = const <TaxonNameSuggestion>[];
      _taxonNameSearchError = null;
      _isTaxonNameSearching = false;
      _nameController.clear();
      _descriptionController.clear();
      _latController.clear();
      _lngController.clear();

      _identificationStatusController.clear();
      _habitatController.clear();
      _soilTypeController.clear();
      _moistureController.clear();
      _lightConditionController.clear();
      _lifeStageController.clear();
      _phenophaseController.clear();
      _plantConditionController.clear();
      _abundanceCategoryController.clear();
      _individualCountController.clear();
      _areaOccupiedController.clear();
      _anthropogenicImpactController.clear();
      _threatFactorController.clear();
      _protectionStatusController.clear();
      _selectedAttributeTags.clear();
      _sharedAttributeTags.clear();
      _expandedAttributeKey = null;
      _isManualEntry = false;
      _isLocationFixed = false;
      _coordinatesLabel = "Ожидание данных...";
      _geoStatus = "Инициализация ГЛОНАСС...";
      _currentPosition = null;
      _manualPoint = null;
    });

    _notifyPhotoListChanged();
    _notifyLocationChanged();
    _notifyManualMapChanged();
    _notifyAttributesChanged();
    unawaited(_loadTargetAccuracy());
    unawaited(TaxonNameService.instance.warmUp());
    if (_isEditMode) {
      unawaited(_loadObservationForEdit());
    } else {
      _startLocationCapture(reset: true);
    }
    if (!widget.isGuest) {
      unawaited(
        GeoportalSyncService.instance.syncAttributeOptions(
          userLogin: widget.userLogin,
        ),
      );
    }
  }

  void _removePhoto(int index) {
    if (_images.isEmpty || index < 0 || index >= _images.length) return;

    _images.removeAt(index);
    if (index < _imageLabels.length) {
      _imageLabels.removeAt(index);
    }

    if (_images.isEmpty) {
      _setCurrentPhotoIndex(0);
    } else if (_currentPhotoIndex >= _images.length) {
      _setCurrentPhotoIndex(_images.length - 1);
    } else {
      _setCurrentPhotoIndex(_currentPhotoIndex);
    }

    _notifyPhotoListChanged();
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: WildColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                Icons.checklist_rounded,
                color: WildColors.of(context).primary,
              ),
              title: const Text('Серия по чек-листу'),
              subtitle: const Text('Общий вид, листья, цветок или плод, место произрастания'),
              onTap: () {
                Navigator.of(context).pop();
                _openGuidedPhotoCapture();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.camera_alt,
                color: WildColors.of(context).primary,
              ),
              title: const Text('Камера'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library,
                color: WildColors.of(context).primary,
              ),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Object?> _collectAttributes() {
    final result = <String, Object?>{};

    void addText(String key, TextEditingController controller) {
      final value = controller.text.trim();
      if (value.isNotEmpty) {
        result[key] = value;
      }
    }

    void addTags(String key, TextEditingController controller) {
      final values = <String>[];

      for (final item in _selectedAttributeTags[key] ?? const <String>[]) {
        final value = item.trim();
        if (value.isNotEmpty && !values.contains(value)) {
          values.add(value);
        }
      }

      final typed = controller.text.trim();
      if (typed.isNotEmpty && !values.contains(typed)) {
        values.add(typed);
      }

      if (values.isEmpty) return;

      result[key] = values.length == 1 ? values.first : values;
    }

    void addNumber(String key, TextEditingController controller) {
      final raw = controller.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) return;

      final value = double.tryParse(raw);
      if (value != null && value.isFinite) {
        result[key] = value;
      } else {
        result[key] = raw;
      }
    }

    final selectedTaxon = _selectedTaxonName;
    if (selectedTaxon != null) {
      result[PlantAttributeKeys.plantName] = selectedTaxon.acceptedNameRu;
      result['taxon_id'] = selectedTaxon.id;
      result['taxon_scientific_name'] = selectedTaxon.scientificName;
      result['taxon_group'] = selectedTaxon.group;
      result['taxon_source'] = selectedTaxon.source;
    }
    addText(PlantAttributeKeys.description, _descriptionController);

    addTags(
      PlantAttributeKeys.identificationStatus,
      _identificationStatusController,
    );
    addTags(PlantAttributeKeys.habitat, _habitatController);
    addTags(PlantAttributeKeys.soilType, _soilTypeController);
    addTags(PlantAttributeKeys.moisture, _moistureController);
    addTags(PlantAttributeKeys.lightCondition, _lightConditionController);
    addTags(PlantAttributeKeys.lifeStage, _lifeStageController);
    addTags(PlantAttributeKeys.phenophase, _phenophaseController);
    addTags(PlantAttributeKeys.plantCondition, _plantConditionController);
    addTags(PlantAttributeKeys.abundanceCategory, _abundanceCategoryController);
    addNumber(PlantAttributeKeys.individualCount, _individualCountController);
    addNumber(PlantAttributeKeys.areaOccupied, _areaOccupiedController);
    addTags(
      PlantAttributeKeys.anthropogenicImpact,
      _anthropogenicImpactController,
    );
    addTags(PlantAttributeKeys.threatFactor, _threatFactorController);
    addTags(PlantAttributeKeys.protectionStatus, _protectionStatusController);

    return result;
  }

  Future<void> _publishMarkedAttributeOptions() async {
    if (widget.isGuest || _sharedAttributeTags.isEmpty) return;

    for (final entry in _sharedAttributeTags.entries) {
      for (final value in entry.value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) continue;

        await GeoportalSyncService.instance.publishAttributeOption(
          attributeKey: entry.key,
          value: trimmed,
          createdBy: widget.userLogin,
        );
      }
    }
  }

  void _setAttributeTags(String key, List<String> values) {
    if (!mounted) return;

    if (values.isEmpty) {
      _selectedAttributeTags.remove(key);
    } else {
      _selectedAttributeTags[key] = values;
    }

    _notifyAttributesChanged();
  }

  void _setSharedAttributeTags(String key, Set<String> values) {
    if (values.isEmpty) {
      _sharedAttributeTags.remove(key);
    } else {
      _sharedAttributeTags[key] = values;
    }

    _notifyAttributesChanged();
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: WildColors.of(context).primaryDark,
        ),
      ),
    );
  }

  bool _isLastAttribute(String attributeKey) {
    return _attributeOrder.isNotEmpty && _attributeOrder.last == attributeKey;
  }

  String? _nextAttributeKey(String attributeKey) {
    final index = _attributeOrder.indexOf(attributeKey);
    if (index < 0 || index >= _attributeOrder.length - 1) return null;
    return _attributeOrder[index + 1];
  }

  void _toggleAttribute(String attributeKey) {
    if (!mounted) return;

    FocusScope.of(context).unfocus();

    _expandedAttributeKey =
    _expandedAttributeKey == attributeKey ? null : attributeKey;
    _notifyAttributesChanged();
  }

  void _goToNextAttribute(String attributeKey) {
    if (!mounted) return;

    final nextKey = _nextAttributeKey(attributeKey);
    _expandedAttributeKey = nextKey;
    _notifyAttributesChanged();

    if (nextKey == null) {
      FocusScope.of(context).unfocus();
    }
  }


  Widget _buildTextInputCard({
    required String title,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    final colors = WildColors.of(context);
    final fill = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.045),
      colors.surface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        TextField(
          controller: controller,
          maxLines: maxLines,
          textInputAction: textInputAction,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: maxLines > 1 ? 18 : 15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagAttributeField({
    required String label,
    required String attributeKey,
    required TextEditingController controller,
    String? hintText,
    bool allowMultiple = false,
    bool showLabel = true,
    bool autoFocus = false,
    VoidCallback? onDone,
  }) {
    return _AttributeTagField(
      label: label,
      attributeKey: attributeKey,
      controller: controller,
      selectedValues: _selectedAttributeTags[attributeKey] ?? const <String>[],
      sharedValues: _sharedAttributeTags[attributeKey] ?? const <String>{},
      allowMultiple: allowMultiple,
      showLabel: showLabel,
      userLogin: widget.userLogin,
      hintText: hintText,
      onChanged: (values) => _setAttributeTags(attributeKey, values),
      onShareChanged: (values) => _setSharedAttributeTags(attributeKey, values),
      autoFocus: autoFocus,
      onDone: onDone,
    );
  }

  String _attributeSummary({
    required String attributeKey,
    required TextEditingController controller,
  }) {
    final selected = _selectedAttributeTags[attributeKey] ?? const <String>[];
    if (selected.isNotEmpty) return selected.join(', ');

    final text = controller.text.trim();
    if (text.isNotEmpty) return text;

    return 'Не заполнено';
  }

  Widget _buildTagAttributeTile({
    required String label,
    required String attributeKey,
    required TextEditingController controller,
    String? hintText,
    bool allowMultiple = false,
  }) {
    final isExpanded = _expandedAttributeKey == attributeKey;

    return _LazyAttributeTile(
      title: label,
      summary: _attributeSummary(
        attributeKey: attributeKey,
        controller: controller,
      ),
      iconAssetName: AppIconAssets.forAttribute(attributeKey),
      fallbackIcon: allowMultiple ? Icons.sell_outlined : Icons.label_outline_rounded,
      expanded: isExpanded,
      showDivider: !_isLastAttribute(attributeKey),
      onTap: () => _toggleAttribute(attributeKey),
      builder: (context) => _buildTagAttributeField(
        label: label,
        attributeKey: attributeKey,
        controller: controller,
        hintText: hintText,
        allowMultiple: allowMultiple,
        showLabel: false,
        autoFocus: isExpanded,
        onDone: () => _goToNextAttribute(attributeKey),
      ),
    );
  }

  Widget _buildNumberAttributeTile({
    required String label,
    required String attributeKey,
    required TextEditingController controller,
    String? hintText,
  }) {
    final value = controller.text.trim();
    final isExpanded = _expandedAttributeKey == attributeKey;

    return _LazyAttributeTile(
      title: label,
      summary: value.isEmpty ? 'Не заполнено' : value,
      iconAssetName: AppIconAssets.forAttribute(attributeKey),
      fallbackIcon: Icons.pin_outlined,
      expanded: isExpanded,
      showDivider: !_isLastAttribute(attributeKey),
      onTap: () => _toggleAttribute(attributeKey),
      builder: (context) => _buildNumberAttributeField(
        label: label,
        controller: controller,
        hintText: hintText,
        autoFocus: isExpanded,
        onDone: () => _goToNextAttribute(attributeKey),
      ),
    );
  }


  Widget _buildNumberAttributeField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    bool autoFocus = false,
    VoidCallback? onDone,
  }) {
    final colors = WildColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        autofocus: autoFocus,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onDone?.call(),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          filled: true,
          fillColor: Color.alphaBlend(
            colors.primary.withValues(alpha: 0.045),
            colors.surface,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildAttributesBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Характеристики растения'),
        _buildTagAttributeTile(
          label: 'Статус определения',
          attributeKey: PlantAttributeKeys.identificationStatus,
          controller: _identificationStatusController,
        ),
        _buildTagAttributeTile(
          label: 'Местообитание',
          attributeKey: PlantAttributeKeys.habitat,
          controller: _habitatController,
          allowMultiple: true,
        ),
        _buildTagAttributeTile(
          label: 'Тип почвы',
          attributeKey: PlantAttributeKeys.soilType,
          controller: _soilTypeController,
          allowMultiple: true,
        ),
        _buildTagAttributeTile(
          label: 'Увлажнение',
          attributeKey: PlantAttributeKeys.moisture,
          controller: _moistureController,
          allowMultiple: true,
        ),
        _buildTagAttributeTile(
          label: 'Освещенность',
          attributeKey: PlantAttributeKeys.lightCondition,
          controller: _lightConditionController,
          allowMultiple: true,
        ),
        _buildTagAttributeTile(
          label: 'Жизненная стадия',
          attributeKey: PlantAttributeKeys.lifeStage,
          controller: _lifeStageController,
        ),
        _buildTagAttributeTile(
          label: 'Фенологическая фаза',
          attributeKey: PlantAttributeKeys.phenophase,
          controller: _phenophaseController,
        ),
        _buildTagAttributeTile(
          label: 'Состояние растения',
          attributeKey: PlantAttributeKeys.plantCondition,
          controller: _plantConditionController,
        ),
        _buildTagAttributeTile(
          label: 'Категория численности',
          attributeKey: PlantAttributeKeys.abundanceCategory,
          controller: _abundanceCategoryController,
        ),
        _buildNumberAttributeTile(
          label: 'Количество особей',
          attributeKey: PlantAttributeKeys.individualCount,
          controller: _individualCountController,
          hintText: 'Например: 1, 5, 20',
        ),
        _buildNumberAttributeTile(
          label: 'Площадь участка, м²',
          attributeKey: PlantAttributeKeys.areaOccupied,
          controller: _areaOccupiedController,
          hintText: 'Например: 0.5, 2, 10',
        ),
        _buildTagAttributeTile(
          label: 'Антропогенное воздействие',
          attributeKey: PlantAttributeKeys.anthropogenicImpact,
          controller: _anthropogenicImpactController,
        ),
        _buildTagAttributeTile(
          label: 'Угрожающий фактор',
          attributeKey: PlantAttributeKeys.threatFactor,
          controller: _threatFactorController,
          allowMultiple: true,
        ),
        _buildTagAttributeTile(
          label: 'Охранный статус',
          attributeKey: PlantAttributeKeys.protectionStatus,
          controller: _protectionStatusController,
        ),
      ],
    );
  }

  void _onTaxonNameQueryChanged(String value) {
    if (_selectedTaxonName != null) return;

    final query = TaxonNameService.normalizeSearchQuery(value);
    _taxonNameSearchDebounce?.cancel();

    if (query.length < 2) {
      setState(() {
        _taxonNameSuggestions = const <TaxonNameSuggestion>[];
        _isTaxonNameSearching = false;
        _taxonNameSearchError = null;
      });
      return;
    }

    _taxonNameSearchDebounce = Timer(
      const Duration(milliseconds: 180),
          () => _searchTaxonNames(query),
    );
  }

  Future<void> _searchTaxonNames(String query) async {
    setState(() {
      _isTaxonNameSearching = true;
      _taxonNameSearchError = null;
    });

    try {
      final suggestions = await TaxonNameService.instance.search(query);
      if (!mounted) return;

      setState(() {
        _taxonNameSuggestions = suggestions;
        _isTaxonNameSearching = false;
        _taxonNameSearchError = suggestions.isEmpty
            ? 'В справочнике нет совпадений. Уточните русское или латинское название.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _taxonNameSuggestions = const <TaxonNameSuggestion>[];
        _isTaxonNameSearching = false;
        _taxonNameSearchError = 'Не удалось загрузить локальный справочник видов.';
      });
    }
  }

  void _selectTaxonName(TaxonNameSuggestion suggestion) {
    final normalized = TaxonNameService.normalizeDisplayName(
      suggestion.acceptedNameRu,
    );

    setState(() {
      _selectedTaxonName = suggestion.copyWith(acceptedNameRu: normalized);
      _nameController.text = normalized;
      _taxonNameSuggestions = const <TaxonNameSuggestion>[];
      _taxonNameSearchError = null;
      _isTaxonNameSearching = false;
    });

    FocusScope.of(context).unfocus();
  }

  void _submitTaxonNameQuery(String value) {
    if (_selectedTaxonName != null) return;

    if (_taxonNameSuggestions.isNotEmpty) {
      _selectTaxonName(_taxonNameSuggestions.first);
      return;
    }

    final query = TaxonNameService.normalizeSearchQuery(value);
    if (query.length >= 2) {
      unawaited(_searchTaxonNames(query));
    }
  }

  void _clearTaxonNameSelection() {
    setState(() {
      _selectedTaxonName = null;
      _nameController.clear();
      _taxonNameSuggestions = const <TaxonNameSuggestion>[];
      _taxonNameSearchError = null;
      _isTaxonNameSearching = false;
    });

    _taxonNameFocusNode.requestFocus();
  }

  Widget _buildTaxonNameSelector() {
    final colors = WildColors.of(context);
    final selected = _selectedTaxonName;
    final fill = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.045),
      colors.surface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Название'),
        if (selected != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _clearTaxonNameSelection,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.acceptedNameRu,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: colors.primaryDark,
                            ),
                          ),
                          if (selected.scientificName.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              selected.scientificName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontStyle: FontStyle.italic,
                                color: colors.muted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            selected.groupLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Выбрать другое название',
                      onPressed: _clearTaxonNameSelection,
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          TextField(
            controller: _nameController,
            focusNode: _taxonNameFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: _onTaxonNameQueryChanged,
            onSubmitted: _submitTaxonNameQuery,
            decoration: InputDecoration(
              hintText: 'Начните вводить русское название...',
              filled: true,
              fillColor: fill,
              suffixIcon: _isTaxonNameSearching
                  ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : Icon(Icons.search_rounded, color: colors.muted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 15,
              ),
            ),
          ),
          if (_taxonNameSearchError != null) ...[
            const SizedBox(height: 8),
            Text(
              _taxonNameSearchError!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.muted,
              ),
            ),
          ],
          if (_taxonNameSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: _taxonNameSuggestions.asMap().entries.map((entry) {
                  final item = entry.value;
                  final isLast = entry.key == _taxonNameSuggestions.length - 1;

                  return InkWell(
                    borderRadius: BorderRadius.vertical(
                      top: entry.key == 0
                          ? const Radius.circular(18)
                          : Radius.zero,
                      bottom: isLast
                          ? const Radius.circular(18)
                          : Radius.zero,
                    ),
                    onTap: () => _selectTaxonName(item),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : Border(
                          bottom: BorderSide(color: colors.border),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.acceptedNameRu,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: colors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.scientificName,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w700,
                              color: colors.muted,
                            ),
                          ),
                          if (item.synonymsRu.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Также: ${item.synonymsRu.take(4).join(', ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildMainObservationPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<int>(
          valueListenable: _photoRevisionNotifier,
          builder: (context, revision, child) => _buildPhotoCarousel(),
        ),
        const SizedBox(height: 26),
        _buildTaxonNameSelector(),
        const SizedBox(height: 26),
        _buildTextInputCard(
          title: 'Описание',
          controller: _descriptionController,
          hintText: 'Свободное описание наблюдения...',
          maxLines: 3,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 28),
        ValueListenableBuilder<int>(
          valueListenable: _attributesRevisionNotifier,
          builder: (context, revision, child) => RepaintBoundary(
            child: _buildAttributesBlock(),
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    WildPageHeader(
                      title: _isEditMode ? 'Редактирование записи' : 'Новая запись',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 18),
                    _buildMainObservationPanel(),
                    const SizedBox(height: 28),
                    ValueListenableBuilder<int>(
                      valueListenable: _locationRevisionNotifier,
                      builder: (context, revision, child) => RepaintBoundary(
                        child: _buildLocationBlock(),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: colors.muted.withValues(alpha: 0.36),
                          disabledForegroundColor: Colors.white70,
                          padding: EdgeInsets.symmetric(
                            vertical: colors.fieldMode ? 22 : 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isSaving
                            ? null
                            : () async {
                          if (!_isManualEntry && !_isLocationFixed) {
                            AppLogger.instance.warning(
                              'AddPlantScreen',
                              'Save button pressed before location is ready',
                              data: {
                                'isManual': _isManualEntry,
                                'isLocationFixed': _isLocationFixed,
                                'hasCurrentPosition': _currentPosition != null,
                              },
                            );

                            _showMessage('Дождитесь определения координат');
                            return;
                          }

                          await _saveObservation();
                        },
                        child: _isSaving
                            ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Сохранение...'),
                          ],
                        )
                            : Text(
                          _isEditMode
                              ? 'Сохранить изменения'
                              : (widget.isGuest
                              ? 'Сохранить локально'
                              : 'Сохранить и отправить'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  String _photoLabelAt(int index) {
    if (index >= 0 && index < _imageLabels.length) {
      final value = _imageLabels[index].trim();
      if (value.isNotEmpty) return value;
    }

    return 'Фото ${index + 1}';
  }


  Widget _buildPhotoCarousel() {
    final colors = WildColors.of(context);
    final hasImages = _images.isNotEmpty;

    return RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: 356,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: Color.alphaBlend(
                    colors.primary.withValues(alpha: 0.045),
                    colors.surface,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: hasImages
                            ? PageView.builder(
                          controller: _pageController,
                          itemCount: _images.length,
                          onPageChanged: _setCurrentPhotoIndex,
                          itemBuilder: (context, index) {
                            return Image.file(
                              _images[index],
                              key: ValueKey<String>('main_photo_${_images[index].path}'),
                              fit: BoxFit.cover,
                              cacheWidth: 1000,
                              filterQuality: FilterQuality.low,
                            );
                          },
                        )
                            : _buildCameraPlaceholder(),
                      ),
                      if (hasImages)
                        Positioned(
                          right: 16,
                          top: 16,
                          child: _roundPhotoButton(
                            icon: Icons.delete_outline,
                            foregroundColor: colors.danger,
                            onTap: () => _removePhoto(_currentPhotoIndex),
                          ),
                        ),
                      if (hasImages)
                        Positioned(
                          left: 16,
                          right: 74,
                          bottom: 16,
                          child: ValueListenableBuilder<int>(
                            valueListenable: _photoIndexNotifier,
                            builder: (context, currentIndex, child) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primaryDark.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    _photoLabelAt(currentIndex),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.surface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _showImageSourceActionSheet(context),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          colors.primary.withValues(alpha: 0.12),
                          colors.surface,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        color: colors.primary,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: hasImages
                        ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _images.length,
                      separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            _pageController.jumpToPage(index);
                            _setCurrentPhotoIndex(index);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutCubic,
                            width: 56,
                            height: 56,
                            padding: EdgeInsets.all(
                              _currentPhotoIndex == index ? 2 : 0,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _currentPhotoIndex == index
                                    ? colors.primary.withValues(alpha: 0.38)
                                    : Colors.transparent,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(
                                _images[index],
                                fit: BoxFit.cover,
                                cacheWidth: 180,
                                cacheHeight: 180,
                                filterQuality: FilterQuality.low,
                              ),
                            ),
                          ),
                        );
                      },
                    )
                        : Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Добавьте фото или пройдите чек-лист',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (hasImages) ...[
                    const SizedBox(width: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: _photoIndexNotifier,
                      builder: (context, currentIndex, child) {
                        return Text(
                          '${currentIndex + 1}/${_images.length}',
                          style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundPhotoButton({
    required IconData icon,
    required VoidCallback onTap,
    Color foregroundColor = const Color(0xFF5D7B79),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: WildColors.of(context).surface.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: foregroundColor),
      ),
    );
  }


  Widget _buildCameraPlaceholder() {
    final colors = WildColors.of(context);

    return Container(
      color: Color.alphaBlend(
        colors.primary.withValues(alpha: 0.05),
        colors.surface,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.not_interested_rounded,
            size: 58,
            color: colors.primary.withValues(alpha: 0.70),
          ),
          const SizedBox(height: 12),
          Text(
            'Фото не прикреплено',
            style: TextStyle(
              color: colors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualCoordinateField({
    required String label,
    required TextEditingController controller,
  }) {
    final colors = WildColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: colors.muted,
          ),
        ),
        const SizedBox(height: 7),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              colors.primary.withValues(alpha: 0.045),
              colors.surface,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 12,
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: colors.primaryDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualMapSelector() {
    final colors = WildColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 196,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _manualMapRevisionNotifier,
                    builder: (context, revision, child) {
                      final point = _manualPoint ??
                          _manualPointFromControllers() ??
                          (_currentPosition == null
                              ? const LatLng(68.9707, 33.0749)
                              : LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ));

                      return FlutterMap(
                        mapController: _manualMapController,
                        options: MapOptions(
                          initialCenter: point,
                          initialZoom: 15,
                          onTap: (_, tappedPoint) => _setManualPointFromMap(tappedPoint),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'ru.mauniver.wildnote',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: point,
                                width: 38,
                                height: 38,
                                child: Icon(
                                  Icons.location_on_rounded,
                                  color: colors.danger,
                                  size: 34,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      child: Text(
                        'Нажмите на карту, чтобы переставить точку',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _locationQualityValue() {
    final progress = _locationProgress;
    if (_isManualEntry || progress == null) return 0;

    final accuracy = progress.accuracy;
    final sampleScore = (progress.usedSampleCount / 6.0).clamp(0.0, 1.0);

    if (accuracy == null || !accuracy.isFinite || accuracy <= 0) {
      return (sampleScore * 0.35).toDouble();
    }

    final accuracyScore = (_targetAccuracyMeters / accuracy).clamp(0.0, 1.0);
    return (accuracyScore * 0.72 + sampleScore * 0.28).clamp(0.0, 1.0).toDouble();
  }

  String _locationQualityTitle() {
    if (_isManualEntry) return 'Ручной ввод';
    final value = _locationQualityValue();

    if (value >= 0.92) return 'Отличный сигнал';
    if (value >= 0.74) return 'Хороший сигнал';
    if (value >= 0.48) return 'Средний сигнал';
    if (_isLocating) return 'Идёт уточнение';
    return 'Слабый сигнал';
  }

  String _locationQualitySubtitle() {
    final progress = _locationProgress;
    if (_isManualEntry) {
      return 'Точность задана пользователем вручную';
    }

    if (progress == null) {
      return 'Дождитесь первых измерений GNSS';
    }

    final rejected = progress.rejectedSpatialOutlierCount;
    final rejectedText = rejected > 0 ? ' • антискачок: $rejected' : '';

    return 'Принято: ${progress.sampleCount} • в расчёте: ${progress.usedSampleCount}$rejectedText';
  }


  Color _locationQualityColor() {
    return WildColors.of(context).primary;
  }


  Widget _buildLocationQualityIndicator() {
    final colors = WildColors.of(context);
    final value = _locationQualityValue();
    final color = _locationQualityColor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.065),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: colors.sunlightContrast ? 0.55 : 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _locationQualityTitle(),
                  style: TextStyle(
                    color: colors.primaryDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          LinearProgressIndicator(
            value: value,
            minHeight: 7,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: Color.alphaBlend(
              colors.primary.withValues(alpha: 0.10),
              colors.surface,
            ),
            color: color,
          ),
          const SizedBox(height: 8),
          Text(
            _locationQualitySubtitle(),
            style: TextStyle(
              color: colors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildLocationBlock() {
    final bool locationReady = _isManualEntry || _isLocationFixed;

    final String coordinatesText = _coordinatesLabel.trim().isEmpty
        ? 'Координаты появятся после фиксации'
        : _coordinatesLabel;

    final String finalAccuracyText = _locationProgress?.accuracy != null
        ? 'Итоговая: ±${_locationProgress!.accuracy!.toStringAsFixed(1)} м'
        : 'Итоговая точность пока неизвестна';

    final String bestAccuracyText = _locationProgress?.bestSampleAccuracy != null
        ? 'Лучшая одиночная: ±${_locationProgress!.bestSampleAccuracy!.toStringAsFixed(1)} м'
        : 'Лучшая одиночная точка пока неизвестна';

    final String targetAccuracyText =
        'Цель: ±${LocationAccuracySettings.formatMeters(_targetAccuracyMeters)} м';

    final colors = WildColors.of(context);
    final borderColor = locationReady
        ? colors.primary.withValues(alpha: 0.36)
        : colors.warning.withValues(alpha: 0.55);

    final container = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon(
                AppIconAssets.geolocation,
                size: 20,
                color: locationReady ? colors.primary : colors.warning,
                fallbackIcon: _isManualEntry
                    ? Icons.edit_location_alt
                    : Icons.gps_fixed,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Местоположение',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: colors.primaryDark,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                'Ручной ввод',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryDark,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _isManualEntry,
                onChanged: (value) => _toggleManualEntry(value),
                activeThumbColor: colors.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isManualEntry) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.045),
                  colors.surface,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      color: colors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Задайте координаты числом или выберите точку на карте.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.22,
                          color: colors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildManualCoordinateField(
                    label: 'Широта',
                    controller: _latController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildManualCoordinateField(
                    label: 'Долгота',
                    controller: _lngController,
                  ),
                ),
              ],
            ),
            _buildManualMapSelector(),
          ] else ...[
            GestureDetector(
              onTap: () {
                if (!_isManualEntry) {
                  _startLocationCapture(reset: false);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    colors.primary.withValues(alpha: 0.045),
                    colors.surface,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Статус: $_geoStatus',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.primaryDark,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      finalAccuracyText,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bestAccuracyText,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      targetAccuracyText,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      coordinatesText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Нажмите, чтобы продолжить уточнение.',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildLocationQualityIndicator(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: _isLocating
                        ? 'Остановить и принять текущее'
                        : 'Продолжить поиск',
                    child: ElevatedButton(
                      onPressed: _isLocating
                          ? _stopAndAcceptCurrentLocation
                          : () => _startLocationCapture(reset: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: colors.fieldMode ? 18 : 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Icon(
                        _isLocating ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: 'Начать заново',
                    child: OutlinedButton(
                      onPressed: _restartLocationCapture,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        padding: EdgeInsets.symmetric(
                          vertical: colors.fieldMode ? 18 : 14,
                        ),
                        side: BorderSide(
                          color: colors.primary,
                          width: 1.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Icon(
                        Icons.restart_alt_rounded,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _locationProgress != null
                  ? 'Принято: ${_locationProgress!.sampleCount} • В расчёте: ${_locationProgress!.usedSampleCount}'
                  '${_locationProgress!.accuracy != null ? ' • ±${_locationProgress!.accuracy!.toStringAsFixed(1)} м' : ''}'
                  : 'Сбор ещё не начат',
              style: TextStyle(
                fontSize: 12,
                color: colors.muted,
              ),
            ),
          ],
        ],
      ),
    );

    if (!_isManualEntry) {
      return container;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        container,
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Точка будет отмечена как введенная вручную.',
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              color: colors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

}





class _LazyAttributeTile extends StatelessWidget {
  final String title;
  final String summary;
  final String iconAssetName;
  final IconData fallbackIcon;
  final bool expanded;
  final bool showDivider;
  final VoidCallback onTap;
  final WidgetBuilder builder;

  const _LazyAttributeTile({
    required this.title,
    required this.summary,
    required this.iconAssetName,
    required this.fallbackIcon,
    required this.expanded,
    required this.showDivider,
    required this.onTap,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final filled = summary != 'Не заполнено';
    final colors = WildColors.of(context);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.zero,
            splashColor: colors.primary.withValues(alpha: 0.06),
            highlightColor: colors.primary.withValues(alpha: 0.03),
            hoverColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        colors.primary.withValues(alpha: 0.12),
                        colors.surface,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: AppSvgIcon(
                      iconAssetName,
                      size: 17,
                      color: colors.primary,
                      fallbackIcon: fallbackIcon,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: colors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          summary,
                          maxLines: expanded ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.12,
                            fontWeight:
                            filled ? FontWeight.w700 : FontWeight.w500,
                            color: filled ? colors.primary : colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: expanded
              ? Padding(
            key: ValueKey<String>('expanded_$title'),
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
            child: builder(context),
          )
              : const SizedBox.shrink(),
        ),
        if (showDivider) Divider(height: 1, color: colors.border),
      ],
    );
  }
}

class _AttributeOptionUi {
  final String value;
  final bool isBuiltin;
  final bool isDeleted;
  final String? createdBy;
  final int? remoteId;

  const _AttributeOptionUi({
    required this.value,
    required this.isBuiltin,
    required this.isDeleted,
    this.createdBy,
    this.remoteId,
  });

  bool isOwn(String userLogin) {
    final author = createdBy?.trim().toLowerCase();
    return author != null && author == userLogin.trim().toLowerCase();
  }

  bool canDeleteFromCommon(String userLogin) {
    return !isBuiltin && remoteId != null && isOwn(userLogin);
  }
}

class _AttributeTagField extends StatefulWidget {
  final String label;
  final String attributeKey;
  final TextEditingController controller;
  final List<String> selectedValues;
  final Set<String> sharedValues;
  final bool allowMultiple;
  final bool showLabel;
  final String userLogin;
  final String? hintText;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<Set<String>> onShareChanged;
  final bool autoFocus;
  final VoidCallback? onDone;

  const _AttributeTagField({
    required this.label,
    required this.attributeKey,
    required this.controller,
    required this.selectedValues,
    required this.sharedValues,
    required this.allowMultiple,
    required this.showLabel,
    required this.userLogin,
    required this.onChanged,
    required this.onShareChanged,
    this.autoFocus = false,
    this.onDone,
    this.hintText,
  });

  @override
  State<_AttributeTagField> createState() => _AttributeTagFieldState();
}

class _AttributeTagFieldState extends State<_AttributeTagField> {
  final FocusNode _focusNode = FocusNode();
  final List<_AttributeOptionUi> _options = <_AttributeOptionUi>[];
  late List<String> _selected;
  late Set<String> _sharedPending;
  Timer? _debounce;
  bool _isFocused = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selected = _cleanValues(widget.selectedValues);
    _sharedPending = widget.sharedValues
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);

    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AttributeTagField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedValues != widget.selectedValues) {
      _selected = _cleanValues(widget.selectedValues);
    }

    if (oldWidget.sharedValues != widget.sharedValues) {
      _sharedPending = widget.sharedValues
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    if (!oldWidget.autoFocus && widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _cleanValues(Iterable<String> values) {
    final result = <String>[];

    for (final item in values) {
      final value = item.trim();
      if (value.isNotEmpty && !result.any((e) => _sameValue(e, value))) {
        result.add(value);
      }
    }

    return result;
  }

  bool _rowBool(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == true || value == 1 || value == '1') return true;
    return false;
  }

  int? _rowInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_loadOptions(search: widget.controller.text));
    });

    if (mounted) {
      setState(() {});
    }
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _isFocused = _focusNode.hasFocus);

    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          alignment: 0.12,
          curve: Curves.easeOutCubic,
        );
      });
      unawaited(_loadOptions(search: widget.controller.text));
    }
  }

  Future<void> _loadOptions({String? search}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final rows = await DatabaseHelper.instance.getAttributeOptions(
        attributeKey: widget.attributeKey,
        search: search,
        limit: 14,
      );

      final options = <_AttributeOptionUi>[];
      for (final row in rows) {
        final value = row['value']?.toString().trim() ?? '';
        if (value.isEmpty || value == 'Другое') continue;

        options.add(
          _AttributeOptionUi(
            value: value,
            isBuiltin: _rowBool(row, 'is_builtin'),
            isDeleted: _rowBool(row, 'is_deleted'),
            createdBy: row['created_by']?.toString().trim(),
            remoteId: _rowInt(row, 'remote_id'),
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _options
          ..clear()
          ..addAll(_cleanOptions(options));
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<_AttributeOptionUi> _cleanOptions(Iterable<_AttributeOptionUi> values) {
    final result = <_AttributeOptionUi>[];

    for (final item in values) {
      if (item.value.trim().isEmpty || item.isDeleted) continue;
      if (!result.any((e) => _sameValue(e.value, item.value))) {
        result.add(item);
      }
    }

    return result;
  }

  bool _sameValue(String a, String b) {
    return DatabaseHelper.instance.normalizeOptionValue(a) ==
        DatabaseHelper.instance.normalizeOptionValue(b);
  }

  bool _containsValue(Iterable<String> values, String value) {
    return values.any((item) => _sameValue(item, value));
  }

  _AttributeOptionUi? _optionForValue(String value) {
    for (final option in _options) {
      if (_sameValue(option.value, value)) return option;
    }
    return null;
  }

  void _commitLocal(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;

    setState(() {
      if (widget.allowMultiple) {
        if (!_containsValue(_selected, value)) {
          _selected.add(value);
        }
      } else {
        _selected = <String>[value];
      }

      widget.controller.clear();
    });

    widget.onChanged(List<String>.unmodifiable(_selected));
  }

  void _commitAndMarkForShare(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;

    _commitLocal(value);

    setState(() {
      _sharedPending.add(value);
    });

    widget.onShareChanged(Set<String>.unmodifiable(_sharedPending));

    _showWildTopMessage(
      context,
      '«$value» будет добавлено в общий список при сохранении',
    );
  }

  void _removeSelectedOnly(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _selected.removeWhere((item) => _sameValue(item, trimmed));
      _sharedPending.removeWhere((item) => _sameValue(item, trimmed));
    });

    widget.onChanged(List<String>.unmodifiable(_selected));
    widget.onShareChanged(Set<String>.unmodifiable(_sharedPending));
  }

  Future<void> _deleteOwnPublishedOption(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _selected.removeWhere((item) => _sameValue(item, trimmed));
      _sharedPending.removeWhere((item) => _sameValue(item, trimmed));
      _options.removeWhere((item) => _sameValue(item.value, trimmed));
    });

    widget.onChanged(List<String>.unmodifiable(_selected));
    widget.onShareChanged(Set<String>.unmodifiable(_sharedPending));

    final result = await GeoportalSyncService.instance.deleteAttributeOption(
      attributeKey: widget.attributeKey,
      value: trimmed,
    );

    if (!mounted) return;

    if (result.success) {
      _showWildTopMessage(context, 'Вариант убран из общего списка');
    } else {
      _showWildTopMessage(context, result.message);
    }
  }

  void _handleSelectedDelete(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    if (_containsValue(_sharedPending, trimmed)) {
      _removeSelectedOnly(trimmed);
      return;
    }

    final option = _optionForValue(trimmed);
    if (option != null && option.canDeleteFromCommon(widget.userLogin)) {
      unawaited(_deleteOwnPublishedOption(trimmed));
      return;
    }

    _removeSelectedOnly(trimmed);
  }

  List<_AttributeOptionUi> _visibleSuggestions() {
    final query = widget.controller.text.trim();

    final filtered = query.isEmpty
        ? _options
        : _options
        .where(
          (item) => item.value.toLowerCase().contains(query.toLowerCase()),
    )
        .toList();

    return filtered
        .where((item) => !_containsValue(_selected, item.value))
        .take(10)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);
    final input = widget.controller.text.trim();
    final suggestions = _visibleSuggestions();
    final canShare = input.isNotEmpty &&
        !_options.any((option) => _sameValue(option.value, input)) &&
        !_containsValue(_sharedPending, input);
    final isMarkedForShare =
        input.isNotEmpty && _containsValue(_sharedPending, input);
    final fill = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.045),
      colors.surface,
    );
    final chipFill = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.075),
      colors.surface,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showLabel) ...[
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_selected.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _selected
                      .map(
                        (value) => InputChip(
                      label: Text(value),
                      labelStyle: TextStyle(
                        color: colors.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                      backgroundColor: chipFill,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      deleteIcon: Icon(
                        Icons.close,
                        size: 17,
                        color: colors.primary,
                      ),
                      onDeleted: () => _handleSelectedDelete(value),
                      materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                      .toList(),
                ),
                const SizedBox(height: 8),
              ],
              DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) {
                    _commitLocal(value);
                    widget.onDone?.call();
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText ??
                        (widget.allowMultiple
                            ? 'Выберите несколько или напишите'
                            : 'Выберите или напишите'),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Добавить в общий список при сохранении',
                      onPressed:
                      canShare ? () => _commitAndMarkForShare(input) : null,
                      icon: Icon(
                        isMarkedForShare
                            ? Icons.add_circle
                            : Icons.add_circle_outline,
                        color: canShare || isMarkedForShare
                            ? colors.primary
                            : colors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              if (canShare || isMarkedForShare) ...[
                const SizedBox(height: 6),
                Text(
                  isMarkedForShare
                      ? 'Будет добавлено в общий словарь при сохранении'
                      : 'Нажмите +, чтобы добавить вариант в общий словарь',
                  style: TextStyle(
                    fontSize: 11,
                    color: isMarkedForShare ? colors.primary : colors.muted,
                    fontWeight:
                    isMarkedForShare ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
              if (_isFocused && (_isLoading || suggestions.isNotEmpty)) ...[
                const SizedBox(height: 8),
                if (_isLoading)
                  SizedBox(
                    height: 22,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                      itemCount: suggestions.length,
                      separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final option = suggestions[index];
                        final canDelete =
                        option.canDeleteFromCommon(widget.userLogin);

                        return InputChip(
                          label: Text(option.value),
                          labelStyle: TextStyle(
                            color: colors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                          backgroundColor: chipFill,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          onPressed: () => _commitLocal(option.value),
                          onDeleted: canDelete
                              ? () => _deleteOwnPublishedOption(option.value)
                              : null,
                          materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
