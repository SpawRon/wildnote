import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../data/database_helper.dart';
import 'dart:io';

class AddPlantScreen extends StatefulWidget {
  final bool isGuest;
  const AddPlantScreen({super.key, required this.isGuest});

  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen> {
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();
  int _currentPhotoIndex = 0;

  String _geoStatus = "Инициализация ГЛОНАСС...";
  String _coordinatesLabel = "Ожидание данных...";
  bool _isLocationFixed = false;
  Position? _currentPosition;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  @override
  void initState() {
    super.initState();
    _getRealLocation();
  }
  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80, // сжвтие для оптимизации
      );

      if (pickedFile != null) {
        setState(() {
          _images.add(File(pickedFile.path));
          _currentPhotoIndex = _images.length - 1; // смпна на новое фото
        });
      }
    } catch (e) {
      debugPrint("Ошибка выбора фото: $e");
    }
  }

  bool _isManualEntry = false;
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

// Метод для переключения режима
  void _toggleManualEntry(bool value) {
    setState(() {
      _isManualEntry = value;
      if (_isManualEntry) {
        _geoStatus = "Ручной ввод координат";
      } else {
        _getRealLocation(); // Возвращаемся к GPS
      }
    });
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) =>
          SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(
                      Icons.camera_alt, color: Color(0xFF5D7B79)),
                  title: const Text('Сделать фото'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(
                      Icons.photo_library, color: Color(0xFF5D7B79)),
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

  Future<void> _getRealLocation() async {
    setState(() => _geoStatus = "Проверка разрешений...");

    bool serviceEnabled;
    LocationPermission permission;
    // GPS на телефоне
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _geoStatus = "Ошибка: Включите GPS");
      return;
    }

    // разрешения приложения
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _geoStatus = "Ошибка: Нет прав на локацию");
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _geoStatus = "Ошибка: Права запрещены навсегда");
      return;
    }
    setState(() => _geoStatus = "Поиск спутников...");
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);

    setState(() {
      _currentPosition = position;
      _isLocationFixed = true;
      _geoStatus =
      "Фиксация успешна. Точность: ±${position.accuracy.toStringAsFixed(1)}м";
      _coordinatesLabel =
      "Шир: ${position.latitude}, Долг: ${position.longitude}";
    });
  }

  void _addPhotoMock() {
    setState(() {
      // заглушка путь временный
      _images.add(File("https://placeholder.com/photo${_images.length}"));
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _images.removeAt(index);
      if (_currentPhotoIndex >= _images.length && _images.isNotEmpty) {
        _currentPhotoIndex = _images.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEBEAE0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Новая запись",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              _buildPhotoCarousel(),

              const SizedBox(height: 25),

              // ввод
              const Text('Название',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Введите название...',
                ),
              ),

              const SizedBox(height: 16),
              const Text('Описание',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const TextField(
                maxLines: 3,
                decoration: InputDecoration(hintText: 'Состояние, почва...'),
              ),

              const SizedBox(height: 20),

              _buildLocationBlock(),

              const SizedBox(height: 30),

              // Кнопка действия
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF131D1C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isLocationFixed ? () {} : null,
                  child: Text(widget.isGuest
                      ? "Сохранить локально"
                      : "Отправить на Геопортал"),
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
                onPageChanged: (i) => setState(() => _currentPhotoIndex = i),
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
              // Кнопка удаления на текущем фото
              Positioned(
                top: 10,
                right: 15,
                child: CircleAvatar(
                  backgroundColor: Colors.red.withOpacity(0.8),
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () => _removePhoto(_currentPhotoIndex),
                  ),
                ),
              ),
              // Индикатор страниц
              Positioned(
                bottom: 15,
                left: 0,
                right: 0,
                child: Center(
                  child: Text("${_currentPhotoIndex + 1} / ${_images.length}",
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 4)])),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 10),
        //  лента
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Камера всегда первая
              GestureDetector(
                onTap: () => _showImageSourceActionSheet(context),
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5D7B79),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
              ),
              // Остальные фото
              ...List.generate(5, (index) =>
                  Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Icon(Icons.image, color: Colors.grey),
                  )),
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
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 50, color: Colors.grey),
          SizedBox(height: 10),
          Text("Добавьте фотографии растения",
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLocationBlock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isLocationFixed ? Colors.green.shade200 : Colors.orange
              .shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок с иконкой и переключателем
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isManualEntry ? Icons.edit_location_alt : Icons.gps_fixed,
                    color: _isLocationFixed ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  const Text("Местоположение",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                children: [
                  const Text("Ручной ввод", style: TextStyle(fontSize: 12)),
                  Switch(
                    value: _isManualEntry,
                    onChanged: _toggleManualEntry,
                    activeColor: const Color(0xFF5D7B79),
                  ),
                ],
              ),
            ],
          ),
          const Divider(),

          // Контент в зависимости от режима
          if (_isManualEntry) ...[
            TextField(
              controller: _latController,
              decoration: const InputDecoration(
                  labelText: "Широта (Lat)", isDense: true),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _lngController,
              decoration: const InputDecoration(
                  labelText: "Долгота (Lng)", isDense: true),
              keyboardType: TextInputType.number,
            ),
          ] else
            ...[
              Text(
                _coordinatesLabel,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Статус: $_geoStatus",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}
