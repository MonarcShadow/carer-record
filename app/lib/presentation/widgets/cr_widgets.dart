import 'package:flutter/material.dart';
import '../../core/theme/cr_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Componentes reutilizables del diseño Carer-Record
// ─────────────────────────────────────────────────────────────────────────────

/// Título grande de pantalla (estilo Figma: 32–36px, peso 700).
class CRLargeTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double size;

  const CRLargeTitle({super.key, required this.title, this.subtitle, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(title,
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: t.textPrimary)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: TextStyle(fontSize: 14, color: t.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Etiqueta de sección (13px, mayúsculas, grey).
class CRSectionLabel extends StatelessWidget {
  final String text;
  const CRSectionLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.04,
            color: t.textSecondary),
      ),
    );
  }
}

/// Botón primario con gradiente menta (estilo Figma).
class CRPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  const CRPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF72EDD1), Color(0xFF29B88F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: enabled ? null : CR.mintDark.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: CR.mintDark.withValues(alpha: 0.38),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: CR.mintInk),
              )
            : Text(
                label,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: enabled
                        ? CR.mintInk
                        : CR.mintDark.withValues(alpha: 0.5)),
              ),
      ),
    );
  }
}

/// Chip de categoría de evento (colores del diseño).
class CRCategoryChip extends StatelessWidget {
  final String category;
  final bool selected;
  final bool small;
  final VoidCallback? onTap;

  const CRCategoryChip({
    super.key,
    required this.category,
    this.selected = false,
    this.small = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = CRCategories.of(category);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(
            horizontal: small ? 8 : 12, vertical: small ? 3 : 6),
        decoration: BoxDecoration(
          color: selected ? cfg.color : cfg.bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          category,
          style: TextStyle(
              fontSize: small ? 11 : 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : cfg.color),
        ),
      ),
    );
  }
}

/// Chip de filtro neutro (Todas / UCI / Textos / Voz …).
class CRFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const CRFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: selected
              ? (t.isDark ? Colors.white : t.textPrimary)
              : t.chipBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected
                  ? (t.isDark ? t.textPrimary : Colors.white)
                  : t.textSecondary),
        ),
      ),
    );
  }
}

/// Píldora de contexto del paciente (fondo menta suave, punto + texto).
class CRPatientContextPill extends StatelessWidget {
  final String label;
  final String? trailing;

  const CRPatientContextPill(
      {super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CR.mintSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                const BoxDecoration(color: CR.mintDark, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: CR.mintInk),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CR.mintInk.withValues(alpha: 0.55)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge "Sugerido por IA" (estrella + texto menta).
class CRAIBadge extends StatelessWidget {
  const CRAIBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: 14, color: CR.mintDark.withValues(alpha: 0.9)),
        const SizedBox(width: 5),
        Text('Sugerido por IA',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CR.mintDark.withValues(alpha: 0.9))),
      ],
    );
  }
}

