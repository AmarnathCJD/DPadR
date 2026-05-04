import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bt_client.dart';
import 'home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const DpadrApp());
}

class DpadrApp extends StatefulWidget {
  const DpadrApp({super.key});

  @override
  State<DpadrApp> createState() => _DpadrAppState();
}

class _DpadrAppState extends State<DpadrApp> {
  final BtClient _client = BtClient();
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString('theme');
    if (!mounted) return;
    setState(() {
      _mode = switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
  }

  Future<void> _toggleTheme() async {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final currentlyDark = _mode == ThemeMode.dark ||
        (_mode == ThemeMode.system && brightness == Brightness.dark);
    final next = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    setState(() => _mode = next);
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', next == ThemeMode.dark ? 'dark' : 'light');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dpadr',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: DpadrTheme.light,
      darkTheme: DpadrTheme.dark,
      builder: DpadrTheme.wrap,
      home: HomePage(client: _client, onToggleTheme: _toggleTheme),
    );
  }
}

/// Soft modern palette — cream paper + terracotta accent.
/// Designed to be inviting and confident: rounded geometry, layered surfaces,
/// real depth from soft shadows (no glow), single signature accent used sparingly.
class DpadrPalette {
  /// Outer scaffold.
  final Color bg;

  /// Raised cards / inputs.
  final Color card;

  /// Slightly recessed surfaces (chips, segmented controls).
  final Color sunken;

  /// Primary text.
  final Color ink;

  /// Secondary text.
  final Color muted;

  /// Subtle borders / dividers.
  final Color line;

  /// Brand / signature accent.
  final Color accent;

  /// Foreground when sitting on accent.
  final Color onAccent;

  /// Tinted-accent background (chips, soft buttons).
  final Color accentSoft;

  /// Shadow color base (multiplied by alpha at the cast site).
  final Color shadow;

  const DpadrPalette({
    required this.bg,
    required this.card,
    required this.sunken,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.shadow,
  });

  static const light = DpadrPalette(
    bg: Color(0xFFF8F5F0),
    card: Color(0xFFFFFFFF),
    sunken: Color(0xFFF1ECE4),
    ink: Color(0xFF1A1814),
    muted: Color(0xFF8B847A),
    line: Color(0xFFE8E2D6),
    accent: Color(0xFFE5734A),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFFCE7DD),
    shadow: Color(0xFF2A1F12),
  );

  static const dark = DpadrPalette(
    bg: Color(0xFF1A1815),
    card: Color(0xFF24221E),
    sunken: Color(0xFF1F1D1A),
    ink: Color(0xFFEFE9DE),
    muted: Color(0xFF918878),
    line: Color(0xFF34302A),
    accent: Color(0xFFEC8A66),
    onAccent: Color(0xFF1A0E08),
    accentSoft: Color(0xFF3A2418),
    shadow: Color(0xFF000000),
  );
}

class DpadrThemeProvider extends InheritedWidget {
  final DpadrPalette palette;
  const DpadrThemeProvider({super.key, required this.palette, required super.child});

  static DpadrPalette of(BuildContext ctx) {
    final p = ctx.dependOnInheritedWidgetOfExactType<DpadrThemeProvider>();
    assert(p != null, 'DpadrThemeProvider missing in ancestry');
    return p!.palette;
  }

  @override
  bool updateShouldNotify(DpadrThemeProvider old) => old.palette != palette;
}

/// Reusable shadow stack — soft, layered, no glow.
List<BoxShadow> dpadrShadows(BuildContext ctx, {double depth = 1}) {
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  final p = DpadrThemeProvider.of(ctx);
  if (isDark) {
    // On dark, shadow is barely visible — rely on subtle border instead.
    return [
      BoxShadow(
        color: p.shadow.withValues(alpha: 0.30 * depth),
        blurRadius: 24 * depth,
        offset: Offset(0, 8 * depth),
        spreadRadius: -4,
      ),
    ];
  }
  return [
    BoxShadow(
      color: p.shadow.withValues(alpha: 0.04 * depth),
      blurRadius: 1,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: p.shadow.withValues(alpha: 0.06 * depth),
      blurRadius: 12 * depth,
      offset: Offset(0, 4 * depth),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: p.shadow.withValues(alpha: 0.04 * depth),
      blurRadius: 32 * depth,
      offset: Offset(0, 12 * depth),
      spreadRadius: -8,
    ),
  ];
}

