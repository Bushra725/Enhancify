import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ButtonStyleKind { white, brand, dark, outline }

/// Pill-shaped button used throughout the app.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = ButtonStyleKind.white,
    this.trailing,
    this.leading,
    this.height = 54,
    this.expand = true,
    this.loading = false,
    this.fontSize = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonStyleKind kind;
  final Widget? trailing;
  final Widget? leading;
  final double height;
  final bool expand;
  final bool loading;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final (Color fg, Color? bg, Gradient? gradient, BoxBorder? border) =
        switch (kind) {
      ButtonStyleKind.white =>
        (Colors.black, Colors.white, null, Border.all(color: Colors.black12)),
      ButtonStyleKind.brand => (Colors.white, null, AppColors.brandGradient, null),
      ButtonStyleKind.dark => (Colors.white, AppColors.primary, null, null),
      ButtonStyleKind.outline => (
          Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : AppColors.maroon,
          Colors.transparent,
          null,
          Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.border
                  : const Color(0xFFF5CADC),
              width: 1.4)
        ),
    };
    final text = Text(
      label,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: fg,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    );
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        else if (expand)
          Flexible(child: text)
        else
          text,
        if (trailing != null && !loading) ...[
          const SizedBox(width: 10),
          IconTheme(data: IconThemeData(color: fg, size: 18), child: trailing!),
        ],
      ],
    );
    return Opacity(
      opacity: disabled && !loading ? 0.45 : 1,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient,
          border: border,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: disabled ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class ProBadge extends StatelessWidget {
  const ProBadge({super.key, this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'PRO',
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 9 : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Gradient tile with an icon, used where the reference app shows sample
/// photos. Swap with real images via `imageUrl` in the catalog.
class GradientThumb extends StatelessWidget {
  const GradientThumb({
    super.key,
    required this.colors,
    required this.icon,
    this.label,
    this.imageUrl,
    this.radius = 14,
  });

  final List<Color> colors;
  final IconData icon;
  final String? label;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 34),
          ),
          if (label != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: imageUrl == null
          ? fallback
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

/// Rounded dark card used for settings groups etc.
class DarkCard extends StatelessWidget {
  const DarkCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
