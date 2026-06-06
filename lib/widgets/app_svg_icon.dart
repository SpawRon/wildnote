import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppIconConfig {
  AppIconConfig._();

  static const String root = 'assets/icon';

  /// Меняется весь набор иконок.
  /// Ожидаемый путь:
  /// assets/icon/minimal2/name.svg
  static const String folderName = 'minimal2';

  /// На время настройки лучше false.
  /// Если true, при отсутствии иконки в наборе будет попытка взять:
  /// assets/icon/name.svg
  static const bool enableDirectFallback = false;

  /// Логи загрузки SVG в debug-консоль.
  static const bool debugIconLoading = true;

  static String primaryPath(String assetName) {
    return '$root/$folderName/$assetName.svg';
  }

  static String fallbackPath(String assetName) {
    return '$root/$assetName.svg';
  }
}

class AppIconAssets {
  AppIconAssets._();

  /// ВАЖНО:
  /// Сейчас у тебя, судя по списку файлов, нет nav_add.svg,
  /// nav_history.svg, nav_explorer.svg, nav_settings.svg.
  /// Поэтому временно привязываем навигацию к существующим файлам.
  static const String navAdd = 'button';
  static const String navHistory = 'identification_status';
  static const String navExplorer = 'geolocation';
  static const String navSettings = 'button_2';

  static const String button = 'button';
  static const String button2 = 'button_2';
  static const String favoriteButton = 'favorite_button';
  static const String geolocation = 'geolocation';

  static const String abundanceCategory = 'abundance_category';
  static const String anthropogenicImpact = 'anthropogenic_impact';
  static const String areaOccupied = 'area_occupied';
  static const String habitat = 'habitat';
  static const String identificationStatus = 'identification_status';
  static const String individualCount = 'individual_count';
  static const String lifeStage = 'life_stage';
  static const String lightCondition = 'light_condition';
  static const String moisture = 'moisture';
  static const String phenophase = 'phenophase';
  static const String plantCondition = 'plant_condition';
  static const String protectionStatus = 'protection_status';
  static const String soilType = 'soil_type';
  static const String threatFactor = 'threat_factor';

  static String forAttribute(String attributeKey) {
    switch (attributeKey) {
      case 'abundance_category':
        return abundanceCategory;
      case 'anthropogenic_impact':
        return anthropogenicImpact;
      case 'area_occupied':
        return areaOccupied;
      case 'habitat':
        return habitat;
      case 'identification_status':
        return identificationStatus;
      case 'individual_count':
        return individualCount;
      case 'life_stage':
        return lifeStage;
      case 'light_condition':
        return lightCondition;
      case 'moisture':
        return moisture;
      case 'phenophase':
        return phenophase;
      case 'plant_condition':
        return plantCondition;
      case 'protection_status':
        return protectionStatus;
      case 'soil_type':
        return soilType;
      case 'threat_factor':
        return threatFactor;
      default:
        return button;
    }
  }
}

class AppSvgIcon extends StatelessWidget {
  final String assetName;
  final double size;
  final Color? color;
  final IconData? fallbackIcon;
  final BoxFit fit;

  const AppSvgIcon(
      this.assetName, {
        super.key,
        this.size = 24,
        this.color,
        this.fallbackIcon,
        this.fit = BoxFit.contain,
      });

  static final Map<String, Future<_LoadedSvg?>> _svgCache =
  <String, Future<_LoadedSvg?>>{};

  static void clearCache() {
    _svgCache.clear();
  }

  static Future<_LoadedSvg?> _loadSvg(BuildContext context, String assetName) {
    final primaryPath = AppIconConfig.primaryPath(assetName);
    final fallbackPath = AppIconConfig.fallbackPath(assetName);

    final cacheKey =
        '${AppIconConfig.folderName}|$assetName|${AppIconConfig.enableDirectFallback}';

    return _svgCache.putIfAbsent(cacheKey, () async {
      final bundle = DefaultAssetBundle.of(context);

      final paths = <String>[
        primaryPath,
        if (AppIconConfig.enableDirectFallback) fallbackPath,
      ];

      for (final path in paths) {
        try {
          final svg = await bundle.loadString(path);

          if (kDebugMode && AppIconConfig.debugIconLoading) {
            debugPrint('SVG loaded: $path');
          }

          return _LoadedSvg(path: path, source: svg);
        } on FlutterError catch (e) {
          if (kDebugMode && AppIconConfig.debugIconLoading) {
            debugPrint('SVG missing: $path');
            debugPrint('SVG error: ${e.message}');
          }
        } catch (e) {
          if (kDebugMode && AppIconConfig.debugIconLoading) {
            debugPrint('SVG failed: $path');
            debugPrint('SVG error: $e');
          }
        }
      }

      if (kDebugMode && AppIconConfig.debugIconLoading) {
        debugPrint('SVG not found for assetName="$assetName"');
      }

      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? IconTheme.of(context).color;

    final fallback = Icon(
      fallbackIcon ?? Icons.broken_image_outlined,
      size: size,
      color: resolvedColor,
    );

    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<_LoadedSvg?>(
        future: _loadSvg(context, assetName),
        builder: (context, snapshot) {
          final loaded = snapshot.data;

          if (loaded == null || loaded.source.trim().isEmpty) {
            return fallback;
          }

          return SvgPicture.string(
            loaded.source,
            width: size,
            height: size,
            fit: fit,
            colorFilter: resolvedColor == null
                ? null
                : ColorFilter.mode(
              resolvedColor,
              BlendMode.srcIn,
            ),
          );
        },
      ),
    );
  }
}

class _LoadedSvg {
  final String path;
  final String source;

  const _LoadedSvg({
    required this.path,
    required this.source,
  });
}