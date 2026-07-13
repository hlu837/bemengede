// lib/screens/auth/widgets/role_selector.dart

import 'package:flutter/material.dart';
import '../../../models/user_profile.dart';
import '../../../utils/constants.dart';

class RoleSelector extends StatelessWidget {
  final UserRole selected;
  final String label;
  final ValueChanged<UserRole> onChanged;

  const RoleSelector({
    super.key,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _RoleCard(
              role: UserRole.traveler,
              selected: selected == UserRole.traveler,
              icon: Icons.flight_takeoff_rounded,
              title: 'Traveler',
              subtitle: 'Carry packages & earn',
              onTap: () => onChanged(UserRole.traveler),
            )),
            const SizedBox(width: 12),
            Expanded(child: _RoleCard(
              role: UserRole.sender,
              selected: selected == UserRole.sender,
              icon: Icons.local_shipping_rounded,
              title: 'Sender',
              subtitle: 'Send a package',
              onTap: () => onChanged(UserRole.sender),
            )),
          ],
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'You can switch roles anytime in settings',
            style: TextStyle(fontSize: 12, color: Color(AppColors.textSecondary)),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final UserRole role;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(AppColors.primaryLight) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(AppColors.primary) : const Color(AppColors.border),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected
                  ? const Color(AppColors.primary)
                  : const Color(AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(AppColors.primary)
                    : const Color(AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
