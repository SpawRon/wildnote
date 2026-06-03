import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFFAFAF3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF8F9F4);
  static const Color primary = Color(0xFF6F8F77);
  static const Color primaryDark = Color(0xFF17201D);
  static const Color muted = Color(0xFF6F7975);
  static const Color border = Color(0xFFE4E8DF);
  static const Color softGreen = Color(0xFFEAF1EA);
  static const Color danger = Color(0xFFE95A5A);
  static const Color success = Color(0xFF46A35C);
  static const Color warning = Color(0xFFE49B3D);
}

class AppRadius {
  static const double small = 12;
  static const double medium = 18;
  static const double card = 24;
  static const double sheet = 30;
}

class AppSpacing {
  static const double screen = 20;
  static const double card = 16;
  static const double block = 20;
}

class AppTheme {
  static ThemeData get light {
    return build(
      brightness: Brightness.light,
      accent: AppColors.primary,
    );
  }

  static ThemeData get dark {
    return build(
      brightness: Brightness.dark,
      accent: AppColors.primary,
    );
  }

  static ThemeData build({
    required Brightness brightness,
    required Color accent,
    bool highContrast = false,
    bool sunlightContrast = false,
    bool fieldMode = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final contrast = highContrast && !isDark;
    final ultraContrast = contrast && sunlightContrast;

    final background = isDark
        ? Color.alphaBlend(
      accent.withValues(alpha: 0.045),
      const Color(0xFF09100C),
    )
        : ultraContrast
        ? Colors.white
        : Color.alphaBlend(
      accent.withValues(alpha: contrast ? 0.006 : 0.025),
      const Color(0xFFFFFEFA),
    );

    final surface = isDark
        ? Color.alphaBlend(
      accent.withValues(alpha: 0.035),
      const Color(0xFF111A14),
    )
        : Colors.white;

    final surfaceSoft = isDark
        ? Color.alphaBlend(
      accent.withValues(alpha: 0.075),
      const Color(0xFF18231B),
    )
        : ultraContrast
        ? Colors.white
        : (contrast ? Colors.white : const Color(0xFFFBFCF8));

    final primaryText = isDark
        ? const Color(0xFFF4FBF4)
        : ultraContrast
        ? Colors.black
        : const Color(0xFF07110C);

    final mutedText = isDark
        ? const Color(0xFFB9C3BD)
        : ultraContrast
        ? const Color(0xFF101812)
        : (contrast ? const Color(0xFF35413A) : const Color(0xFF5F6B64));

    final border = isDark
        ? Color.alphaBlend(
      accent.withValues(alpha: 0.14),
      const Color(0xFF263229),
    )
        : ultraContrast
        ? Color.alphaBlend(
      accent.withValues(alpha: 0.58),
      const Color(0xFFD5DDD5),
    )
        : (contrast
        ? Color.alphaBlend(
      accent.withValues(alpha: 0.22),
      const Color(0xFFD8DDD6),
    )
        : Color.alphaBlend(
      accent.withValues(alpha: 0.07),
      const Color(0xFFE7EAE2),
    ));

    final softAccent = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.23 : (ultraContrast ? 0.23 : 0.14)),
      surface,
    );

