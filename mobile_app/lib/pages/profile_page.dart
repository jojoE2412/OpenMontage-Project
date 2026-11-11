import 'package:flutter/material.dart';

import 'login_page.dart';
import 'app_destination_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _showEditProfile(BuildContext context) =>
      openDestination(context, AppDestination.profileInformation);

  void _showHelp(BuildContext context) =>
      openDestination(context, AppDestination.help);

  void _showAbout(BuildContext context) =>
      openDestination(context, AppDestination.about);

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              },
              child: const Text('Log Out'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          children: [
            Container(
              width: 98,
              height: 98,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C5CFF), Color(0xFF4C8DFF)],
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 54,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Creator',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'creator@openmontage.app',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline
                      .withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: [
                  _statItem(context, '12', 'Projects'),
                  _divider(context),
                  _statItem(context, '8', 'Videos'),
                  _divider(context),
                  _statItem(context, '24', 'Assets'),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            _menuItem(
              context,
              Icons.person_outline,
              'Edit Profile',
              'Update your profile information',
              () => _showEditProfile(context),
            ),
            _menuItem(
              context,
              Icons.settings_outlined,
              'Settings',
              'Customize your app preferences',
              () {
                openDestination(context, AppDestination.settings);
              },
            ),
            _menuItem(
              context,
              Icons.link_outlined,
              'Linked Accounts',
              'Connect supported services',
              () => openDestination(context, AppDestination.linkedAccounts),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Support',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            _menuItem(
              context,
              Icons.help_outline,
              'Help & Support',
              'Get help using OpenMontage',
              () => _showHelp(context),
            ),
            _menuItem(
              context,
              Icons.info_outline,
              'About OpenMontage',
              'Learn more about the application',
              () => _showAbout(context),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _showLogoutConfirmation(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline
                        .withValues(alpha: 0.2),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Log Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Container(
      width: 1,
      height: 35,
      color: Theme.of(context).dividerColor,
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right, size: 20),
        ),
      ),
    );
  }
}
