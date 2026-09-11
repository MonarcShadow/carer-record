import 'package:flutter/material.dart';

/// Paleta de marca Carer-Record (diseño Figma).
class CR {
  CR._();

  // Marca
  static const Color mint     = Color(0xFF4EDDB3);
  static const Color mintDark = Color(0xFF2AB892);
  static const Color mintSoft = Color(0xFFE7FAF4);
  static const Color mintInk  = Color(0xFF0D3D2C);

  // Sistema
  static const Color blue   = Color(0xFF007AFF);
  static const Color red    = Color(0xFFFF3B30);
  static const Color orange = Color(0xFFFF9500);
  static const Color purple = Color(0xFFAF52DE);
}

/// Tokens que cambian según el modo (claro / oscuro).
class CRTokens {
  final Brightness brightness;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color background;
  final Color surface;
  final Color field;
  final Color separator;
  final Color chipBg;

  const CRTokens._({
    required this.brightness,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.background,
    required this.surface,
    required this.field,
    required this.separator,
    required this.chipBg,
  });

  static const CRTokens light = CRTokens._(
    brightness: Brightness.light,
    textPrimary:    Color(0xFF1C1C1E),
    textSecondary:  Color(0xFF6E6E73),
    textTertiary:   Color(0xFFAEAEB2),
    background:     Color(0xFFF2F2F7),
    surface:        Color(0xFFFFFFFF),
    field:          Color(0x1F767680), // rgba(118,118,128,0.12)
    separator:      Color(0x1F3C3C43), // rgba(60,60,67,0.12)
    chipBg:         Color(0x14767680),
  );

  static const CRTokens dark = CRTokens._(
    brightness: Brightness.dark,
    textPrimary:   Color(0xFFF2F2F7),
    textSecondary: Color(0xFF98989E),
    textTertiary:  Color(0xFF636366),
    background:    Color(0xFF0B0B0F),
    surface:       Color(0xFF1C1C1E),
    field:         Color(0x1AFFFFFF),
    separator:     Color(0x29FFFFFF),
    chipBg:        Color(0x1AFFFFFF),
  );

  static CRTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  bool get isDark => brightness == Brightness.dark;

  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.05),
          blurRadius: isDark ? 0 : 12,
          offset: const Offset(0, 2),
        ),
      ];
}

/// Un color de categoría + fondo translúcido.
class CRCategory {
  final Color color;
  final Color bg;
  const CRCategory(this.color, this.bg);
}

/// Categorías de eventos del diseño (chip de color por tipo).
class CRCategories {
  CRCategories._();

  static const Map<String, CRCategory> all = {
    'Rutina':       CRCategory(Color(0xFF6E6E73), Color(0x1F6E6E73)),
    'Movilidad':    CRCategory(CR.purple,   Color(0x1FAF52DE)),
    'Nota clínica': CRCategory(CR.blue,     Color(0x1F007AFF)),
    'Farmacología': CRCategory(CR.orange,   Color(0x1FFF9500)),
    'Procedimiento':CRCategory(CR.red,      Color(0x1FFF3B30)),
    'Comunicación': CRCategory(CR.mintDark, Color(0x264EDDB3)),
    'Voz':          CRCategory(CR.mintDark, Color(0x264EDDB3)),
  };

  static CRCategory of(String? key) => all[key] ?? all['Rutina']!;
}
