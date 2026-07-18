import 'package:flutter/material.dart';

import 'app_localizations.dart';

abstract final class AbyssLPalette {
  static const ink = Color(0xFF21252D);
  static const inkRaised = Color(0xFF23272F);
  static const inkBorder = Color(0xFF4B515C);
  static const blue = Color(0xFF0E58F4);
  static const blueHover = Color(0xFF0B4EDB);
  static const blueSoft = Color(0xFFE9F0FF);
  static const canvas = Color(0xFFF6F7F9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1F3F6);
  static const outline = Color(0xFFD7DCE3);
  static const outlineStrong = Color(0xFFBAC2CD);
  static const text = Color(0xFF202631);
  static const textMuted = Color(0xFF68717F);
  static const success = Color(0xFF18A957);
  static const danger = Color(0xFFD92D43);

  static Color canvasFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF11151B) : canvas;

  static Color surfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF191E26) : surface;

  static Color mutedSurfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF202630) : surfaceMuted;

  static Color outlineFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF39414D) : outline;
}

abstract final class AbyssLSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

ThemeData buildAbyssLTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AbyssLPalette.blue,
        brightness: brightness,
      ).copyWith(
        primary: AbyssLPalette.blue,
        onPrimary: Colors.white,
        error: AbyssLPalette.danger,
        surface: AbyssLPalette.surfaceFor(brightness),
        surfaceContainerHighest: AbyssLPalette.mutedSurfaceFor(brightness),
        outline: AbyssLPalette.outlineFor(brightness),
        outlineVariant: AbyssLPalette.outlineFor(brightness),
      );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
  );
  final textTheme = base.textTheme
      .apply(
        bodyColor: isDark ? const Color(0xFFE9EDF3) : AbyssLPalette.text,
        displayColor: isDark ? const Color(0xFFF7F9FC) : AbyssLPalette.text,
      )
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontSize: 22,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 18,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          height: 1.55,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.45,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.35,
        ),
      );

  OutlineInputBorder inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    scaffoldBackgroundColor: AbyssLPalette.canvasFor(brightness),
    canvasColor: AbyssLPalette.surfaceFor(brightness),
    dividerColor: AbyssLPalette.outlineFor(brightness),
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AbyssLPalette.surfaceFor(brightness),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: inputBorder(AbyssLPalette.outlineFor(brightness)),
      enabledBorder: inputBorder(AbyssLPalette.outlineFor(brightness)),
      disabledBorder: inputBorder(
        AbyssLPalette.outlineFor(brightness).withValues(alpha: 0.55),
      ),
      focusedBorder: inputBorder(AbyssLPalette.blue, width: 1.5),
      hintStyle: TextStyle(
        color: isDark ? const Color(0xFF9099A6) : AbyssLPalette.textMuted,
      ),
      labelStyle: TextStyle(
        color: isDark ? const Color(0xFFBAC2CE) : AbyssLPalette.textMuted,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AbyssLPalette.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AbyssLPalette.blue.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? const Color(0xFFE9EDF3) : AbyssLPalette.text,
        side: BorderSide(color: AbyssLPalette.outlineFor(brightness)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AbyssLPalette.blue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AbyssLPalette.blue
            : (isDark ? const Color(0xFF4C5562) : const Color(0xFFCBD1D9)),
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AbyssLPalette.surfaceFor(brightness),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AbyssLPalette.outlineFor(brightness)),
      ),
    ),
  );
}

class AbyssLBrand extends StatelessWidget {
  const AbyssLBrand({super.key, this.showWordmark = true});

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/abyssl_mark.png',
          width: 32,
          height: 38,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        if (showWordmark) ...[
          const SizedBox(width: 10),
          const Text(
            'AbyssL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
          ),
        ],
      ],
    );
  }
}

class AbyssLKeyboardHint extends StatelessWidget {
  const AbyssLKeyboardHint(this.label, {super.key, this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: dark ? const Color(0xFFDCE2EC) : AbyssLPalette.textMuted,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AbyssLNavItem extends StatelessWidget {
  const AbyssLNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizedLabel = AbyssLAppLocalizations.of(context).text(label);
    final color = selected
        ? AbyssLPalette.blue
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: localizedLabel,
      child: Semantics(
        selected: selected,
        button: true,
        label: localizedLabel,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 78,
            height: 82,
            decoration: BoxDecoration(
              color: selected ? AbyssLPalette.blueSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 7),
                Text(
                  localizedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AbyssLPane extends StatelessWidget {
  const AbyssLPane({
    super.key,
    required this.header,
    required this.child,
    this.footer,
    this.backgroundColor,
    this.headerHeight = 56,
  });

  final Widget header;
  final Widget child;
  final Widget? footer;
  final Color? backgroundColor;
  final double headerHeight;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final outline = AbyssLPalette.outlineFor(brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AbyssLPalette.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: headerHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: outline)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: header,
                ),
              ),
            ),
            Expanded(child: child),
            if (footer != null) ...[
              Divider(height: 1, color: outline),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class AbyssLSectionLabel extends StatelessWidget {
  const AbyssLSectionLabel(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final localizedLabel = AbyssLAppLocalizations.of(context).text(label);
    return Text(
      localizedLabel.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.65,
      ),
    );
  }
}
