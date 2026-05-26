import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../theme/app_theme.dart';

class ObservationDetailBadge {
  final IconData icon;
  final String text;
  final Color? color;

  const ObservationDetailBadge({
    required this.icon,
    required this.text,
    this.color,
  });
}

class ObservationDetailData {
  final String title;
  final String? description;
  final List<String> photos;
  final Future<List<String>>? photosFuture;
  final Map<String, dynamic> attributes;
  final Map<String, String>? imageHeaders;
  final List<ObservationDetailBadge> badges;
  final List<MapEntry<String, String>> technicalRows;

  const ObservationDetailData({
    required this.title,
    required this.photos,
    required this.attributes,
    this.description,
    this.photosFuture,
    this.imageHeaders,
    this.badges = const [],
    this.technicalRows = const [],
  });
}

class ObservationDetailScreen extends StatefulWidget {
  final ObservationDetailData data;

  const ObservationDetailScreen({
    super.key,
    required this.data,
  });

  @override
  State<ObservationDetailScreen> createState() => _ObservationDetailScreenState();
}

class _ObservationDetailScreenState extends State<ObservationDetailScreen> {
  final PageController _pageController = PageController();
  final DraggableScrollableController _sheetController =
  DraggableScrollableController();

  static const double _sheetMinSize = 0.14;
  static const double _sheetInitialSize = 0.58;
  static const double _sheetMaxSize = 0.94;

  static const List<double> _sheetSnapSizes = <double>[
    _sheetMinSize,
    _sheetInitialSize,
    _sheetMaxSize,
  ];

  int _currentPhotoIndex = 0;
  final ValueNotifier<int> _photoIndexNotifier = ValueNotifier<int>(0);
  final Set<String> _precachedPhotos = <String>{};

  static const Map<String, String> _attributeLabels = {
    PlantAttributeKeys.identificationStatus: 'Статус определения',
    PlantAttributeKeys.habitat: 'Местообитание',
    PlantAttributeKeys.soilType: 'Тип почвы',
    PlantAttributeKeys.moisture: 'Увлажнение',
    PlantAttributeKeys.lightCondition: 'Освещенность',
    PlantAttributeKeys.lifeStage: 'Жизненная стадия',
    PlantAttributeKeys.phenophase: 'Фенологическая фаза',
    PlantAttributeKeys.plantCondition: 'Состояние растения',
    PlantAttributeKeys.abundanceCategory: 'Категория численности',
    PlantAttributeKeys.individualCount: 'Количество особей',
    PlantAttributeKeys.areaOccupied: 'Площадь участка, м²',
    PlantAttributeKeys.anthropogenicImpact: 'Антропогенное воздействие',
    PlantAttributeKeys.threatFactor: 'Угрожающий фактор',
    PlantAttributeKeys.protectionStatus: 'Охранный статус',
  };

  double _currentSheetSize() {
    if (!_sheetController.isAttached) {
      return _sheetInitialSize;
    }

    return _sheetController.size
        .clamp(_sheetMinSize, _sheetMaxSize)
        .toDouble();
  }


  void _precacheVisiblePhotos(List<String> photos) {
    if (!mounted || photos.isEmpty) return;

    final cacheWidth = (MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context))
        .clamp(180, 1080)
        .round();