    final fieldFill = surfaceSoft;

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      surface: surface,
      error: AppColors.danger,
    );

    final enabledBorderSide = ultraContrast
        ? BorderSide(color: border, width: 1.15)
        : BorderSide.none;

    final buttonMinHeight = fieldMode ? 62.0 : 54.0;
    final compactButtonMinHeight = fieldMode ? 56.0 : 48.0;
    final inputVerticalPadding = fieldMode ? 17.0 : 14.0;

    final focusedBorderSide = BorderSide(
      color: accent.withValues(alpha: ultraContrast ? 0.86 : 0.36),
      width: ultraContrast ? 1.35 : 1.0,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      visualDensity: VisualDensity.standard,
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[
        WildColors(
          background: background,
          surface: surface,
          surfaceSoft: surfaceSoft,
          fieldFill: fieldFill,
          primary: accent,
          primaryDark: primaryText,
          muted: mutedText,
          border: border,
          softGreen: softAccent,
          danger: AppColors.danger,
          success: AppColors.success,
          warning: AppColors.warning,
          sunlightContrast: ultraContrast,
          fieldMode: fieldMode,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: primaryText,
        titleTextStyle: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: primaryText,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        hintStyle: TextStyle(
          color: mutedText,
          fontWeight: ultraContrast ? FontWeight.w700 : FontWeight.w500,
        ),
        labelStyle: TextStyle(
          color: mutedText,
          fontWeight: ultraContrast ? FontWeight.w800 : FontWeight.w600,
        ),
        prefixIconColor: accent,
        suffixIconColor: mutedText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: enabledBorderSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: enabledBorderSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: focusedBorderSide,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(
            color: AppColors.danger.withValues(alpha: 0.72),
            width: ultraContrast ? 1.3 : 1.0,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(
            color: AppColors.danger,
            width: ultraContrast ? 1.4 : 1.0,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: inputVerticalPadding,
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: primaryText,
        displayColor: primaryText,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: mutedText.withValues(alpha: 0.36),
          disabledForegroundColor: Colors.white70,
          minimumSize: Size.fromHeight(buttonMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ultraContrast ? primaryText : accent,
          minimumSize: Size.fromHeight(compactButtonMinHeight),
          side: BorderSide(
            color: accent.withValues(alpha: ultraContrast ? 0.88 : 0.55),
            width: ultraContrast ? 1.5 : 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ultraContrast ? primaryText : accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: primaryText,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: softAccent,
        selectedColor: accent.withValues(alpha: isDark ? 0.36 : 0.20),
        labelStyle: TextStyle(
          color: primaryText,
          fontWeight: ultraContrast ? FontWeight.w800 : FontWeight.w700,
        ),
        side: ultraContrast ? BorderSide(color: border) : BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryText,
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF101411) : Colors.white,
          fontWeight: FontWeight.w700,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return mutedText.withValues(alpha: 0.42);
          }
          if (states.contains(WidgetState.selected)) return accent;
          return mutedText;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return border.withValues(alpha: 0.56);
          }
          if (states.contains(WidgetState.selected)) {
            return accent.withValues(alpha: ultraContrast ? 0.42 : 0.30);
          }
          return border;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: border,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: softAccent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: fieldMode ? 12.5 : 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? primaryText : mutedText,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: fieldMode ? (selected ? 29 : 27) : (selected ? 27 : 25),
            color: selected ? accent : mutedText,
          );
        }),
      ),
    );
  }
}

@immutable
class WildColors extends ThemeExtension<WildColors> {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color fieldFill;
  final Color primary;
  final Color primaryDark;
  final Color muted;
  final Color border;
  final Color softGreen;
  final Color danger;
  final Color success;
  final Color warning;
  final bool sunlightContrast;
  final bool fieldMode;

  const WildColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.fieldFill,
    required this.primary,
    required this.primaryDark,
    required this.muted,
    required this.border,
    required this.softGreen,
    required this.danger,
    required this.success,
    required this.warning,
    this.sunlightContrast = false,
    this.fieldMode = false,
  });

  static const WildColors fallback = WildColors(
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceSoft: AppColors.surfaceSoft,
    fieldFill: AppColors.surfaceSoft,
    primary: AppColors.primary,
    primaryDark: AppColors.primaryDark,
    muted: AppColors.muted,
    border: AppColors.border,
    softGreen: AppColors.softGreen,
    danger: AppColors.danger,
    success: AppColors.success,
    warning: AppColors.warning,
    sunlightContrast: false,
    fieldMode: false,
  );

  static WildColors of(BuildContext context) {
    return Theme.of(context).extension<WildColors>() ?? fallback;
  }

  @override
  WildColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSoft,
    Color? fieldFill,
    Color? primary,
    Color? primaryDark,
    Color? muted,
    Color? border,
    Color? softGreen,
    Color? danger,
    Color? success,
    Color? warning,
    bool? sunlightContrast,
    bool? fieldMode,
  }) {
    return WildColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      fieldFill: fieldFill ?? this.fieldFill,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      softGreen: softGreen ?? this.softGreen,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      sunlightContrast: sunlightContrast ?? this.sunlightContrast,
      fieldMode: fieldMode ?? this.fieldMode,
    );
  }

  @override
  WildColors lerp(ThemeExtension<WildColors>? other, double t) {
    if (other is! WildColors) return this;

    return WildColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      fieldFill: Color.lerp(fieldFill, other.fieldFill, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      softGreen: Color.lerp(softGreen, other.softGreen, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      sunlightContrast: t < 0.5 ? sunlightContrast : other.sunlightContrast,
      fieldMode: t < 0.5 ? fieldMode : other.fieldMode,
    );
  }
}
