import 'package:flutter/material.dart';

class ProjectCard extends StatelessWidget {
  final String title;
  final String style;
  final String duration;
  final String status;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  const ProjectCard({
    super.key,
    required this.title,
    required this.style,
    required this.duration,
    required this.status,
    required this.icon,
    this.onTap,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final bool isProcessing = status == 'Processing';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),

            const SizedBox(width: 14),

            // Project Information
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    '$style • $duration',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                  const SizedBox(height: 7),

                  Row(
                    children: [
                      Icon(
                        isProcessing ? Icons.autorenew : Icons.check_circle,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary,
                      ),

                      const SizedBox(width: 5),

                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            if (onMore != null)
              IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
            if (onMore == null) const Icon(Icons.chevron_right, size: 22),
          ],
        ),
      ),
    );
  }
}