class DpadrTheme {
  static ThemeData get light => _build(DpadrPalette.light, Brightness.light);
  static ThemeData get dark => _build(DpadrPalette.dark, Brightness.dark);

  static ThemeData _build(DpadrPalette p, Brightness b) {
    // Plus Jakarta Sans for everything UI, DM Mono for technical data.
    TextStyle ui(double size, {FontWeight w = FontWeight.w500, double letter = 0, Color? color, double? height}) {
      return GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: w,
        letterSpacing: letter,
        color: color ?? p.ink,
        height: height,
      );
    }

    final textTheme = TextTheme(
      // Hero
      displayLarge: ui(44, w: FontWeight.w700, letter: -1.2, height: 1.05),
      displayMedium: ui(34, w: FontWeight.w700, letter: -0.8, height: 1.1),
      displaySmall: ui(26, w: FontWeight.w700, letter: -0.5, height: 1.15),
      // Section
      headlineMedium: ui(20, w: FontWeight.w600, letter: -0.2, height: 1.25),
      titleLarge: ui(17, w: FontWeight.w600, letter: -0.1),
      titleMedium: ui(15, w: FontWeight.w600),
      titleSmall: ui(13, w: FontWeight.w600, letter: 0.05),
      // Body
      bodyLarge: ui(15, w: FontWeight.w400, height: 1.5),
      bodyMedium: ui(14, w: FontWeight.w400, height: 1.45),
      bodySmall: ui(12.5, w: FontWeight.w400, color: p.muted, height: 1.4),
      // Eyebrow / labels — small caps, tracked
      labelLarge: ui(13, w: FontWeight.w600, letter: 0.1),
      labelMedium: ui(10.5, w: FontWeight.w700, letter: 1.5, color: p.muted),
      labelSmall: ui(11, w: FontWeight.w500, color: p.muted),
    );

    final scheme = ColorScheme(
      brightness: b,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.muted,
      onSecondary: p.bg,
      error: p.accent,
      onError: p.onAccent,
      surface: p.card,
      onSurface: p.ink,
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.sunken,
      surfaceContainer: p.card,
      surfaceContainerHigh: p.card,
      surfaceContainerHighest: p.sunken,
      onSurfaceVariant: p.muted,
      outline: p.line,
      outlineVariant: p.line,
    );

    return ThemeData(
      brightness: b,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: p.bg,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(color: p.ink, size: 20),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: p.ink),
        systemOverlayStyle: b == Brightness.light
            ? SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: p.bg,
                systemNavigationBarIconBrightness: Brightness.dark,
              )
            : SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: p.bg,
                systemNavigationBarIconBrightness: Brightness.light,
              ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.ink,
          foregroundColor: p.bg,
          disabledBackgroundColor: p.sunken,
          disabledForegroundColor: p.muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.muted,
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.sunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: GoogleFonts.plusJakartaSans(color: p.muted, fontSize: 14),
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
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
    );
  }

  static Widget wrap(BuildContext context, Widget? child) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? DpadrPalette.dark : DpadrPalette.light;
    return DpadrThemeProvider(palette: palette, child: child ?? const SizedBox());
  }
}

/// Small mono helper.
TextStyle dpadrMono(BuildContext ctx,
    {double size = 12, FontWeight w = FontWeight.w500, double letter = 0, Color? color}) {
  return GoogleFonts.dmMono(
    fontSize: size,
    fontWeight: w,
    letterSpacing: letter,
    color: color ?? DpadrThemeProvider.of(ctx).ink,
  );
}
