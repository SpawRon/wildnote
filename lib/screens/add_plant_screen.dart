import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../data/database_helper.dart';
import '../services/geoportal_sync_service.dart';
import 'dart:async';
import '../services/location_capture_service.dart';
import '../services/gauss_kruger_service.dart';
import '../services/app_logger.dart';

class AddPlantScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;
  final VoidCallback? onSaved;


  const AddPlantScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
    this.onSaved,
  });

  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen>
    with WidgetsBindingObserver {
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();

  final TextEditingController _nameController = TextEditingController();
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
  int _currentPhotoIndex = 0;

  String _geoStatus = "Инициализация ГЛОНАСС...";
  String _coordinatesLabel = "Ожидание данных...";
  bool _isLocationFixed = false;
  bool _isManualEntry = false;
  bool _isSaving = false;
  Position? _currentPosition;

  StreamSubscription<PreciseLocationProgress>? _locationSubscription;
  PreciseLocationProgress? _locationProgress;
  bool _isLocating = false;



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLocationCapture(reset: true);
    if (!widget.isGuest) {
      unawaited(
        GeoportalSyncService.instance.syncAttributeOptions(
          userLogin: widget.userLogin,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _locationSubscription?.cancel();
    unawaited(_locationService.dispose());

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
    _pageController.dispose();

    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isManualEntry) {
      _startLocationCapture(reset: false);
    }
  }
  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (pickedFile == null || !mounted) return;

      setState(() {
        _images.add(File(pickedFile.path));
        _currentPhotoIndex = _images.length - 1;
      });

      AppLogger.instance.info(
        'AddPlantScreen',
        'Photo added',
        data: {
          'source': source.name,
          'photoCount': _images.length,
          'path': pickedFile.path,
        },
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && _images.isNotEmpty) {
          _pageController.jumpToPage(_images.length - 1);
        }
      });
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

  Future<void> _toggleManualEntry(bool value) async {
    if (value) {
      await _locationService.stopAndKeepBest(
        reason: 'Переключено на ручной ввод.',
      );
    }

    if (!mounted) return;

    setState(() {
      _isManualEntry = value;
      _isLocating = false;

      if (_isManualEntry) {
        _geoStatus = "Ручной ввод координат";

        if (_currentPosition != null) {
          _latController.text = _currentPosition!.latitude.toStringAsFixed(7);
          _lngController.text = _currentPosition!.longitude.toStringAsFixed(7);
        }
      }
    });

    if (!value) {
      await _startLocationCapture(reset: false);
    }
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

    await _locationSubscription?.cancel();

    _locationSubscription = _locationService.progressStream.listen((progress) {
      if (!mounted) return;

      setState(() {
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
      });
    });

    try {
      setState(() {
        _isLocating = true;
        if (reset) {
          _isLocationFixed = false;
          _currentPosition = null;
          _locationProgress = null;
          _coordinatesLabel = "Ожидание данных...";
          _geoStatus = "Идёт точная фиксация координат...";
        }
      });

      await _locationService.startCapture(
        config: const PreciseLocationConfig(
          maxAcceptedAccuracyMeters: 60,
          acceptableSaveAccuracyMeters: 35,
          targetAccuracyMeters: 15,
          minSamples: 3,
          maxBestPointsUsed: 6,
          requestTimeout: Duration(seconds: 3),
          requestInterval: Duration(milliseconds: 600),
          maxSessionDuration: Duration(seconds: 70),
          autoStopWhenTargetReached: true,
        ),
        reset: reset,
      );
    } catch (e, st) {
      AppLogger.instance.error(
        'AddPlantScreen',
        'Location capture start failed',
        error: e,
        stackTrace: st,
      );

      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _geoStatus = e.toString();
      });
    }
  }

  Future<void> _stopAndAcceptCurrentLocation() async {
    final progress = await _locationService.stopAndKeepBest(
      reason: 'Фиксация остановлена пользователем.',
    );

    if (!mounted) return;

    setState(() {
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
    });

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

      if (_nameController.text.trim().isEmpty) {
        AppLogger.instance.warning(
          'AddPlantScreen',
          'Save blocked: empty plant name',
        );
        _showMessage('Введите название растения');
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
          AppLogger.instance.warning(
            'AddPlantScreen',
            'Save blocked: current position is null',
          );
          _showMessage('Сначала дождитесь определения геолокации');
          return;
        }

        latitude = _currentPosition!.latitude;
        longitude = _currentPosition!.longitude;
        accuracy = _currentPosition!.accuracy;
      }

      if (!_isManualEntry &&
          (_currentPosition == null || _currentPosition!.accuracy > 35)) {
        AppLogger.instance.warning(
          'AddPlantScreen',
          'Save blocked: accuracy is not enough',
          data: {
            'accuracy': _currentPosition?.accuracy,
            'limit': 35,
          },
        );

        _showMessage(
          'Точность пока недостаточная. Продолжите фиксацию, нажмите "Остановить и принять текущее" или введите координаты вручную.',
        );
        return;
      }

      double? gaussX;
      double? gaussY;
      int? zone;

      if (latitude != null && longitude != null) {
        try {
          final gk = await _gaussKrugerService.transform(
            latitude: latitude,
            longitude: longitude,
          );

          gaussX = gk.x;
          gaussY = gk.y;
          zone = gk.zone;

          AppLogger.instance.info(
            'AddPlantScreen',
            'Gauss-Kruger transform completed',
            data: {
              'zone': zone,
              'hasGaussX': gaussX != null,
              'hasGaussY': gaussY != null,
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
      }

      final createdAt = DateTime.now().toIso8601String();

      final observation = {
        'user_login': widget.userLogin,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'is_manual': _isManualEntry ? 1 : 0,
        'accuracy': accuracy,
        'created_at': createdAt,
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

      final attributes = _collectAttributes();

      final observationId = await DatabaseHelper.instance.insertObservation(
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

      String message = widget.isGuest
          ? 'Запись сохранена локально'
          : 'Запись добавлена в очередь на отправку';

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
          message = 'Запись отправлена на геопортал';
        } else {
          message = 'Сохранено локально. ${syncResult.message}';
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      widget.onSaved?.call();
      _clearForm();
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
      _currentPhotoIndex = 0;
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
      _isManualEntry = false;
      _isLocationFixed = false;
      _coordinatesLabel = "Ожидание данных...";
      _geoStatus = "Инициализация ГЛОНАСС...";
      _currentPosition = null;
    });

    _startLocationCapture(reset: true);
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

    setState(() {
      _images.removeAt(index);

      if (_images.isEmpty) {
        _currentPhotoIndex = 0;
      } else if (_currentPhotoIndex >= _images.length) {
        _currentPhotoIndex = _images.length - 1;
      }
    });
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: Color(0xFF5D7B79),
              ),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFF5D7B79),
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

    addText(PlantAttributeKeys.plantName, _nameController);
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
    _selectedAttributeTags[key] = values;
  }

  void _setSharedAttributeTags(String key, Set<String> values) {
    if (values.isEmpty) {
      _sharedAttributeTags.remove(key);
    } else {
      _sharedAttributeTags[key] = values;
    }
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF131D1C),
        ),
      ),
    );
  }

  Widget _buildTagAttributeField({
    required String label,
    required String attributeKey,
    required TextEditingController controller,
    String? hintText,
    bool allowMultiple = false,
  }) {
    return _AttributeTagField(
      label: label,
      attributeKey: attributeKey,
      controller: controller,
      selectedValues: _selectedAttributeTags[attributeKey] ?? const <String>[],
      sharedValues: _sharedAttributeTags[attributeKey] ?? const <String>{},
      allowMultiple: allowMultiple,
      userLogin: widget.userLogin,
      hintText: hintText,
      onChanged: (values) => _setAttributeTags(attributeKey, values),
      onShareChanged: (values) => _setSharedAttributeTags(attributeKey, values),
    );
  }

  Widget _buildNumberAttributeField({
    required String label,
    required TextEditingController controller,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
        ),
      ),
    );
  }

  Widget _buildAttributesBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Характеристики растения'),
          _buildTagAttributeField(
            label: 'Статус определения',
            attributeKey: PlantAttributeKeys.identificationStatus,
            controller: _identificationStatusController,
          ),
          _buildTagAttributeField(
            label: 'Местообитание',
            attributeKey: PlantAttributeKeys.habitat,
            controller: _habitatController,
            allowMultiple: true,
          ),
          _buildTagAttributeField(
            label: 'Тип почвы',
            attributeKey: PlantAttributeKeys.soilType,
            controller: _soilTypeController,
            allowMultiple: true,
          ),
          _buildTagAttributeField(
            label: 'Увлажнение',
            attributeKey: PlantAttributeKeys.moisture,
            controller: _moistureController,
            allowMultiple: true,
          ),
          _buildTagAttributeField(
            label: 'Освещенность',
            attributeKey: PlantAttributeKeys.lightCondition,
            controller: _lightConditionController,
            allowMultiple: true,
          ),
          _buildTagAttributeField(
            label: 'Жизненная стадия',
            attributeKey: PlantAttributeKeys.lifeStage,
            controller: _lifeStageController,
          ),
          _buildTagAttributeField(
            label: 'Фенологическая фаза',
            attributeKey: PlantAttributeKeys.phenophase,
            controller: _phenophaseController,
          ),
          _buildTagAttributeField(
            label: 'Состояние растения',
            attributeKey: PlantAttributeKeys.plantCondition,
            controller: _plantConditionController,
          ),
          _buildTagAttributeField(
            label: 'Категория численности',
            attributeKey: PlantAttributeKeys.abundanceCategory,
            controller: _abundanceCategoryController,
          ),
          _buildNumberAttributeField(
            label: 'Количество особей',
            controller: _individualCountController,
            hintText: 'Например: 1, 5, 20',
          ),
          _buildNumberAttributeField(
            label: 'Площадь участка, м²',
            controller: _areaOccupiedController,
            hintText: 'Например: 0.5, 2, 10',
          ),
          _buildTagAttributeField(
            label: 'Антропогенное воздействие',
            attributeKey: PlantAttributeKeys.anthropogenicImpact,
            controller: _anthropogenicImpactController,
          ),
          _buildTagAttributeField(
            label: 'Угрожающий фактор',
            attributeKey: PlantAttributeKeys.threatFactor,
            controller: _threatFactorController,
            allowMultiple: true,
          ),
          _buildTagAttributeField(
            label: 'Охранный статус',
            attributeKey: PlantAttributeKeys.protectionStatus,
            controller: _protectionStatusController,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool locationReady = _isManualEntry || _isLocationFixed;

    return Scaffold(
      backgroundColor: const Color(0xFFEBEAE0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          children: [
            const Text(
              "Новая запись",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            _buildPhotoCarousel(),

            const SizedBox(height: 25),

            const Text(
              'Название',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Введите название...',
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Описание',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Свободное описание наблюдения...',
              ),
            ),

            const SizedBox(height: 20),

            _buildAttributesBlock(),

            const SizedBox(height: 20),

            _buildLocationBlock(),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF131D1C),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade500,
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                  if (!_isManualEntry && !locationReady) {
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
                  widget.isGuest
                      ? 'Сохранить локально'
                      : 'Сохранить и отправить',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCarousel() {
    final hasImages = _images.isNotEmpty;

    return Container(
      width: double.infinity,
      height: 330,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: hasImages
                      ? PageView.builder(
                    controller: _pageController,
                    itemCount: _images.length,
                    onPageChanged: (i) =>
                        setState(() => _currentPhotoIndex = i),
                    itemBuilder: (context, index) {
                      return Image.file(
                        _images[index],
                        fit: BoxFit.cover,
                        cacheWidth: 1200,
                      );
                    },
                  )
                      : _buildCameraPlaceholder(),
                ),
                if (hasImages)
                  Positioned(
                    right: 14,
                    top: 14,
                    child: _roundPhotoButton(
                      icon: Icons.delete_outline,
                      foregroundColor: Colors.redAccent,
                      onTap: () => _removePhoto(_currentPhotoIndex),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: 88,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F8F3),
              border: Border(
                top: BorderSide(color: Color(0xFFE1E5DC)),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _showImageSourceActionSheet(context),
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF0E8),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Color(0xFF5D7B79),
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: hasImages
                      ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final selected = index == _currentPhotoIndex;
                      return GestureDetector(
                        onTap: () {
                          _pageController.jumpToPage(index);
                          setState(() => _currentPhotoIndex = index);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF5D7B79)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            image: DecorationImage(
                              image: FileImage(_images[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                      : const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Добавьте фотографии растения',
                      style: TextStyle(
                        color: Color(0xFF5D7B79),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (hasImages) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_currentPhotoIndex + 1}/${_images.length}',
                    style: const TextStyle(
                      color: Color(0xFF5D7B79),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: foregroundColor),
      ),
    );
  }

  Widget _buildCameraPlaceholder() {
    return Container(
      color: const Color(0xFFF1F2EC),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_camera_back_outlined,
            size: 56,
            color: Color(0xFF8CA09D),
          ),
          SizedBox(height: 12),
          Text(
            'Фото наблюдения',
            style: TextStyle(
              color: Color(0xFF5D7B79),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'добавьте снимок снизу',
            style: TextStyle(color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBlock() {
    final bool locationReady = _isManualEntry || _isLocationFixed;

    final String smallCoords = _currentPosition != null
        ? 'Ш: ${_currentPosition!.latitude.toStringAsFixed(5)}'
        ' · Д: ${_currentPosition!.longitude.toStringAsFixed(5)}'
        : 'Координаты появятся после фиксации';

    final String finalAccuracyText = _locationProgress?.accuracy != null
        ? 'Итоговая: ±${_locationProgress!.accuracy!.toStringAsFixed(1)} м'
        : 'Итоговая точность пока неизвестна';

    final String bestAccuracyText = _locationProgress?.bestSampleAccuracy != null
        ? 'Лучшая одиночная: ±${_locationProgress!.bestSampleAccuracy!.toStringAsFixed(1)} м'
        : 'Лучшая одиночная точка пока неизвестна';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: locationReady ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isManualEntry ? Icons.edit_location_alt : Icons.gps_fixed,
                    color: locationReady ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Местоположение",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    "Ручной ввод",
                    style: TextStyle(fontSize: 12),
                  ),
                  Switch(
                    value: _isManualEntry,
                    onChanged: (value) => _toggleManualEntry(value),
                    activeColor: const Color(0xFF5D7B79),
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          if (_isManualEntry) ...[
            TextField(
              controller: _latController,
              decoration: const InputDecoration(
                labelText: "Ш:",
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _lngController,
              decoration: const InputDecoration(
                labelText: "Д:",
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Точка будет помечена как введённая вручную',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: () {
                if (!_isManualEntry) {
                  _startLocationCapture(reset: false);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Статус: $_geoStatus",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      finalAccuracyText,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bestAccuracyText,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      smallCoords,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey[500],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Нажмите, чтобы продолжить уточнение',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                        backgroundColor: const Color(0xFF5D7B79),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                        foregroundColor: const Color(0xFF5D7B79),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(
                          color: Color(0xFF5D7B79),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ],
      ),
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
  final String userLogin;
  final String? hintText;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<Set<String>> onShareChanged;

  const _AttributeTagField({
    required this.label,
    required this.attributeKey,
    required this.controller,
    required this.selectedValues,
    required this.sharedValues,
    required this.allowMultiple,
    required this.userLogin,
    required this.onChanged,
    required this.onShareChanged,
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
    setState(() => _isLoading = true);

    try {
      final rows = await DatabaseHelper.instance.getAttributeOptions(
        attributeKey: widget.attributeKey,
        search: search,
        limit: 18,
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('«$value» будет добавлено в общий список при сохранении'),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вариант убран из общего списка')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
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
        .take(12)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.controller.text.trim();
    final suggestions = _visibleSuggestions();
    final canShare = input.isNotEmpty &&
        !_options.any((option) => _sameValue(option.value, input)) &&
        !_containsValue(_sharedPending, input);
    final isMarkedForShare =
        input.isNotEmpty && _containsValue(_sharedPending, input);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF131D1C),
                ),
              ),
              const SizedBox(height: 8),
              if (_selected.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _selected
                      .map(
                        (value) => InputChip(
                      label: Text(value),
                      deleteIcon: const Icon(Icons.close, size: 17),
                      onDeleted: () => _handleSelectedDelete(value),
                      materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                      .toList(),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.done,
                onSubmitted: _commitLocal,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.hintText ??
                      (widget.allowMultiple
                          ? 'Выберите несколько вариантов или напишите свой'
                          : 'Выберите вариант или напишите свой'),
                  suffixIcon: IconButton(
                    tooltip: 'Добавить в общий список при сохранении',
                    onPressed:
                    canShare ? () => _commitAndMarkForShare(input) : null,
                    icon: Icon(
                      isMarkedForShare
                          ? Icons.add_circle
                          : Icons.add_circle_outline,
                      color: canShare || isMarkedForShare
                          ? const Color(0xFF2E7D32)
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
              if (_isFocused && (_isLoading || suggestions.isNotEmpty)) ...[
                const SizedBox(height: 8),
                if (_isLoading)
                  const SizedBox(
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
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final option = suggestions[index];
                        final canDelete =
                        option.canDeleteFromCommon(widget.userLogin);

                        return InputChip(
                          label: Text(option.value),
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
