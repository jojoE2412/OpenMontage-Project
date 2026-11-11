import 'package:flutter/material.dart';

import '../services/library_storage.dart';
import '../services/project_storage.dart';
import '../theme/app_theme.dart';
import 'ai_video_generator_page.dart';
import 'login_page.dart';
import 'template_pages.dart';

enum AppDestination {
  settings,
  profileInformation,
  changePassword,
  linkedAccounts,
  language,
  theme,
  notifications,
  aiProvider,
  defaultModel,
  aiBudget,
  localAi,
  storage,
  templates,
  templateDetail,
  notificationCenter,
  help,
  about,
}

void openDestination(BuildContext context, AppDestination destination) {
  if (destination == AppDestination.templates) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TemplateGalleryPage()),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AppDestinationPage(destination: destination),
    ),
  );
}

void showComingSoon(BuildContext context, String feature) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.auto_awesome_outlined),
      title: Text('$feature · Coming Soon'),
      content: const Text(
        'This OpenMontage feature is being prepared for a future release.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class OpenMontageDrawer extends StatelessWidget {
  const OpenMontageDrawer({super.key, required this.onTabSelected});
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF202B47), Color(0xFF30426F)],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Color(0xFF5963E8),
                  child: Text('JD', style: TextStyle(color: Colors.white)),
                ),
                SizedBox(height: 12),
                Text(
                  'John Doe',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'john@domain.com',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          _drawerItem(
            context,
            'Home',
            Icons.home_outlined,
            onTap: () => _select(context, 0),
          ),
          _drawerItem(
            context,
            'My Projects',
            Icons.folder_outlined,
            onTap: () => _select(context, 1),
          ),
          _drawerItem(
            context,
            'Create',
            Icons.add_circle_outline,
            onTap: () => _select(context, 2),
          ),
          _drawerItem(
            context,
            'Library',
            Icons.video_library_outlined,
            onTap: () => _select(context, 3),
          ),
          _drawerItem(
            context,
            'Templates',
            Icons.dashboard_outlined,
            onTap: () => _open(context, AppDestination.templates),
          ),
          _drawerItem(
            context,
            'AI Provider',
            Icons.hub_outlined,
            onTap: () => _open(context, AppDestination.aiProvider),
          ),
          _drawerItem(
            context,
            'Local AI Settings',
            Icons.memory_outlined,
            onTap: () => _open(context, AppDestination.localAi),
          ),
          _drawerItem(
            context,
            'Storage',
            Icons.storage_outlined,
            onTap: () => _open(context, AppDestination.storage),
          ),
          const Divider(),
          _drawerItem(
            context,
            'Settings',
            Icons.settings_outlined,
            onTap: () => _open(context, AppDestination.settings),
          ),
          _drawerItem(
            context,
            'Help & Support',
            Icons.help_outline,
            onTap: () => _open(context, AppDestination.help),
          ),
          const Spacer(),
          _drawerItem(
            context,
            'Log Out',
            Icons.logout,
            color: Colors.redAccent,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (_) => false,
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _drawerItem(
    BuildContext context,
    String title,
    IconData icon, {
    required VoidCallback onTap,
    Color? color,
  }) => ListTile(
    dense: true,
    leading: Icon(icon, size: 20, color: color),
    title: Text(title, style: TextStyle(fontSize: 13, color: color)),
    onTap: onTap,
  );

  void _select(BuildContext context, int index) {
    Navigator.pop(context);
    onTabSelected(index);
  }

  void _open(BuildContext context, AppDestination destination) {
    Navigator.pop(context);
    openDestination(context, destination);
  }
}

class AppDestinationPage extends StatefulWidget {
  const AppDestinationPage({super.key, required this.destination});
  final AppDestination destination;
  @override
  State<AppDestinationPage> createState() => _AppDestinationPageState();
}

class _AppDestinationPageState extends State<AppDestinationPage> {
  final _name = TextEditingController(text: 'John Doe');
  final _email = TextEditingController(text: 'john@domain.com');
  final _username = TextEditingController(text: '@johndoe');
  final _passwords = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  String _language = 'English';
  String _providerMode = 'Auto';
  String _videoModel = 'Auto';
  bool _fallback = true;
  final Map<String, bool> _toggles = {
    'Generation Updates': true,
    'Project Updates': true,
    'System Notifications': true,
    'Marketing': false,
  };

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _username.dispose();
    for (final c in _passwords) {
      c.dispose();
    }
    super.dispose();
  }

  String get _title => switch (widget.destination) {
    AppDestination.settings => 'Settings',
    AppDestination.profileInformation => 'Profile Information',
    AppDestination.changePassword => 'Change Password',
    AppDestination.linkedAccounts => 'Linked Accounts',
    AppDestination.language => 'Language',
    AppDestination.theme => 'Appearance',
    AppDestination.notifications => 'Notifications',
    AppDestination.aiProvider => 'AI Providers',
    AppDestination.defaultModel => 'Default Models',
    AppDestination.aiBudget => 'AI Budget',
    AppDestination.localAi => 'Local AI',
    AppDestination.storage => 'Storage',
    AppDestination.templates => 'Templates',
    AppDestination.templateDetail => 'Cinematic Travel',
    AppDestination.notificationCenter => 'Notifications',
    AppDestination.help => 'Help & Support',
    AppDestination.about => 'About OpenMontage',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: _content(context),
      ),
    ),
  );

  List<Widget> _content(BuildContext context) => switch (widget.destination) {
    AppDestination.settings => _settings(context),
    AppDestination.profileInformation => _profileInformation(context),
    AppDestination.changePassword => _changePassword(context),
    AppDestination.linkedAccounts => _linkedAccounts(context),
    AppDestination.language => _languagePage(context),
    AppDestination.theme => _theme(context),
    AppDestination.notifications => _notificationSettings(context),
    AppDestination.aiProvider => _aiProvider(context),
    AppDestination.defaultModel => _defaultModel(context),
    AppDestination.aiBudget => _aiBudget(context),
    AppDestination.localAi => _localAi(context),
    AppDestination.storage => _storage(context),
    AppDestination.templates => _templates(context),
    AppDestination.templateDetail => _templateDetail(context),
    AppDestination.notificationCenter => _notificationCenter(context),
    AppDestination.help => _help(context),
    AppDestination.about => _about(context),
  };

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: Color(0xFF718097),
      ),
    ),
  );
  Widget _card(Widget child) => Card(child: child);
  Widget _saveButton(String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: SizedBox(
      height: 50,
      child: FilledButton(onPressed: onPressed, child: Text(label)),
    ),
  );
  void _saved(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  List<Widget> _profileInformation(BuildContext context) => [
    const Center(
      child: CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
    ),
    Center(
      child: TextButton.icon(
        onPressed: () => showComingSoon(context, 'Avatar upload'),
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Change Avatar'),
      ),
    ),
    _field('Name', _name),
    _field('Email', _email, keyboard: TextInputType.emailAddress),
    _field('Username', _username),
    _saveButton(
      'Save Changes',
      () => _saved('Profile changes saved on this device.'),
    ),
  ];

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  List<Widget> _changePassword(BuildContext context) => [
    const Text('Update your password. This demo validates input locally only.'),
    _field('Current Password', _passwords[0], obscure: true),
    _field('New Password', _passwords[1], obscure: true),
    _field('Confirm Password', _passwords[2], obscure: true),
    _saveButton('Update Password', () {
      if (_passwords[0].text.isEmpty ||
          _passwords[1].text.length < 8 ||
          _passwords[1].text != _passwords[2].text) {
        _saved(
          _passwords[1].text.length < 8
              ? 'New password must be at least 8 characters.'
              : 'Check required fields and confirm the new password.',
        );
      } else {
        _saved('Password updated in the local demo.');
      }
    }),
  ];

  List<Widget> _linkedAccounts(BuildContext context) => [
    const Text('Connect your accounts to access additional services.'),
    for (final account in [
      ('Google', Icons.g_mobiledata),
      ('Apple', Icons.apple),
      ('GitHub', Icons.code),
    ])
      _card(
        ListTile(
          leading: Icon(account.$2, size: 28),
          title: Text(account.$1),
          subtitle: const Text('Not connected'),
          trailing: OutlinedButton(
            onPressed: () =>
                showComingSoon(context, '${account.$1} account connection'),
            child: const Text('Connect'),
          ),
        ),
      ),
  ];

  List<Widget> _languagePage(BuildContext context) => [
    _card(
      RadioGroup<String>(
        groupValue: _language,
        onChanged: (value) {
          if (value != null) setState(() => _language = value);
        },
        child: Column(
          children: [
            for (final language in ['English', 'Bahasa Indonesia'])
              RadioListTile<String>(value: language, title: Text(language)),
          ],
        ),
      ),
    ),
    Text(
      'Language preference: $_language',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ];

  List<Widget> _theme(BuildContext context) => [
    for (final entry in [
      (ThemeMode.system, 'System', Icons.settings_suggest_outlined),
      (ThemeMode.light, 'Light', Icons.light_mode_outlined),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
    ])
      _card(
        ListTile(
          leading: Icon(entry.$3),
          title: Text(entry.$2),
          trailing: AppThemeController.instance.themeMode == entry.$1
              ? const Icon(Icons.check, color: Color(0xFF5963E8))
              : null,
          onTap: () => AppThemeController.instance.setThemeMode(entry.$1),
        ),
      ),
  ];

  List<Widget> _notificationSettings(BuildContext context) => [
    for (final entry in _toggles.entries.toList())
      _card(
        SwitchListTile(
          title: Text(entry.key),
          value: entry.value,
          onChanged: (v) => setState(() => _toggles[entry.key] = v),
        ),
      ),
  ];

  List<Widget> _aiProvider(BuildContext context) => [
    _section('External Providers'),
    _card(
      const ListTile(
        leading: Icon(Icons.cloud_outlined),
        title: Text('Hugging Face · LTX Video'),
        subtitle: Text('Not connected · backend setup required'),
        trailing: _StatusBadge('Unavailable'),
      ),
    ),
    _section('Local AI'),
    _card(
      const ListTile(
        leading: Icon(Icons.memory_outlined),
        title: Text('Local AI'),
        subtitle: Text('Available when a local engine is connected'),
        trailing: _StatusBadge('Not configured'),
      ),
    ),
    _section('AI Routing'),
    _card(
      RadioGroup<String>(
        groupValue: _providerMode,
        onChanged: (value) {
          if (value != null) setState(() => _providerMode = value);
        },
        child: Column(
          children: [
            for (final x in ['Auto', 'Manual'])
              RadioListTile<String>(value: x, title: Text(x)),
          ],
        ),
      ),
    ),
    SwitchListTile(
      title: const Text('Fallback to Local AI'),
      subtitle: const Text(
        'Use local AI when an external provider is unavailable.',
      ),
      value: _fallback,
      onChanged: (v) => setState(() => _fallback = v),
    ),
  ];

  List<Widget> _defaultModel(BuildContext context) => [
    const Text(
      'These are local preferences only. Provider availability and model execution are not connected.',
    ),
    _section('Video Generation'),
    _card(
      RadioGroup<String>(
        groupValue: _videoModel,
        onChanged: (value) {
          if (value != null) setState(() => _videoModel = value);
        },
        child: Column(
          children: [
            for (final x in ['Auto', 'LTX Video', 'Local AI'])
              RadioListTile<String>(value: x, title: Text(x)),
          ],
        ),
      ),
    ),
    for (final section in ['Image Generation', 'Text / Planning']) ...[
      _section(section),
      _card(const ListTile(title: Text('Auto'), trailing: Icon(Icons.check))),
    ],
  ];

  List<Widget> _aiBudget(BuildContext context) => [
    _card(
      const ListTile(
        leading: Icon(Icons.payments_outlined),
        title: Text('External AI Usage'),
        trailing: Text('--'),
      ),
    ),
    _card(
      const ListTile(
        leading: Icon(Icons.calendar_month_outlined),
        title: Text('Monthly Limit'),
        trailing: Text('--'),
      ),
    ),
    _card(
      const ListTile(
        leading: Icon(Icons.memory_outlined),
        title: Text('Local AI Fallback'),
        subtitle: Text('Enabled in routing preferences'),
      ),
    ),
    _card(
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('Provider Usage'),
        subtitle: Text('Not available yet. No cost estimate is fabricated.'),
      ),
    ),
  ];

  List<Widget> _localAi(BuildContext context) => [
    _card(
      const ListTile(
        title: Text('Status'),
        subtitle: Text('Not Configured'),
        trailing: _StatusBadge('Unavailable'),
      ),
    ),
    _section('Hardware'),
    const Text(
      'Hardware information will be detected when Local AI is connected.',
    ),
    _card(
      const ListTile(
        title: Text('GPU / VRAM / CPU'),
        subtitle: Text('Not detected'),
      ),
    ),
    _section('Mode'),
    _card(
      RadioGroup<String>(
        groupValue: _videoModel,
        onChanged: (value) {
          if (value != null) setState(() => _videoModel = value);
        },
        child: Column(
          children: [
            for (final x in ['Draft', 'Standard'])
              RadioListTile<String>(value: x, title: Text(x)),
          ],
        ),
      ),
    ),
    _section('Recommended Settings'),
    _card(
      const ListTile(
        title: Text('Resolution'),
        subtitle: Text('360p · short duration · batch 1 · concurrent jobs 1'),
      ),
    ),
    const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
        'Experimental. Recommendations are placeholders until a local engine reports device capability.',
      ),
    ),
  ];

  List<Widget> _settings(BuildContext context) => [
    _section('Account'),
    _settingRow(
      context,
      'Profile Information',
      Icons.person_outline,
      AppDestination.profileInformation,
    ),
    _settingRow(
      context,
      'Change Password',
      Icons.lock_outline,
      AppDestination.changePassword,
    ),
    _settingRow(
      context,
      'Linked Accounts',
      Icons.link,
      AppDestination.linkedAccounts,
    ),
    _section('App Settings'),
    _settingRow(context, 'Language', Icons.language, AppDestination.language),
    _settingRow(
      context,
      'Appearance',
      Icons.palette_outlined,
      AppDestination.theme,
    ),
    _settingRow(
      context,
      'Notifications',
      Icons.notifications_outlined,
      AppDestination.notifications,
    ),
    _section('AI Provider'),
    _settingRow(
      context,
      'Manage Providers',
      Icons.hub_outlined,
      AppDestination.aiProvider,
    ),
    _settingRow(
      context,
      'Default Model',
      Icons.tune,
      AppDestination.defaultModel,
    ),
    _settingRow(
      context,
      'AI Budget',
      Icons.payments_outlined,
      AppDestination.aiBudget,
    ),
    _settingRow(
      context,
      'Local AI',
      Icons.memory_outlined,
      AppDestination.localAi,
    ),
    _section('Storage'),
    _settingRow(
      context,
      'Manage Storage',
      Icons.storage_outlined,
      AppDestination.storage,
    ),
    _settingRow(
      context,
      'Help & Support',
      Icons.help_outline,
      AppDestination.help,
    ),
    _settingRow(context, 'About', Icons.info_outline, AppDestination.about),
  ];

  Widget _settingRow(
    BuildContext context,
    String title,
    IconData icon,
    AppDestination destination,
  ) => _card(
    ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openDestination(context, destination),
    ),
  );
  List<Widget> _storage(BuildContext context) => [
    FutureBuilder<List<dynamic>>(
      future: Future.wait([
        ProjectStorage.getProjects(),
        LibraryStorage.getAssets(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = snapshot.data?[0] as List<Map<String, dynamic>>? ?? [];
        final assets = snapshot.data?[1] as List<Map<String, dynamic>>? ?? [];
        return Column(
          children: [
            _card(
              const ListTile(
                leading: Icon(Icons.storage_outlined),
                title: Text('Used Storage'),
                subtitle: Text(
                  'Storage size is unavailable in the local index.',
                ),
              ),
            ),
            _card(
              ListTile(
                title: const Text('Projects'),
                trailing: Text('${projects.length}'),
              ),
            ),
            _card(
              ListTile(
                title: const Text('Videos'),
                trailing: Text(
                  '${projects.where((p) => p['status'] == 'Completed').length}',
                ),
              ),
            ),
            _card(
              ListTile(
                title: const Text('Images'),
                trailing: Text(
                  '${assets.where((a) => a['type'] == 'image').length}',
                ),
              ),
            ),
            _card(
              ListTile(
                title: const Text('Audio'),
                trailing: Text(
                  '${assets.where((a) => a['type'] == 'audio').length}',
                ),
              ),
            ),
            _card(
              const ListTile(
                title: Text('Manage Files'),
                subtitle: Text('Use the Library asset manager.'),
              ),
            ),
            ListTile(
              title: const Text('Clear Cache'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showComingSoon(context, 'Cache management'),
            ),
          ],
        );
      },
    ),
  ];

  List<Widget> _templates(BuildContext context) => [
    const Text('Starter templates · local demo content'),
    for (final name in [
      'Cinematic Travel',
      'Product Showcase',
      'Documentary',
      'Social Media',
      'Anime Story',
      'Minimal',
    ])
      _card(
        ListTile(
          leading: const Icon(Icons.movie_filter_outlined),
          title: Text(name),
          subtitle: const Text('Open template details'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openDestination(context, AppDestination.templateDetail),
        ),
      ),
  ];

  List<Widget> _templateDetail(BuildContext context) => [
    Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF5B6991), Color(0xFFEDB278), Color(0xFF344461)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white, size: 52),
      ),
    ),
    _section('Description'),
    const Text(
      'Beautiful cinematic travel footage with deliberate pacing and warm natural color.',
    ),
    _section('Style'),
    _card(const ListTile(title: Text('Cinematic'))),
    _card(
      const ListTile(
        title: Text('Recommended Duration'),
        trailing: Text('15s'),
      ),
    ),
    _saveButton(
      'Use Template',
      () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AiVideoGeneratorPage(
            initialProject: {
              'title': 'Cinematic Travel',
              'prompt': 'Beautiful cinematic travel footage',
              'style': 'Cinematic',
              'duration': '15s',
              'aspectRatio': '16:9',
            },
          ),
        ),
      ),
    ),
  ];

  List<Widget> _notificationCenter(BuildContext context) => [
    Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => _saved('Notifications marked as read.'),
        child: const Text('Mark all as read'),
      ),
    ),
    _section('Today'),
    _notification('Video generation completed', 'Sunrise in Bali'),
    _section('Yesterday'),
    _notification('Project saved', 'Product Showcase'),
    _section('Earlier'),
    _notification('Welcome to OpenMontage', 'Your video studio is ready.'),
  ];
  Widget _notification(String title, String detail) => _card(
    ListTile(
      leading: const CircleAvatar(child: Icon(Icons.notifications_none)),
      title: Text(title),
      subtitle: Text(detail),
      onTap: () => _saved('$title notification opened.'),
    ),
  );

  List<Widget> _help(BuildContext context) => [
    const TextField(
      decoration: InputDecoration(
        hintText: 'Search help...',
        prefixIcon: Icon(Icons.search),
      ),
    ),
    for (final q in [
      'How to create a video',
      'How to edit a video',
      'Managing projects',
      'Managing assets',
    ])
      _card(
        ExpansionTile(
          title: Text(q),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Open the relevant workspace from the bottom navigation. Some tools are marked Coming Soon while their engines are prepared.',
              ),
            ),
          ],
        ),
      ),
    _section('Contact'),
    _card(
      ListTile(
        title: const Text('Contact Support'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showComingSoon(context, 'Contact Support'),
      ),
    ),
    _card(
      ListTile(
        title: const Text('Report a Problem'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showComingSoon(context, 'Problem reports'),
      ),
    ),
  ];

  List<Widget> _about(BuildContext context) => [
    const SizedBox(height: 24),
    const Center(
      child: CircleAvatar(
        radius: 38,
        child: Icon(Icons.play_arrow_rounded, size: 48),
      ),
    ),
    const SizedBox(height: 12),
    const Center(
      child: Text(
        'OpenMontage',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    ),
    const Center(child: Text('AI Video Production Studio')),
    const SizedBox(height: 10),
    const Center(child: Text('Version 1.0.0')),
    const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Built for AI-powered video production.'),
    ),
    for (final label in ['Terms', 'Privacy', 'Open Source Licenses'])
      _card(
        ListTile(
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showComingSoon(context, label),
        ),
      ),
  ];
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
