import 'package:material_ui/material_ui.dart';

/// Semantic design tokens matching the v2.0 minimalist high-tech studio aesthetic
/// (`#3F6AF5` electric indigo accent, `#F7F8FA`/`#0B0D12` studio canvas, 1px
/// hairline borders, zero heavy shadows).
@immutable
class InouTokens extends ThemeExtension<InouTokens> {
  const InouTokens({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.borderHairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.redPen,
  });

  factory InouTokens.light() => const InouTokens(
    isDark: false,
    canvas: Color(0xFFF5F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF1F6),
    borderHairline: Color(0xFFE5E7EB),
    textPrimary: Color(0xFF0B0F19),
    textSecondary: Color(0xFF4B5563),
    textMuted: Color(0xFF9CA3AF),
    accent: Color(0xFF2F5AF6),
    accentSoft: Color(0x1F2F5AF6),
    success: Color(0xFF059669),
    successSoft: Color(0x14059669),
    warning: Color(0xFFD97706),
    warningSoft: Color(0x16D97706),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0x14DC2626),
    redPen: Color(0xFFE11D48),
  );

  factory InouTokens.dark() => const InouTokens(
    isDark: true,
    canvas: Color(0xFF090C13),
    surface: Color(0xFF111622),
    surfaceMuted: Color(0xFF181F30),
    borderHairline: Color(0xFF22293B),
    textPrimary: Color(0xFFF3F4F6),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF6B7280),
    accent: Color(0xFF4C72FF),
    accentSoft: Color(0x304C72FF),
    success: Color(0xFF34D399),
    successSoft: Color(0x2034D399),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0x20FBBF24),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x20F87171),
    redPen: Color(0xFFFB7185),
  );

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color borderHairline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color redPen;

  @override
  InouTokens copyWith({
    bool? isDark,
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? borderHairline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? redPen,
  }) {
    return InouTokens(
      isDark: isDark ?? this.isDark,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      borderHairline: borderHairline ?? this.borderHairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      redPen: redPen ?? this.redPen,
    );
  }

  @override
  InouTokens lerp(ThemeExtension<InouTokens>? other, double t) {
    if (other is! InouTokens) return this;
    return InouTokens(
      isDark: t < 0.5 ? isDark : other.isDark,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      borderHairline: Color.lerp(borderHairline, other.borderHairline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      redPen: Color.lerp(redPen, other.redPen, t)!,
    );
  }
}

extension InouTokensContext on BuildContext {
  InouTokens get inou =>
      Theme.of(this).extension<InouTokens>() ?? InouTokens.light();
}

/// Shared studio theme definitions (Light/Dark).
abstract final class InouTheme {
  static const _seedColor = Color(0xFF3F6AF5);

  static ThemeData light() => _build(InouTokens.light(), Brightness.light);

  static ThemeData dark() => _build(InouTokens.dark(), Brightness.dark);

  static ThemeData _build(InouTokens t, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
      primary: t.accent,
      surface: t.surface,
      error: t.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.canvas,
      dividerColor: t.borderHairline,
      extensions: [t],
      appBarTheme: AppBarTheme(
        backgroundColor: t.canvas,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 54,
        titleSpacing: 18,
        titleTextStyle: TextStyle(
          fontSize: 17.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
          color: t.textPrimary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 62,
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.accentSoft,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? t.accent
                : t.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected)
                ? t.accent
                : t.textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.surface,
        indicatorColor: t.accentSoft,
        selectedIconTheme: IconThemeData(color: t.accent, size: 21),
        unselectedIconTheme: IconThemeData(color: t.textSecondary, size: 21),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: t.accent,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: t.textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: t.borderHairline, width: 0.9),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: t.borderHairline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.isDark ? t.surfaceMuted : t.textPrimary,
        contentTextStyle: TextStyle(
          fontSize: 13,
          color: t.isDark ? t.textPrimary : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(
        color: t.borderHairline,
        thickness: 0.85,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.borderHairline),
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return t.accent;
            return t.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return t.textSecondary;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: t.borderHairline, width: 0.9),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12.5,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.isDark ? t.surfaceMuted : t.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.borderHairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.borderHairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.accent, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            if (states.contains(WidgetState.selected)) {
              return t.accent.withValues(alpha: 0.45);
            }
            return t.surfaceMuted;
          }
          if (states.contains(WidgetState.selected)) return t.accent;
          return t.surface;
        }),
        backgroundColor: t.surface,
        selectedColor: t.accent,
        disabledColor: t.surfaceMuted,
        checkmarkColor: Colors.white,
        deleteIconColor: t.textSecondary,
        showCheckmark: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: t.accent, width: 1.2);
          }
          return BorderSide(color: t.borderHairline, width: 1.0);
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white.withValues(alpha: 0.78);
              }
              return t.textSecondary;
            }
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return t.textPrimary;
          }),
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

abstract final class InouTypography {
  static TextStyle tabular(TextStyle base) =>
      base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
