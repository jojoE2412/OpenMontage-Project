import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notifications = true;
  bool autoSave = true;

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = AppThemeController.instance.themeMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _sectionTitle(context, 'Appearance'),
          _settingItem(
            context,
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: '${_themeLabel(currentTheme)} mode is active',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeDialog(context),
          ),
          const SizedBox(height: 18),
          _sectionTitle(context, 'AI'),
          _settingItem(
            context,
            icon: Icons.smart_toy_outlined,
            title: 'Default Provider',
            subtitle: 'OpenMontage Local',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          _settingItem(
            context,
            icon: Icons.auto_awesome_rounded,
            title: 'Default Model',
            subtitle: 'LTX-Video',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 18),
          _sectionTitle(context, 'Video'),
          _settingItem(
            context,
            icon: Icons.aspect_ratio_rounded,
            title: 'Resolution',
            subtitle: '720p',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          _settingItem(
            context,
            icon: Icons.speed_rounded,
            title: 'FPS',
            subtitle: '24',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          _settingItem(
            context,
            icon: Icons.crop_16_9_rounded,
            title: 'Aspect Ratio',
            subtitle: '16:9',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          _settingItem(
            context,
            icon: Icons.timer_outlined,
            title: 'Default Duration',
            subtitle: '30s',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          _settingItem(
            context,
            icon: Icons.style_rounded,
            title: 'Default Style',
            subtitle: 'Cinematic',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 18),
          _sectionTitle(context, 'Account'),
          _settingItem(
            context,
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: 'Manage account details',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          _settingItem(
            context,
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Receive project and system notifications',
            trailing: Switch(
              value: notifications,
              onChanged: (value) => setState(() => notifications = value),
            ),
          ),
          _settingItem(
            context,
            icon: Icons.save_outlined,
            title: 'Auto Save',
            subtitle: 'Automatically save your projects',
            trailing: Switch(
              value: autoSave,
              onChanged: (value) => setState(() => autoSave = value),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle(context, 'About'),
          _settingItem(
            context,
            icon: Icons.info_outline,
            title: 'OpenMontage',
            subtitle: 'AI Video Production Studio',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          _settingItem(
            context,
            icon: Icons.build_circle_outlined,
            title: 'Version',
            subtitle: '1.0.0',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'OpenMontage Mobile',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _settingItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Theme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark'),
                trailing:
                    AppThemeController.instance.themeMode == ThemeMode.dark
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  AppThemeController.instance.setThemeMode(ThemeMode.dark);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.light_mode_outlined),
                title: const Text('Light'),
                trailing:
                    AppThemeController.instance.themeMode == ThemeMode.light
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  AppThemeController.instance.setThemeMode(ThemeMode.light);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_suggest_outlined),
                title: const Text('System'),
                trailing:
                    AppThemeController.instance.themeMode == ThemeMode.system
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  AppThemeController.instance.setThemeMode(ThemeMode.system);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
