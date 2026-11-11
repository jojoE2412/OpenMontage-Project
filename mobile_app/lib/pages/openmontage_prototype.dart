import 'package:flutter/material.dart';

const _ink = Color(0xFF17233B);
const _muted = Color(0xFF718097);
const _line = Color(0xFFE3EAF4);
const _paper = Color(0xFFF4F7FC);
const _blue = Color(0xFF5963E8);

class OpenMontagePrototype extends StatefulWidget {
  const OpenMontagePrototype({super.key});

  @override
  State<OpenMontagePrototype> createState() => _OpenMontagePrototypeState();
}

class _OpenMontagePrototypeState extends State<OpenMontagePrototype> {
  int _tab = 0;
  String _screen = 'Splash';
  String _selectedFeature = 'AI Video Generation';
  bool _signedIn = false;

  static const features = <_Feature>[
    _Feature(
      'AI Video Generation',
      'Turn ideas into polished videos.',
      Icons.movie_creation_outlined,
      Color(0xFF5963E8),
    ),
    _Feature(
      'Real Footage Editing',
      'Find and shape the right footage.',
      Icons.video_library_outlined,
      Color(0xFF20A69A),
    ),
    _Feature(
      'Video Editing',
      'Trim, arrange, and refine clips.',
      Icons.video_settings_outlined,
      Color(0xFFE46870),
    ),
    _Feature(
      'Audio & Music',
      'Music, voice, and sound effects.',
      Icons.music_note_outlined,
      Color(0xFF8D63D9),
    ),
    _Feature(
      'Subtitle & Caption',
      'Create accessible captions.',
      Icons.subtitles_outlined,
      Color(0xFF4389D5),
    ),
    _Feature(
      'Image Generation',
      'Create images for your story.',
      Icons.image_outlined,
      Color(0xFF2E9B89),
    ),
    _Feature(
      'Avatar & Talking Head',
      'Build presenter-led videos.',
      Icons.face_retouching_natural,
      Color(0xFF9B68C8),
    ),
    _Feature(
      'Localization & Dubbing',
      'Adapt videos for new audiences.',
      Icons.translate,
      Color(0xFF4184C7),
    ),
    _Feature(
      'Shorts / Clip Generator',
      'Turn long videos into shorts.',
      Icons.smart_display_outlined,
      Color(0xFFE1764D),
    ),
    _Feature(
      'Screen Demo',
      'Record a clear product walkthrough.',
      Icons.desktop_windows_outlined,
      Color(0xFF4E83CE),
    ),
    _Feature(
      'Animation & Motion Graphics',
      'Add movement and visual style.',
      Icons.auto_awesome_motion_outlined,
      Color(0xFF9A61C7),
    ),
    _Feature(
      '3D World & Hybrid',
      'Explore experimental 3D scenes.',
      Icons.view_in_ar_outlined,
      Color(0xFF6681A7),
    ),
    _Feature(
      'Video Enhancement',
      'Improve clarity and color.',
      Icons.hd_outlined,
      Color(0xFF32A18D),
    ),
    _Feature(
      'Analysis & Transcription',
      'Understand and transcribe video.',
      Icons.analytics_outlined,
      Color(0xFF5684CF),
    ),
  ];

