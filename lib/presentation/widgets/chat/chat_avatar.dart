import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/utils/media_utils.dart';

/// Authenticated relative media URLs with an initial/icon fallback on failure.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.title,
    this.url,
    this.token,
    this.radius = 20,
    this.foreground,
    this.background,
    this.fallbackIcon,
  });

  final String title;
  final String? url;
  final String? token;
  final double radius;
  final Color? foreground;
  final Color? background;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final fullUrl = resolveMediaUrl(null, existingUrl: url);
    final uri = Uri.tryParse(fullUrl);
    final base = Uri.parse(ApiConstants.baseUrl);
    final hasImage =
        uri != null &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        ['http', 'https'].contains(uri.scheme);
    // A user-supplied external avatar must not receive our bearer token.
    final headers =
        token != null && hasImage && uri != null && uri.origin == base.origin
        ? {'Authorization': 'Bearer $token'}
        : null;
    final color = foreground ?? Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: background ?? color.withValues(alpha: 0.15),
      foregroundColor: color,
      foregroundImage: hasImage
          ? NetworkImage(fullUrl, headers: headers)
          : null,
      onForegroundImageError: hasImage ? (_, __) {} : null,
      child: fallbackIcon != null
          ? Icon(fallbackIcon, size: radius)
          : Text(
              title.trim().isEmpty
                  ? '?'
                  : title.trim().characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: radius * 0.85,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
