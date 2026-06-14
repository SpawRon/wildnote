import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';


class AppIconConfig {
  AppIconConfig._();

  static const String root = 'assets/icon';
  static const String folderName = 'standard';
  static const String extension = 'svg';

  static String path(String assetName) {
    return '$root/$folderName/$assetName.$extension';
  }
}

class AppIconName {
  AppIconName._();

  static const String abundanceCategory = 'abundance_category';
  static const String abundanceCategoryV2 = 'abundance_category_v2';
  static const String anthropogenicImpact = 'anthropogenic_impact';
  static const String anthropogenicImpactV2 = 'anthropogenic_impact_2';
  static const String areaOccupied = 'area_occupied';
  static const String button = 'button';
  static const String button2 = 'button_2';
  static const String favoriteButton = 'favorite_button';
  static const String geolocation = 'geolocation';
  static const String geolocationV2 = 'geolocation_2';
  static const String habitat = 'habitat';
  static const String identificationStatus = 'identification_status';
  static const String individualCount = 'individual_count';
  static const String lifeStage = 'life_stage';
  static const String lifeStageV2 = 'life_stage_v2';
  static const String lightCondition = 'light_condition';
  static const String lightConditionV2 = 'light_condition_v2';
  static const String moisture = 'moisture';
  static const String phenophase = 'phenophase';
  static const String plantCondition = 'plant_condition';
  static const String protectionStatus = 'protection_status';
  static const String soilType = 'soil_type';
  static const String soilTypeV2 = 'soil_type_v2';
  static const String threatFactor = 'threat_factor';
}

/// Semantic icon aliases used by screens.
///
/// If you want to replace an icon variant, edit the alias here only.
/// Screens should not use raw file names directly.
class AppIconAssets {
  AppIconAssets._();

  // General icons used inside screens.
  static const String button = AppIconName.button;
  static const String button2 = AppIconName.button2;
  static const String favoriteButton = AppIconName.favoriteButton;
  static const String geolocation = AppIconName.geolocationV2;
  static const String navigationArrow = AppIconName.button;

  // Photo checklist icons.
  static const String photoGeneral = AppIconName.lifeStageV2;
  static const String photoLeaves = AppIconName.habitat;
  static const String photoFlowerOrFruit = AppIconName.phenophase;
  static const String photoHabitat = AppIconName.soilTypeV2;

  // Plant observation attributes.
  static const String abundanceCategory = AppIconName.abundanceCategoryV2;
  static const String anthropogenicImpact = AppIconName.anthropogenicImpactV2;
  static const String areaOccupied = AppIconName.areaOccupied;
  static const String habitat = AppIconName.habitat;
  static const String identificationStatus = AppIconName.identificationStatus;
  static const String individualCount = AppIconName.individualCount;
  static const String lifeStage = AppIconName.lifeStageV2;
  static const String lightCondition = AppIconName.lightCondition;
  static const String moisture = AppIconName.moisture;
  static const String phenophase = AppIconName.phenophase;
  static const String plantCondition = AppIconName.plantCondition;
  static const String protectionStatus = AppIconName.protectionStatus;
  static const String soilType = AppIconName.soilTypeV2;
  static const String threatFactor = AppIconName.threatFactor;

  static const Map<String, String> attributeIcons = <String, String>{
    'abundance_category': abundanceCategory,
    'anthropogenic_impact': anthropogenicImpact,
    'area_occupied': areaOccupied,
    'habitat': habitat,
    'identification_status': identificationStatus,
    'individual_count': individualCount,
    'life_stage': lifeStage,
    'light_condition': lightCondition,
    'moisture': moisture,
    'phenophase': phenophase,
    'plant_condition': plantCondition,
    'protection_status': protectionStatus,
    'soil_type': soilType,
    'threat_factor': threatFactor,
  };

  static String forAttribute(String attributeKey) {
    return attributeIcons[attributeKey] ?? button;
  }
}

class AppSvgIcon extends StatelessWidget {
  final String assetName;
  final double size;
  final Color? color;
  final IconData? fallbackIcon;
  final BoxFit fit;

  /// Keep this at 1.0 for normalized 24x24 icons.
  /// Use only for temporary one-off correction while source SVG is adjusted.
  final double visualScale;

  const AppSvgIcon(
      this.assetName, {
        super.key,
        this.size = 24,
        this.color,
        this.fallbackIcon,
        this.fit = BoxFit.contain,
        this.visualScale = 1.0,
      });

  /// Convenience constructor for attribute rows.
  ///
  /// Example:
  /// AppSvgIcon.attribute(PlantAttributeKeys.habitat, size: 18)
  factory AppSvgIcon.attribute(
      String attributeKey, {
        Key? key,
        double size = 24,
        Color? color,
        IconData? fallbackIcon,
        BoxFit fit = BoxFit.contain,
        double visualScale = 1.0,
      }) {
    return AppSvgIcon(
      AppIconAssets.forAttribute(attributeKey),
      key: key,
      size: size,
      color: color,
      fallbackIcon: fallbackIcon,
      fit: fit,
      visualScale: visualScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? IconTheme.of(context).color;
    final innerSize = size * visualScale.clamp(0.1, 2.0);

    return SizedBox.square(
      dimension: size,
      child: Center(
        child: SizedBox.square(
          dimension: innerSize,
          child: SvgPicture.asset(
            AppIconConfig.path(assetName),
            width: innerSize,
            height: innerSize,
            fit: fit,
            colorFilter: resolvedColor == null
                ? null
                : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
            placeholderBuilder: (context) => Icon(
              fallbackIcon ?? Icons.broken_image_outlined,
              size: innerSize,
              color: resolvedColor,
            ),
          ),
        ),
      ),
    );
  }
}