    for (final path in photos.take(3)) {
      final normalized = path.trim();
      if (normalized.isEmpty || !_precachedPhotos.add(normalized)) {
        continue;
      }

      final ImageProvider provider = _isRemotePath(normalized)
          ? ResizeImage(
        NetworkImage(
          normalized,
          headers: widget.data.imageHeaders,
        ),
        width: cacheWidth,
      )
          : ResizeImage(
        FileImage(File(normalized)),
        width: cacheWidth,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        precacheImage(provider, context);
      });
    }
  }

  @override
  void dispose() {
    _photoIndexNotifier.dispose();
    _sheetController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool _isRemotePath(String? value) {
    if (value == null) return false;
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  Widget _image(
      String? path, {
        double? width,
        double? height,
        BoxFit fit = BoxFit.cover,
        Alignment alignment = Alignment.center,
        IconData placeholderIcon = Icons.image_outlined,
      }) {
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.surfaceSoft,
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon,
        size: width != null && width < 90 ? 23 : 54,
        color: AppColors.muted,
      ),
    );

    if (path == null || path.trim().isEmpty) return placeholder;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);

        final resolvedWidth = width ??
            (constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : fallbackWidth);

        final resolvedHeight = height ??
            (constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : null);

        final cacheWidth = (resolvedWidth * pixelRatio)
            .clamp(180, 1080)
            .round();

        if (_isRemotePath(path)) {
          return Image.network(
            path,
            headers: widget.data.imageHeaders,
            width: resolvedWidth,
            height: resolvedHeight,
            fit: fit,
            alignment: alignment,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );
        }

        return Image.file(
          File(path),
          width: resolvedWidth,
          height: resolvedHeight,
          fit: fit,
          alignment: alignment,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) => placeholder,
        );
      },
    );
  }

  String _formatAttributeValue(dynamic value) {
    if (value == null) return '';

    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty && item != 'null')
          .join(', ');
    }

    if (value is num) {
      final number = value.toDouble();
      if (number.truncateToDouble() == number) {
        return number.toStringAsFixed(0);
      }
      return number.toString();
    }

    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return '';

    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return _formatAttributeValue(jsonDecode(text));
      } catch (_) {
        return text;
      }
    }

    return text;
  }

  List<MapEntry<String, String>> _rowsFor(List<String> keys) {
    final rows = <MapEntry<String, String>>[];

    for (final key in keys) {
      final value = _formatAttributeValue(widget.data.attributes[key]);
      if (value.isEmpty) continue;
      rows.add(MapEntry(_attributeLabels[key] ?? key, value));
    }

    return rows;
  }

  Widget _topButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.96),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 22, color: AppColors.primaryDark),
          ),
        ),
      ),
    );
  }

  Widget _mainPhoto(
      List<String> photos, {
        BoxFit fit = BoxFit.cover,
        Alignment alignment = Alignment.center,
      }) {
    if (photos.isEmpty) {
      return Container(
        color: AppColors.surfaceSoft,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_outlined,
          size: 72,
          color: AppColors.muted,
        ),
      );
    }

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final height = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : null;

          return PageView.builder(
            controller: _pageController,
            physics: const PageScrollPhysics(),
            pageSnapping: true,
            allowImplicitScrolling: true,
            itemCount: photos.length,
            onPageChanged: (index) {
              _currentPhotoIndex = index;
              _photoIndexNotifier.value = index;
            },
            itemBuilder: (context, index) => _image(
              photos[index],
              width: width,
              height: height,
              fit: fit,
              alignment: alignment,
            ),
          );
        },
      ),
    );
  }

  void _goToPhoto(int index, int length) {
    if (length <= 0) return;

    final safeIndex = index.clamp(0, length - 1);
    if (safeIndex == _currentPhotoIndex) return;

    _pageController.animateToPage(
      safeIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _photoDots(List<String> photos) {
    if (photos.length <= 1) return const SizedBox.shrink();

    return ValueListenableBuilder<int>(
      valueListenable: _photoIndexNotifier,
      builder: (context, currentIndex, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(photos.length, (index) {
            final selected = index == currentIndex;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goToPhoto(index, photos.length),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                width: selected ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.surface
                      : AppColors.surface.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _badge(ObservationDetailBadge badge) {
    final color = badge.color ?? AppColors.muted;
    final text = badge.text.trim().isEmpty ? '—' : badge.text.trim();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(badge.icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _thinDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          height: 1,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 18),
          color: AppColors.border.withValues(alpha: 0.72),
        ),
      ),
    );
  }

  Widget _panelHeader() {
    final description = widget.data.description?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.local_florist_rounded,
                color: AppColors.primary,
                size: 30,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.data.title.trim().isEmpty
                        ? 'Без названия'
                        : widget.data.title.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  if (widget.data.badges.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 12,
                      runSpacing: 7,
                      children: widget.data.badges.map(_badge).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 15),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              height: 1.34,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ],
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<MapEntry<String, String>> rows,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _thinDivider(),
        Row(
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        ...rows.map(
              (row) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    row.key,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Text(
                    row.value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
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

  Future<void> _showTechnicalInfo(BuildContext buttonContext) async {
    if (widget.data.technicalRows.isEmpty) return;

    final buttonBox = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
    Navigator.of(buttonContext).overlay?.context.findRenderObject()
    as RenderBox?;

    if (buttonBox == null || overlay == null) return;

    final buttonRect = Rect.fromPoints(
      buttonBox.localToGlobal(Offset.zero, ancestor: overlay),
      buttonBox.localToGlobal(
        buttonBox.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );

    await showMenu<void>(
      context: buttonContext,
      position: RelativeRect.fromRect(buttonRect, Offset.zero & overlay.size),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: 285,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Техническая информация',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                ...widget.data.technicalRows.map(
                      (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            row.key,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            row.value,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDark,
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
        ),
      ],
    );
  }

  Widget _contentBody(ScrollController controller) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        overscroll: false,
        scrollbars: false,
      ),
      child: ListView(
        controller: controller,
        primary: false,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _panelHeader(),
          _section(
            icon: Icons.terrain_rounded,
            title: 'Среда произрастания',
            rows: _rowsFor(const [
              PlantAttributeKeys.habitat,
              PlantAttributeKeys.soilType,
              PlantAttributeKeys.moisture,
              PlantAttributeKeys.lightCondition,
            ]),
          ),
          _section(
            icon: Icons.eco_rounded,
            title: 'Состояние растения',
            rows: _rowsFor(const [
              PlantAttributeKeys.identificationStatus,
              PlantAttributeKeys.lifeStage,
              PlantAttributeKeys.phenophase,
              PlantAttributeKeys.plantCondition,
            ]),
          ),
          _section(
            icon: Icons.scatter_plot_rounded,
            title: 'Численность',
            rows: _rowsFor(const [
              PlantAttributeKeys.abundanceCategory,
              PlantAttributeKeys.individualCount,
              PlantAttributeKeys.areaOccupied,
            ]),
          ),
          _section(
            icon: Icons.shield_outlined,
            title: 'Охрана и воздействие',
            rows: _rowsFor(const [
              PlantAttributeKeys.anthropogenicImpact,
              PlantAttributeKeys.threatFactor,
              PlantAttributeKeys.protectionStatus,
            ]),
          ),
        ],
      ),
    );
  }

  Widget _staticPhotoLayer(List<String> photos) {
    return RepaintBoundary(
      child: SizedBox.expand(
        child: _mainPhoto(
          photos,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.06),
        ),
      ),
    );
  }

  Widget _photoLayer({
    required Widget photoLayer,
    required List<String> photos,
    required double screenHeight,
    required double safeTop,
    required double sheetSize,
  }) {
    final sheetTop = screenHeight * (1 - sheetSize);

    final initialTop = screenHeight * (1 - _sheetInitialSize);
    final minTop = screenHeight * (1 - _sheetMinSize);

    final openProgress = ((sheetTop - initialTop) / (minTop - initialTop))
        .clamp(0.0, 1.0)
        .toDouble();

    final closedProgress = ((sheetSize - _sheetInitialSize) /
        (_sheetMaxSize - _sheetInitialSize))
        .clamp(0.0, 1.0)
        .toDouble();

    // Масштаб идёт от более общего кадра при опущенной плашке
    // к более крупному кадру при закрытии фото плашкой.
    // Ниже 1.0 не опускаемся, поэтому боковых полей не появляется.
    final photoScale = (1.06 - openProgress * 0.06 + closedProgress * 0.07)
        .clamp(1.0, 1.14)
        .toDouble();

    // Низ фотографии визуально привязан к верхней границе плашки,
    // но уходит под неё на небольшой нахлёст.
    // Фото не смещается вниз, поэтому сверху не появляется пустая область.
    final sheetOverlap = 26.0 + openProgress * 18.0;
    final visiblePhotoHeight = (sheetTop + sheetOverlap)
        .clamp(safeTop + 160.0, screenHeight)
        .toDouble();

    final dotsTop = (sheetTop - 34)
        .clamp(safeTop + 78.0, visiblePhotoHeight - 32.0)
        .toDouble();

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: visiblePhotoHeight,
          child: ClipRect(
            child: Transform.scale(
              scale: photoScale,
              alignment: Alignment.bottomCenter,
              child: photoLayer,
            ),
          ),
        ),

        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.20),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.center,
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),

        if (photos.length > 1)
          Positioned(
            left: 0,
            right: 0,
            top: dotsTop,
            child: IgnorePointer(
              ignoring: sheetSize > 0.86,
              child: Center(child: _photoDots(photos)),
            ),
          ),
      ],
    );
  }

  Widget _body(List<String> photos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;

        final safeTop = MediaQuery.paddingOf(context).top;

        return Stack(
          children: [
            AnimatedBuilder(
              animation: _sheetController,
              child: _staticPhotoLayer(photos),
              builder: (context, child) {
                return _photoLayer(
                  photoLayer: child!,
                  photos: photos,
                  screenHeight: screenHeight,
                  safeTop: safeTop,
                  sheetSize: _currentSheetSize(),
                );
              },
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: _sheetInitialSize,
                minChildSize: _sheetMinSize,
                maxChildSize: _sheetMaxSize,
                snap: true,
                snapSizes: _sheetSnapSizes,
                snapAnimationDuration: const Duration(milliseconds: 150),
                expand: false,
                builder: (context, scrollController) {
                  return RepaintBoundary(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(34),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: _contentBody(scrollController),
                      ),
                    ),
                  );
                },
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _topButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Назад',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    Builder(
                      builder: (buttonContext) {
                        return _topButton(
                          icon: Icons.more_horiz_rounded,
                          tooltip: 'Информация',
                          onTap: () => _showTechnicalInfo(buttonContext),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.photosFuture == null) {
      _precacheVisiblePhotos(widget.data.photos);

      return Scaffold(
        backgroundColor: AppColors.background,
        body: _body(widget.data.photos),
      );
    }

    return FutureBuilder<List<String>>(
      future: widget.data.photosFuture,
      initialData: widget.data.photos,
      builder: (context, snapshot) {
        final photos = snapshot.data ?? widget.data.photos;
        _precacheVisiblePhotos(photos);

        if (_currentPhotoIndex >= photos.length && photos.isNotEmpty) {
          _currentPhotoIndex = photos.length - 1;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _photoIndexNotifier.value = _currentPhotoIndex;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentPhotoIndex);
            }
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: _body(photos),
        );
      },
    );
  }
}
