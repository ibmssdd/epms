import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ============================================================
  // EPMS COLOR SYSTEM — BLACK & GOLD
  // ============================================================

  // Primary gold — buttons, active states, key accents.
  static const Color gold = Color(0xFFD4AF37);

  // Brighter gold — hover/selected highlights, glows.
  static const Color brightGold = Color(0xFFF3D680);

  // Deep antique gold — pressed states, subtle borders.
  static const Color deepGold = Color(0xFF9C7A29);

  // Champagne — soft gold for secondary chips/badges.
  static const Color champagne = Color(0xFFE8D9A8);

  // Status colors, kept legible against black.
  static const Color statusRed = Color(0xFFE0654B);
  static const Color statusGreen = Color(0xFF4CAF7D);
  static const Color statusAmber = Color(0xFFE0B84B);

  // Dark theme surfaces — true near-black, warm undertone.
  static const Color darkBackground = Color(0xFF0A0A0C);
  static const Color darkSurface = Color(0xFF16151A);
  static const Color darkSurfaceAlt = Color(0xFF201E22);
  static const Color darkBorder = Color(0xFF35311F);

  // Dark theme text.
  static const Color darkText = Color(0xFFF5EFE0);
  static const Color darkSecondaryText = Color(0xFFB8AF9C);

  // Light theme surfaces — ivory/cream, kept for contexts that need it.
  static const Color lightBackground = Color(0xFFF7F3E9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEFE7D2);

  // Light theme text.
  static const Color lightText = Color(0xFF1A1712);
  static const Color lightSecondaryText = Color(0xFF6B6455);

  // ============================================================
  // DARK THEME — the app's primary/default look.
  // ============================================================

  static ThemeData get darkTheme {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ).copyWith(
          primary: gold,
          onPrimary: Colors.black,
          secondary: champagne,
          onSecondary: Colors.black,
          tertiary: brightGold,
          onTertiary: Colors.black,
          surface: darkSurface,
          onSurface: darkText,
          error: statusRed,
          onError: Colors.black,
          outline: darkBorder,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      scaffoldBackgroundColor: darkBackground,

      colorScheme: colorScheme,

      fontFamily: 'Roboto',

      // ----------------------------------------------------------
      // APP BAR
      // ----------------------------------------------------------
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: gold,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),

      // ----------------------------------------------------------
      // CARDS
      // ----------------------------------------------------------
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.6),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),

      // ----------------------------------------------------------
      // INPUT FIELDS
      // ----------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceAlt,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 2),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: statusRed, width: 1.5),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: statusRed, width: 2),
        ),

        hintStyle: const TextStyle(color: darkSecondaryText),
        labelStyle: const TextStyle(color: darkSecondaryText),

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),

      // ----------------------------------------------------------
      // BUTTONS
      // ----------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkSurfaceAlt,
          foregroundColor: gold,
          elevation: 0,
          side: const BorderSide(color: darkBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          side: const BorderSide(color: gold, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: gold),
      ),

      iconTheme: const IconThemeData(color: darkSecondaryText),

      // ----------------------------------------------------------
      // CHIPS
      // ----------------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceAlt,
        selectedColor: gold,
        disabledColor: darkSurfaceAlt,
        secondarySelectedColor: brightGold,
        side: const BorderSide(color: darkBorder),
        labelStyle: const TextStyle(
          color: darkText,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      // ----------------------------------------------------------
      // SWITCHES
      // ----------------------------------------------------------
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          return darkSecondaryText;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return gold;
          }
          return darkSurfaceAlt;
        }),
        trackOutlineColor: WidgetStateProperty.all(darkBorder),
      ),

      // ----------------------------------------------------------
      // DIVIDERS
      // ----------------------------------------------------------
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),

      // ----------------------------------------------------------
      // NAVIGATION RAIL (left sidebar)
      // ----------------------------------------------------------
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkBackground,
        selectedIconTheme: const IconThemeData(color: Colors.black),
        unselectedIconTheme: const IconThemeData(color: darkSecondaryText),
        indicatorColor: gold,
        selectedLabelTextStyle: const TextStyle(
          color: gold,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: darkSecondaryText),
      ),

      // ----------------------------------------------------------
      // TEXT
      // ----------------------------------------------------------
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
        titleLarge: TextStyle(color: darkText, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: darkText, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: darkText),
        bodyMedium: TextStyle(color: darkSecondaryText),
        bodySmall: TextStyle(color: darkSecondaryText),
      ),
    );
  }

  // ============================================================
  // LIGHT THEME — ivory/gold variant, kept for completeness.
  // ============================================================

  static ThemeData get lightTheme {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.light,
        ).copyWith(
          primary: deepGold,
          onPrimary: Colors.white,
          secondary: champagne,
          onSecondary: lightText,
          tertiary: gold,
          onTertiary: Colors.black,
          surface: lightSurface,
          onSurface: lightText,
          error: statusRed,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      scaffoldBackgroundColor: lightBackground,

      colorScheme: colorScheme,

      fontFamily: 'Roboto',

      appBarTheme: const AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: deepGold,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),

      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 1,
        shadowColor: deepGold.withValues(alpha: 0.12),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: champagne.withValues(alpha: 0.6)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: deepGold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: statusRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: statusRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: deepGold,
          foregroundColor: Colors.white,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: Colors.black,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: deepGold,
          side: const BorderSide(color: deepGold, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: lightSurfaceAlt,
        selectedColor: deepGold,
        disabledColor: lightSurfaceAlt.withValues(alpha: 0.5),
        secondarySelectedColor: gold,
        labelStyle: const TextStyle(
          color: lightText,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return deepGold;
          }
          return Colors.grey.shade300;
        }),
      ),

      dividerTheme: DividerThemeData(
        color: champagne.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),

      textTheme: const TextTheme(
        headlineSmall: TextStyle(color: lightText, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: lightText, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: lightText, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: lightText),
        bodyMedium: TextStyle(color: lightSecondaryText),
        bodySmall: TextStyle(color: lightSecondaryText),
      ),
    );
  }
}
