import 'package:material_ui/material_ui.dart';

import 'inou_theme.dart';

/// Minimalist studio container with hairline border (or subtle borderless
/// fill when nested, or soft ambient shadow when [elevated]).
class InouSurface extends StatelessWidget {
  const InouSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 14,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0.9,
    this.elevated = false,
    this.subtle = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final bool elevated;
  final bool subtle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final bg = backgroundColor ?? (subtle ? t.surfaceMuted : t.surface);
    final border =
        borderColor ?? (subtle ? Colors.transparent : t.borderHairline);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: subtle && borderColor == null
            ? null
            : Border.all(color: border, width: borderWidth),
        boxShadow: elevated && !t.isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.045),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: onTap != null
            ? InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              )
            : Padding(padding: padding, child: child),
      ),
    );
  }
}

enum InouBadgeTone { neutral, accent, success, warning, danger }

/// Compact studio status badge with crisp typography and soft tint.
class InouBadge extends StatelessWidget {
  const InouBadge({
    super.key,
    required this.label,
    this.tone = InouBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final InouBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final (bg, fg, border) = switch (tone) {
      InouBadgeTone.neutral => (
        t.surfaceMuted,
        t.textSecondary,
        t.borderHairline,
      ),
      InouBadgeTone.accent => (
        t.accentSoft,
        t.accent,
        t.accent.withValues(alpha: 0.28),
      ),
      InouBadgeTone.success => (
        t.successSoft,
        t.success,
        t.success.withValues(alpha: 0.28),
      ),
      InouBadgeTone.warning => (
        t.warningSoft,
        t.warning,
        t.warning.withValues(alpha: 0.30),
      ),
      InouBadgeTone.danger => (
        t.dangerSoft,
        t.danger,
        t.danger.withValues(alpha: 0.28),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live indicator dot + caption used in top bars (`Gemini · 已连接`, `本地演示`).
class InouStatusDot extends StatelessWidget {
  const InouStatusDot({
    super.key,
    required this.label,
    required this.connected,
    this.onTap,
  });

  final String label;
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final dotColor = connected ? t.success : t.warning;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.borderHairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: content,
    );
  }
}

/// Quiet Linear-style section title row with optional trailing action button.
class InouSectionHeader extends StatelessWidget {
  const InouSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: t.textPrimary,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Collapsible agent tool-call trace disclosure ("AI 思考过程 · N 步").
class InouThinkingDisclosure extends StatefulWidget {
  const InouThinkingDisclosure({
    super.key,
    required this.traces,
    this.antiSpoilerBlocked = false,
    this.initiallyExpanded = false,
  });

  final List<String> traces;
  final bool antiSpoilerBlocked;
  final bool initiallyExpanded;

  @override
  State<InouThinkingDisclosure> createState() => _InouThinkingDisclosureState();
}

class _InouThinkingDisclosureState extends State<InouThinkingDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (widget.traces.isEmpty && !widget.antiSpoilerBlocked) {
      return const SizedBox.shrink();
    }
    final t = context.inou;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.antiSpoilerBlocked
              ? t.warning.withValues(alpha: 0.45)
              : t.borderHairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    widget.antiSpoilerBlocked
                        ? Icons.shield_outlined
                        : Icons.auto_awesome_outlined,
                    size: 14,
                    color: widget.antiSpoilerBlocked ? t.warning : t.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.antiSpoilerBlocked
                          ? 'AI 思考过程 · 已触发防剧透拦截 (${widget.traces.length} 步)'
                          : 'AI 思考与工具链路 (${widget.traces.length} 步)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: t.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in widget.traces)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 5, right: 6),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: line.contains('[拦截]')
                                  ? t.warning
                                  : t.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              line,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                color: t.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Single metric datum rendered in [InouMetricBar].
class InouMetricItem {
  const InouMetricItem({
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
}

/// Unified architectural 4-cell KPI strip separated by crisp hairlines. Fits
/// phones and tablets without multi-line pill wrapping.
class InouMetricBar extends StatelessWidget {
  const InouMetricBar({super.key, required this.items});

  final List<InouMetricItem> items;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      padding: EdgeInsets.zero,
      radius: 12,
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: t.borderHairline),
              Expanded(
                child: InkWell(
                  onTap: items[i].onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 11,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          items[i].value,
                          style: InouTypography.tabular(
                            TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: items[i].valueColor ?? t.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Clean studio empty state module.
class InouEmptyState extends StatelessWidget {
  const InouEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 24, color: t.accent),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: t.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: t.textSecondary,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}
