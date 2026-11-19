import 'package:flutter/material.dart';

import 'theme.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: context.zero.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                color: context.zero.muted,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Section label above an [InsetGroup].
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.zero.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class InsetGroup extends StatelessWidget {
  const InsetGroup({
    required this.children,
    this.dividerIndent = 56,
    super.key,
  });

  final List<Widget> children;

  /// Where row separators start; 56 lines up with text after a leading icon.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.zero.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, indent: dividerIndent),
          ],
        ],
      ),
    );
  }
}
