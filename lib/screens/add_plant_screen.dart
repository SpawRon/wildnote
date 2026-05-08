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

      final observationId = await DatabaseHelper.instance.insertObservation(
        observation: observation,
        photoPaths: photoPaths,
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
      _isManualEntry = false;
      _isLocationFixed = false;
      _coordinatesLabel = "Ожидание данных...";
      _geoStatus = "Инициализация ГЛОНАСС...";
      _currentPosition = null;
    });

    _startLocationCapture(reset: true);
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

  @override
  Widget build(BuildContext context) {
    final bool locationReady = _isManualEntry || _isLocationFixed;

    return Scaffold(
      backgroundColor: const Color(0xFFEBEAE0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  hintText: 'Состояние, почва...',
                ),
              ),

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
      ),
    );
  }

  Widget _buildPhotoCarousel() {
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: _images.isEmpty
              ? _buildCameraPlaceholder()
              : Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: _images.length,
                onPageChanged: (i) =>
                    setState(() => _currentPhotoIndex = i),
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(20),
                      image: DecorationImage(
                        image: FileImage(_images[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 10,
                right: 15,
                child: CircleAvatar(
                  backgroundColor: Colors.red.withOpacity(0.8),
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete,
                      color: Colors.white,
                    ),
                    onPressed: () => _removePhoto(_currentPhotoIndex),
                  ),
                ),
              ),
              Positioned(
                bottom: 15,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    "${_currentPhotoIndex + 1} / ${_images.length}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: () => _showImageSourceActionSheet(context),
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5D7B79),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                  ),
                ),
              ),
              ...List.generate(_images.length, (index) {
                return GestureDetector(
                  onTap: () {
                    _pageController.jumpToPage(index);
                    setState(() => _currentPhotoIndex = index);
                  },
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentPhotoIndex == index
                            ? const Color(0xFF5D7B79)
                            : Colors.grey.shade300,
                        width: 2,
                      ),
                      image: DecorationImage(
                        image: FileImage(_images[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPlaceholder() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 50,
            color: Colors.grey,
          ),
          SizedBox(height: 10),
          Text(
            "Добавьте фотографии растения",
            style: TextStyle(color: Colors.grey),
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