/// Campo de búsqueda del diseño (fondo gris suave, icono + hint).
class CRSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final VoidCallback? onSubmitted;

  const CRSearchField({
    super.key,
    this.controller,
    required this.hint,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 14),
      decoration: BoxDecoration(
        color: t.field,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: t.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSubmitted?.call(),
              style: TextStyle(fontSize: 15, color: t.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 15, color: t.textTertiary),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de paciente (lista "Casos activos").
class CRPatientCard extends StatelessWidget {
  final String initials;
  final String name;
  final String meta;
  final String? dayLabel;
  final String locLine;
  final String? diagnosis;
  final String? statusLabel;
  final Color? statusColor;
  final String? unitLabel;
  final VoidCallback onTap;

  const CRPatientCard({
    super.key,
    required this.initials,
    required this.name,
    required this.meta,
    this.dayLabel,
    required this.locLine,
    this.diagnosis,
    this.statusLabel,
    this.statusColor,
    this.unitLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: t.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // nombre + edad + día
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CR.mintSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: Text(initials,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.isDark ? CR.mint : CR.mintInk)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary)),
                      const SizedBox(height: 1),
                      Text(meta,
                          style:
                              TextStyle(fontSize: 13, color: t.textSecondary)),
                    ],
                  ),
                ),
                if (dayLabel != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(dayLabel!,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary)),
                  ),
              ],
            ),
            Divider(height: 28, color: t.separator),
            // ubicación
            Row(
              children: [
                Icon(Icons.bed, size: 14, color: t.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(locLine,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: t.textSecondary)),
                ),
              ],
            ),
            // diagnóstico
            if (diagnosis != null && diagnosis!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(diagnosis!,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
            ],
            // estado
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: statusColor ?? CR.mintDark, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(statusLabel ?? 'Hospitalización activa',
                      style: TextStyle(fontSize: 13, color: t.textSecondary)),
                ),
                if (unitLabel != null && unitLabel!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(unitLabel!,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.textTertiary)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Elemento de timeline (bitácora): punto de color + tarjeta.
class CREventCard extends StatelessWidget {
  final String time;
  final String role;
  final String category;
  final String? content;
  final bool pending;
  final String? author;
  final Widget? footer;

  const CREventCard({
    super.key,
    required this.time,
    required this.role,
    required this.category,
    this.content,
    this.pending = false,
    this.author,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    final cfg = CRCategories.of(category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // riel: punto + línea
            SizedBox(
              width: 12,
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: pending ? CR.blue : cfg.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: t.surface, spreadRadius: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                      child:
                          Container(width: 1.5, color: t.separator)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // hora · rol … chip categoría
                    Row(
                      children: [
                        Text(time,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: t.textTertiary)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.textSecondary)),
                        ),
                        if (pending)
                          const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: CR.blue))
                        else
                          CRCategoryChip(category: category, small: true),
                      ],
                    ),
                    // contenido
                    const SizedBox(height: 8),
                    if (content != null && content!.isNotEmpty)
                      Text(content!,
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: t.textPrimary,
                              fontWeight: FontWeight.w500))
                    else if (pending)
                      Text('Transcribiendo audio…',
                          style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: t.textSecondary)),
                    // pie
                    if (author != null || footer != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (author != null) ...[
                            Icon(Icons.person,
                                size: 12, color: t.textTertiary),
                            const SizedBox(width: 4),
                            Text(author!,
                                style: TextStyle(
                                    fontSize: 11, color: t.textTertiary)),
                          ],
                        ],
                      ),
                       ?footer,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de acción del detalle de paciente (Bitácora / Registrar evento…).
class CRActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool highlight;
  final VoidCallback? onTap;
  final bool comingSoon;

  const CRActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    this.highlight = false,
    this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    final accent = highlight ? CR.mintDark : t.textSecondary;
    final iconBg = highlight ? CR.mintSoft : t.chipBg;
    return InkWell(
      onTap: comingSoon ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: t.textSecondary)),
                ],
              ),
            ),
            if (comingSoon)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.chipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Próximamente',
                    style: TextStyle(
                        fontSize: 11, color: t.textTertiary))
              )
            else
              Icon(Icons.chevron_right,
                  size: 20, color: t.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Fila etiqueta/valor del detalle (icono + label + valor a la derecha).
class CRInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const CRInfoRow(
      {super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: t.textTertiary),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(fontSize: 14, color: t.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: t.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Fila label/valor a full-width del detalle (motivo de hospitalización).
class CRDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const CRDetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: t.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: t.textPrimary)),
        ],
      ),
    );
  }
}

/// Barra de navegación superior (chevrotón "Atrás" + título + acción).
class CRNavBar extends StatelessWidget {
  final VoidCallback onBack;
  final String backLabel;
  final String? title;
  final Widget? right;

  const CRNavBar({
    super.key,
    required this.onBack,
    this.backLabel = 'Atrás',
    this.title,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, size: 24, color: CR.blue),
                  const SizedBox(width: 2),
                  Text(backLabel,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: CR.blue)),
                ],
              ),
            ),
          ),
          if (title != null)
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary),
                  ),
                ),
              ),
            ),
          SizedBox(width: right != null ? 0 : 30),
           ?right,
        ],
      ),
    );
  }
}

/// Indicador de turno activo (punto menta + rango horario).
class CRShiftIndicator extends StatelessWidget {
  final String shiftRange;
  const CRShiftIndicator({super.key, this.shiftRange = '08:00–16:00'});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: CR.mintDark, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('Turno activo',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CR.mintDark)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: CR.mintSoft,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(shiftRange,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CR.mintDark)),
        ),
      ],
    );
  }
}

/// Avatar circular con iniciales.
class CRCircleAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final Color? bg;
  final Color? fg;
  final double fontSize;

  const CRCircleAvatar({
    super.key,
    required this.initials,
    this.size = 40,
    this.bg,
    this.fg,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? CR.mint,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(initials,
            style: TextStyle(
                fontSize: fontSize * (size / 40),
                fontWeight: FontWeight.w700,
                color: fg ?? CR.mintInk)),
      ),
    );
  }
}
