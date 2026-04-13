import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final bg = statusBgColor(status);
    final label = statusLabel(status);
    final icon = _statusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String s) {
    switch (s.toLowerCase()) {
      case 'present':
      case 'on_time':
        return Icons.check_circle_rounded;
      case 'late':
      case 'left_early':
      case 'early_leave':
        return Icons.warning_rounded;
      case 'absent':
        return Icons.cancel_rounded;
      case 'incomplete':
        return Icons.pending_rounded;
      case 'overtime':
      case 'early_arrival':
        return Icons.rocket_launch_rounded;
      case 'approved_absence':
        return Icons.verified_user_rounded;
      case 'manual':
        return Icons.edit_rounded;
      default:
        return Icons.help_rounded;
    }
  }
}