  void _openFeature(String title) {
    setState(() {
      _selectedFeature = title;
      _screen = title;
      _tab = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenMontage',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -.45,
          ),
          titleLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
          titleMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
          bodyMedium: TextStyle(fontSize: 12, color: _muted, height: 1.4),
          bodySmall: TextStyle(fontSize: 10, color: _muted, height: 1.35),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _line),
          ),
        ),
      ),
      home: _signedIn ? _appShell() : _auth(),
    );
  }

  Widget _auth() => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: 34),
                Text(
                  _screen == 'Register'
                      ? 'Create Your Account'
                      : _screen == 'Verify'
                      ? 'Check your email'
                      : _screen == 'Splash'
                      ? 'Create. Edit. Inspire.'
                      : 'Welcome Back 👋',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 7),
                Text(
                  _screen == 'Verify'
                      ? 'We sent a verification link to your email.'
                      : 'Your video studio, all in one place.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_screen == 'Register')
                  const _Field(
                    label: 'Full Name',
                    hint: 'Jane Doe',
                    icon: Icons.person_outline,
                  ),
                if (_screen != 'Splash' && _screen != 'Verify') ...[
                  const _Field(
                    label: 'Email or Phone',
                    hint: 'you@email.com',
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 14),
                  const _Field(
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                ],
                if (_screen == 'Verify')
                  const _InfoCard(
                    icon: Icons.mark_email_read_outlined,
                    title: 'Verify your email',
                    detail: 'Open the link in your inbox to finish setting up your account.',
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => setState(() {
                    if (_screen == 'Splash') {
                      _screen = 'Login';
                    } else if (_screen == 'Register') {
                      _screen = 'Verify';
                    } else if (_screen == 'Verify') {
                      _screen = 'Login';
                    } else {
                      _signedIn = true;
                      _screen = 'Home';
                    }
                  }),
                  child: Text(
                    _screen == 'Splash'
                        ? 'Get Started'
                        : _screen == 'Register'
                        ? 'Sign Up'
                        : _screen == 'Verify'
                        ? 'Resend Email'
                        : 'Login',
                  ),
                ),
                if (_screen != 'Splash' && _screen != 'Verify') ...[
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'or continue with',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _signedIn = true;
                      _screen = 'Home';
                    }),
                    icon: const Icon(Icons.g_mobiledata, size: 24),
                    label: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(
                        () => _screen = _screen == 'Register'
                            ? 'Login'
                            : 'Register',
                      ),
                      child: Text(
                        _screen == 'Register'
                            ? 'Already have an account? Login'
                            : "Don't have an account? Sign Up",
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _appShell() => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      titleSpacing: 16,
      title: const _Brand(compact: true),
      actions: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFE3E8FF),
            child: Text(
              'JD',
              style: TextStyle(
                color: _blue,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ),
    drawer: _drawer(),
    body: _screen == 'Home'
        ? _home()
        : _screen == 'Create'
        ? _create()
        : _screen == 'Projects'
        ? _projects()
        : _screen == 'Settings'
        ? _settings()
        : _featurePage(),
    bottomNavigationBar: NavigationBar(
      height: 64,
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() {
        _tab = i;
        _screen = ['Home', 'Projects', 'Create', 'Library', 'Settings'][i];
      }),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: 'Projects',
        ),
        NavigationDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle),
          label: 'Create',
        ),
        NavigationDestination(
          icon: Icon(Icons.video_library_outlined),
          selectedIcon: Icon(Icons.video_library),
          label: 'Library',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    ),
  );

  Widget _drawer() => Drawer(
    child: SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF17243D),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Color(0xFF4359B8),
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
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          ...[
            'Home',
            'My Projects',
            'Templates',
            'AI Provider',
            'Local AI Settings',
            'Storage',
            'Settings',
            'Help & Support',
          ].map(
            (x) => ListTile(
              dense: true,
              leading: Icon(_drawerIcon(x), size: 19),
              title: Text(x, style: const TextStyle(fontSize: 13)),
              onTap: () => setState(() {
                _screen = x == 'My Projects' ? 'Projects' : x;
                _tab = x == 'Home'
                    ? 0
                    : x == 'My Projects'
                    ? 1
                    : 4;
                Navigator.pop(context);
              }),
            ),
          ),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log Out'),
            onTap: () => setState(() {
              _signedIn = false;
              _screen = 'Login';
              Navigator.pop(context);
            }),
          ),
        ],
      ),
    ),
  );

  IconData _drawerIcon(String x) => switch (x) {
    'Home' => Icons.home_outlined,
    'My Projects' => Icons.folder_outlined,
    'Templates' => Icons.dashboard_outlined,
    'AI Provider' => Icons.hub_outlined,
    'Local AI Settings' => Icons.memory_outlined,
    'Storage' => Icons.storage_outlined,
    'Settings' => Icons.settings_outlined,
    _ => Icons.help_outline,
  };

  Widget _home() => ListView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
    children: [
      Text(
        'Good morning, Creator 👋',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 5),
      const Text('What would you like to create today?'),
      const SizedBox(height: 18),
      const _Search(),
      const SizedBox(height: 22),
      _section(
        'Quick Create',
        action: 'See all',
        onAction: () => setState(() {
          _screen = 'Create';
          _tab = 2;
        }),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _quick(
              'AI Video',
              Icons.movie_creation_outlined,
              _blue,
              () => _openFeature('AI Video Generation'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _quick(
              'Edit Video',
              Icons.video_settings_outlined,
              const Color(0xFF269D91),
              () => _openFeature('Video Editing'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _quick(
              'Shorts',
              Icons.smart_display_outlined,
              const Color(0xFFE27C50),
              () => _openFeature('Shorts / Clip Generator'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      _section(
        'Popular Features',
        action: 'View all',
        onAction: () => setState(() {
          _screen = 'Create';
          _tab = 2;
        }),
      ),
      const SizedBox(height: 10),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 2.35,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        children: features.take(6).map((f) => _featureTile(f)).toList(),
      ),
      const SizedBox(height: 22),
      _section(
        'Recent Projects',
        action: 'See all',
        onAction: () => setState(() {
          _screen = 'Projects';
          _tab = 1;
        }),
      ),
      const SizedBox(height: 10),
      _project(
        'Sunrise in Bali',
        'Cinematic · 15s',
        'Edited 2 min ago',
        Icons.landscape_outlined,
      ),
      const SizedBox(height: 8),
      _project(
        'City Motion',
        'Minimal · 30s',
        'Edited yesterday',
        Icons.location_city_outlined,
      ),
    ],
  );

  Widget _create() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(
        'Create New Project',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 5),
      const Text('Choose a feature to get started.'),
      const SizedBox(height: 16),
      const _Search(hint: 'Search features...'),
      const SizedBox(height: 16),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: features.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.24,
        ),
        itemBuilder: (context, i) => _featureCard(features[i]),
      ),
    ],
  );

  Widget _featurePage() {
    final feature = features.firstWhere(
      (f) => f.title == _selectedFeature,
      orElse: () => features.first,
    );
    final isVideo = feature.title == 'Video Editing';
    final isFootage = feature.title == 'Real Footage Editing';
    final isAudio = feature.title == 'Audio & Music';
    final children = <Widget>[
      Row(
        children: [
          IconButton(
            onPressed: () => setState(() {
              _screen = 'Create';
              _tab = 2;
            }),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              feature.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
      Text(feature.detail),
      const SizedBox(height: 15),
    ];
    if (isFootage) {
      children.addAll([
        _tabs(['Stock', 'Local', 'Internet']),
        const SizedBox(height: 12),
        const _Search(hint: 'Search footage...'),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.2,
          crossAxisSpacing: 9,
          mainAxisSpacing: 9,
          children: const [
            _Thumbnail(title: 'Ocean sunset'),
            _Thumbnail(title: 'Mountain road'),
            _Thumbnail(title: 'City lights'),
            _Thumbnail(title: 'Forest walk'),
          ],
        ),
      ]);
    } else if (isAudio) {
      children.addAll([
        _tabs(['Music', 'Voice', 'SFX']),
        const SizedBox(height: 12),
        const _Search(hint: 'Search audio...'),
        const SizedBox(height: 10),
        ...[
          'Ambient Piano',
          'Warm Documentary',
          'Bright Horizon',
          'Soft Pulse',
        ].map(_track),
      ]);
    } else if (isVideo) {
      children.addAll([
        const _Preview(),
        const SizedBox(height: 12),
        const Text('Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          height: 70,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: List.generate(
              5,
              (i) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: [
                      const Color(0xFF9EB5D5),
                      const Color(0xFF84A6C8),
                      const Color(0xFFE8A178),
                      const Color(0xFF92B1A6),
                      const Color(0xFF9C9BCC),
                    ][i],
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            'Trim',
            'Cut',
            'Speed',
            'Filters',
          ].map((x) => ActionChip(label: Text(x), onPressed: () {})).toList(),
        ),
      ]);
    } else {
      children.addAll([
        _tabs(['Text to Video', 'Image to Video', 'Template']),
        const SizedBox(height: 14),
        const _Field(
          label: 'Describe your video',
          hint: 'A cinematic sunrise over the ocean...',
          icon: Icons.edit_note,
          lines: 4,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: 'LTX Video (External)',
          decoration: const InputDecoration(
            labelText: 'Model',
            border: OutlineInputBorder(),
          ),
          items: const [
            'LTX Video (External)',
            'Draft Mode (Experimental)',
          ].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
          onChanged: (_) {},
        ),
        const SizedBox(height: 12),
        _fieldSelect('Duration', '5 seconds'),
        _fieldSelect('Aspect ratio', '16:9'),
        const SizedBox(height: 10),
        const _InfoCard(
          icon: Icons.tune,
          title: 'Advanced Settings',
          detail: 'Resolution, style, and seed',
        ),
        const SizedBox(height: 12),
        const _InfoCard(
          icon: Icons.payments_outlined,
          title: 'Estimated cost',
          detail: 'Preview available when a provider is connected.',
        ),
      ]);
    }
    children.addAll([
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project added to your mock queue')),
        ),
        icon: const Icon(Icons.auto_awesome),
        label: Text(
          isFootage
              ? 'Use Selected Footage'
              : isAudio
              ? 'Add to Project'
              : 'Generate',
        ),
      ),
    ]);
    return ListView(padding: const EdgeInsets.all(18), children: children);
  }

  Widget _projects() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('My Projects', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const _Search(hint: 'Search projects...'),
      const SizedBox(height: 14),
      _project(
        'Sunrise in Bali',
        'Cinematic · 15s',
        'Completed',
        Icons.landscape_outlined,
      ),
      const SizedBox(height: 9),
      _project(
        'City Motion',
        'Minimal · 30s',
        'In progress',
        Icons.location_city_outlined,
      ),
      const SizedBox(height: 9),
      _project(
        'Product Story',
        'Podcast to Video',
        'Draft',
        Icons.mic_none_outlined,
      ),
    ],
  );

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      ...{
        'Account': [
          'Profile Information',
          'Change Password',
          'Linked Accounts',
        ],
        'App Settings': ['Language', 'Theme', 'Notifications'],
        'AI Provider': ['Manage Providers', 'Default Model', 'Budget'],
        'Storage': ['Manage Storage'],
        'Support': ['Help & Support', 'About OpenMontage'],
      }.entries.map(
        (section) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 7),
              child: Text(
                section.key,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _muted,
                ),
              ),
            ),
            Card(
              child: Column(
                children: section.value
                    .map(
                      (label) => ListTile(
                        dense: true,
                        title: Text(
                          label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () {},
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _section(String title, {String? action, VoidCallback? onAction}) =>
      Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action, style: const TextStyle(fontSize: 11)),
            ),
        ],
      );
  Widget _quick(String title, IconData icon, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 78,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
  Widget _featureTile(_Feature f) => InkWell(
    onTap: () => _openFeature(f.title),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(f.icon, color: f.color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
                Text(
                  f.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _featureCard(_Feature f) => InkWell(
    onTap: () => _openFeature(f.title),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: f.color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(f.icon, color: f.color, size: 18),
            ),
            const Spacer(),
            Text(
              f.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              f.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _project(String title, String meta, String status, IconData icon) =>
      Card(
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEFA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _blue),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          subtitle: Text(
            '$meta · $status',
            style: const TextStyle(fontSize: 10),
          ),
          trailing: const Icon(Icons.more_horiz),
        ),
      );
  Widget _tabs(List<String> labels) => Wrap(
    spacing: 8,
    children: labels
        .map(
          (x) => ChoiceChip(
            label: Text(x),
            selected: x == labels.first,
            onSelected: (_) {},
          ),
        )
        .toList(),
  );
  Widget _fieldSelect(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: {
        value,
        '10 seconds',
        '30 seconds',
      }.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
      onChanged: (_) {},
    ),
  );
  Widget _track(String title) => Card(
    child: ListTile(
      leading: const Icon(Icons.play_circle_outline, color: _blue),
      title: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      subtitle: const Text(
        'Audio Library · Instrumental',
        style: TextStyle(fontSize: 10),
      ),
      trailing: const Text('02:45', style: TextStyle(fontSize: 10)),
    ),
  );
}

class _Feature {
  const _Feature(this.title, this.detail, this.icon, this.color);
  final String title, detail;
  final IconData icon;
  final Color color;
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 30 : 46,
        height: compact ? 30 : 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4563E8), Color(0xFF37B9D1)],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 25,
        ),
      ),
      const SizedBox(width: 9),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenMontage',
            style: TextStyle(
              color: _ink,
              fontSize: compact ? 16 : 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!compact)
            const Text(
              'AI Video Studio · Mobile App',
              style: TextStyle(fontSize: 10, color: _muted),
            ),
        ],
      ),
    ],
  );
}

class _Search extends StatelessWidget {
  const _Search({this.hint = 'Search features...'});
  final String hint;
  @override
  Widget build(BuildContext context) => TextField(
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search, size: 19),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.lines = 1,
  });
  final String label, hint;
  final IconData icon;
  final bool obscure;
  final int lines;
  @override
  Widget build(BuildContext context) => TextField(
    obscureText: obscure,
    maxLines: lines,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title, detail;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, color: _blue),
      title: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(detail, style: const TextStyle(fontSize: 10)),
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) => Container(
    height: 190,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7FA5BC), Color(0xFFF2B47B), Color(0xFF324968)],
      ),
    ),
    child: const Center(
      child: Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
    ),
  );
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: const LinearGradient(
        colors: [Color(0xFF8FAFC2), Color(0xFFE6A874), Color(0xFF435878)],
      ),
    ),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Color(0x660B1830),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        ),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ),
  );
}
