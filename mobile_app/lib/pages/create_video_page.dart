import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/backend_api.dart';
import '../services/library_storage.dart';
import 'processing_page.dart';

class CreateVideoPage extends StatefulWidget {
  const CreateVideoPage({super.key});

  @override
  State<CreateVideoPage> createState() => _CreateVideoPageState();
}

class _CreateVideoPageState extends State<CreateVideoPage> {
  String selectedStyle = 'Cinematic';
  String selectedDuration = '30s';

  final TextEditingController promptController = TextEditingController();
  final TextEditingController titleController = TextEditingController();

  final List<String> styles = [
    'Cinematic',
    'Documentary',
    'Anime',
    'Realistic',
    'Minimal',
  ];

  // Pilihan durasi video
  final List<String> durations = ['15s', '30s', '60s', '90s', '120s'];

  final List<Map<String, String?>> selectedAssets = [];

  @override
  void dispose() {
    promptController.dispose();
    titleController.dispose();
    super.dispose();
  }

  Future<void> _pickAsset({required String type}) async {
    List<String> allowedExtensions;

    switch (type) {
      case 'Image':
        allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];
        break;

      case 'Video':
        allowedExtensions = ['mp4', 'mov', 'mkv', 'webm'];
        break;

      case 'Audio':
        allowedExtensions = ['mp3', 'wav', 'm4a', 'aac'];
        break;

      default:
        allowedExtensions = [];
    }

    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );

    if (!mounted || files.isEmpty) {
      return;
    }

    setState(() {
      selectedAssets.addAll(
        files.map(
          (file) => {
            'name': file.name,
            'path': file.path,
            'extension': file.extension,
          },
        ),
      );
    });

    for (final file in files) {
      await LibraryStorage.saveAsset(
        name: file.name,
        path: file.path ?? file.name,
        type: type.toLowerCase(),
      );
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${files.length} $type asset berhasil ditambahkan.'),
      ),
    );
  }

  void _showAddAssetOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Asset',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose an asset from your device.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _assetOption(
                  icon: Icons.image_outlined,
                  title: 'Image',
                  subtitle: 'Add photos or images',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAsset(type: 'Image');
                  },
                ),
                _assetOption(
                  icon: Icons.video_library_outlined,
                  title: 'Video',
                  subtitle: 'Add video footage',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAsset(type: 'Video');
                  },
                ),
                _assetOption(
                  icon: Icons.music_note_outlined,
                  title: 'Audio',
                  subtitle: 'Add music or audio',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAsset(type: 'Audio');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _assetOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _showLibraryAssets() async {
    final libraryAssets = await LibraryStorage.getAssets();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose from Library',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Select an asset from your library.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (libraryAssets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No assets yet. Add one from your device.'),
                  ),
                ...libraryAssets.map(
                  (asset) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        _getAssetIconFromType(asset['type']?.toString()),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      asset['name']?.toString() ?? 'Unnamed asset',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(asset['type']?.toString() ?? 'file'),
                    trailing: const Icon(Icons.add),
                    onTap: () {
                      final path = asset['path']?.toString();
                      final alreadySelected = selectedAssets.any(
                        (selected) => selected['path'] == path && path != null,
                      );
                      if (!alreadySelected) {
                        setState(() {
                          selectedAssets.add({
                            'name':
                                asset['name']?.toString() ?? 'Unnamed asset',
                            'path': path,
                            'extension': asset['name']
                                ?.toString()
                                .split('.')
                                .last,
                          });
                        });
                      }
                      Navigator.pop(context);

                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${asset['name']} selected from Library.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getAssetIconFromType(String? type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.video_library;
      case 'audio':
        return Icons.music_note;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _removeAsset(int index) {
    setState(() {
      selectedAssets.removeAt(index);
    });
  }

  IconData _getAssetIcon(String? extension) {
    final ext = extension?.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      return Icons.image;
    }

    if (['mp4', 'mov', 'mkv', 'webm'].contains(ext)) {
      return Icons.video_library;
    }

    if (['mp3', 'wav', 'm4a', 'aac'].contains(ext)) {
      return Icons.music_note;
    }

    return Icons.insert_drive_file;
  }

  String _getAssetType(String? extension) {
    final ext = extension?.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      return 'Image';
    }

    if (['mp4', 'mov', 'mkv', 'webm'].contains(ext)) {
      return 'Video';
    }

    if (['mp3', 'wav', 'm4a', 'aac'].contains(ext)) {
      return 'Audio';
    }

    return 'File';
  }

  Future<void> _generateVideo() async {
    final title = titleController.text.trim();
    final prompt = promptController.text.trim();

    if (prompt.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prompt cannot be empty before generating a video.'),
        ),
      );
      return;
    }

    try {
      final response = await BackendApi.createVideo(
        title: title.isEmpty ? 'Untitled OpenMontage video' : title,
        prompt: prompt,
        style: selectedStyle,
        duration: selectedDuration,
      );

      final jobId = response['job_id']?.toString();
      final projectId = response['project_id']?.toString();

      if (jobId == null || projectId == null) {
        throw const FormatException(
          'Backend did not return a valid job payload',
        );
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProcessingPage(
            jobId: jobId,
            projectId: projectId,
            title: title.isEmpty ? 'Untitled OpenMontage video' : title,
            prompt: prompt,
            style: selectedStyle,
            duration: selectedDuration,
            assetCount: selectedAssets.length,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst('Exception: ', '')
                .replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Video')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create with AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Describe the video you want to create.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            Text(
              'Project Title',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                hintText: 'Example: Japan Holiday 2026',
                prefixIcon: const Icon(Icons.title_rounded),
              ),
            ),
            const SizedBox(height: 22),
            Text('Prompt', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: promptController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Describe your video...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Assets', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${selectedAssets.length} selected',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (selectedAssets.isNotEmpty)
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: selectedAssets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final asset = selectedAssets[index];

                    return Container(
                      width: 170,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _getAssetIcon(asset['extension']),
                                color: Theme.of(context).colorScheme.primary,
                                size: 30,
                              ),
                              const Spacer(),
                              Text(
                                asset['name'] ?? 'Unnamed asset',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _getAssetType(asset['extension']),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          Positioned(
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _removeAsset(index),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showAddAssetOptions,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Asset'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showLibraryAssets,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Library'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('AI Model', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline
                      .withValues(alpha: 0.2),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: 'LTX-Video',
                  items: const [
                    DropdownMenuItem(
                      value: 'LTX-Video',
                      child: Text('LTX-Video'),
                    ),
                    DropdownMenuItem(value: 'Wan 2.2', child: Text('Wan 2.2')),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Style', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: styles.map((style) {
                final isSelected = selectedStyle == style;

                return ChoiceChip(
                  label: Text(style),
                  selected: isSelected,
                  onSelected: (_) => setState(() => selectedStyle = style),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text('Duration', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: durations.map((duration) {
                final isSelected = selectedDuration == duration;

                return ChoiceChip(
                  label: Text(duration),
                  selected: isSelected,
                  onSelected: (_) =>
                      setState(() => selectedDuration = duration),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Advanced Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline
                      .withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: const [
                  _AdvancedRow(label: 'Resolution', value: '720p'),
                  SizedBox(height: 12),
                  _AdvancedRow(label: 'FPS', value: '24'),
                  SizedBox(height: 12),
                  _AdvancedRow(label: 'Aspect Ratio', value: '16:9'),
                  SizedBox(height: 12),
                  _AdvancedRow(label: 'Negative Prompt', value: 'None'),
                  SizedBox(height: 12),
                  _AdvancedRow(label: 'Seed', value: 'Random'),
                ],
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generateVideo,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Generate Video'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedRow extends StatelessWidget {
  final String label;
  final String value;

  const _AdvancedRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
