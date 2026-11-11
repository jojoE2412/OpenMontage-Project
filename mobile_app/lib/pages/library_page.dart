import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/library_storage.dart';
import '../services/project_storage.dart';
import '../services/backend_api.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.initialCategory});
  final String? initialCategory;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final searchController = TextEditingController();
  List<Map<String, dynamic>> assets = [];
  String category = 'All';
  String query = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    category = widget.initialCategory ?? 'All';
    LibraryStorage.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    LibraryStorage.revision.removeListener(_load);
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await LibraryStorage.getAssets();
    try {
      final projectId = await LibraryStorage.getBackendProjectId();
      if (projectId != null) {
        final remote = await BackendApi.getProjectAssets(projectId);
        final existingIds = saved.map((asset) => asset['id'].toString()).toSet();
        for (final asset in remote) {
          final id = asset['id']?.toString();
          if (id == null || existingIds.contains(id)) continue;
          saved.add({
            ...asset,
            'remoteUrl': BackendApi.resolveApiUrl(asset['file_url'].toString()),
            'backendProjectId': projectId,
            'storage': 'backend',
            'path': '',
          });
        }
      }
    } catch (_) {
      // Keep locally cached items visible while backend access is unavailable.
    }
    if (mounted) {
      setState(() {
        assets = saved;
        loading = false;
      });
    }
  }

  Future<void> _pick(String type) async {
    final extensions = type == 'image'
        ? ['jpg', 'jpeg', 'png', 'webp']
        : type == 'video'
        ? ['mp4', 'mov', 'mkv', 'webm']
        : ['mp3', 'wav', 'm4a', 'aac'];
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (!mounted || files.isEmpty) return;
    var uploaded = 0;
    var localOnly = 0;
    String? projectId;
    try {
      projectId = await LibraryStorage.getBackendProjectId();
      if (projectId == null) {
        final project = await BackendApi.createProject(name: 'OpenMontage Library');
        projectId = project['id']?.toString();
        if (projectId == null || projectId.isEmpty) throw const FormatException('Backend returned no library project ID.');
        await LibraryStorage.setBackendProjectId(projectId);
        await ProjectStorage.saveProject(
          id: projectId,
          projectId: projectId,
          title: 'OpenMontage Library',
          prompt: '', style: 'Library', duration: '0s', assetCount: 0,
          status: 'Active',
        );
      }
    } catch (_) {
      projectId = null;
    }
    for (final file in files) {
      final path = file.path;
      if (projectId != null && path != null) {
        try {
          final remote = await BackendApi.uploadMediaAsset(
            projectId: projectId,
            file: File(path),
          );
          await LibraryStorage.saveAsset(
            id: remote['id']?.toString(),
            name: remote['name']?.toString() ?? file.name,
            path: path,
            type: remote['type']?.toString() ?? type,
            backendProjectId: projectId,
            remoteUrl: BackendApi.resolveApiUrl(remote['file_url'].toString()),
            storage: 'backend',
          );
          uploaded++;
          continue;
        } catch (error) {
          await LibraryStorage.saveAsset(
            name: file.name, path: path, type: type,
            storage: 'local', uploadError: error.toString(),
          );
          localOnly++;
          continue;
        }
      }
      await LibraryStorage.saveAsset(
        name: file.name,
        path: path ?? file.name,
        type: type,
        storage: 'local',
        uploadError: 'OpenMontage backend is not reachable; this asset is only on this device.',
      );
      localOnly++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$uploaded uploaded to OpenMontage${localOnly == 0 ? '.' : '; $localOnly kept on this device only.'}')),
      );
    }
  }

  void _addAsset() => showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add Asset',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            _option(sheet, Icons.image_outlined, 'Add Image', 'image'),
            _option(sheet, Icons.video_file_outlined, 'Add Video', 'video'),
            _option(sheet, Icons.music_note_outlined, 'Add Audio', 'audio'),
          ],
        ),
      ),
    ),
  );

  Widget _option(
    BuildContext sheet,
    IconData icon,
    String label,
    String type,
  ) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(label),
    onTap: () {
      Navigator.pop(sheet);
      _pick(type);
    },
  );

  List<Map<String, dynamic>> get visible => assets.where((asset) {
    final type = asset['type']?.toString() ?? '';
    final matchesCategory =
        category == 'All' ||
        (category == 'Images' && type == 'image') ||
        (category == 'Videos' && type == 'video') ||
        (category == 'Audio' && type == 'audio') ||
        (category == 'References' &&
            (asset['isReference'] == true || type == 'reference')) ||
        (category == 'Other' &&
            !['image', 'video', 'audio', 'reference'].contains(type));
    return matchesCategory &&
        asset['name'].toString().toLowerCase().contains(query.toLowerCase());
  }).toList();

  IconData _icon(String type) => type == 'image'
      ? Icons.image_outlined
      : type == 'video'
      ? Icons.video_file_outlined
      : Icons.music_note_outlined;

  Future<void> _assetOptions(Map<String, dynamic> asset) async {
    final isRemote = asset['storage'] == 'backend' || asset['remoteUrl'] != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Preview'),
              onTap: () => Navigator.pop(context, 'preview'),
            ),
            if (!isRemote) ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Associate with Project'),
              onTap: () => Navigator.pop(context, 'projects'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Asset Details'),
              subtitle: Text(asset['name']?.toString() ?? 'Unnamed asset'),
              onTap: () => Navigator.pop(context, 'details'),
            ),
            if (!isRemote) ListTile(
              leading: Icon(
                asset['isReference'] == true ? Icons.link_off : Icons.link,
              ),
              title: Text(
                asset['isReference'] == true
                    ? 'Remove from References'
                    : 'Add to References',
              ),
              onTap: () => Navigator.pop(context, 'reference'),
            ),
            if (!isRemote) ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (!isRemote) ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final id = asset['id']?.toString();
    if (action == 'preview') {
      await showDialog<void>(
        context: context,
        builder: (_) => AssetPreviewDialog(asset: asset),
      );
    } else if (action == 'projects' && id != null && !isRemote) {
      await _editProjectAssociations(asset);
    } else if (action == 'rename' && id != null && !isRemote) {
      final controller = TextEditingController(
        text: asset['name']?.toString() ?? '',
      );
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename Asset'),
          content: TextField(controller: controller),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name?.isNotEmpty == true) await LibraryStorage.renameAsset(id, name!);
    } else if (action == 'reference' && id != null && !isRemote) {
      await LibraryStorage.setReference(id, asset['isReference'] != true);
    } else if (action == 'delete' && id != null && !isRemote) {
      await LibraryStorage.deleteAsset(id);
    } else if (action == 'details') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(asset['name']?.toString() ?? 'Asset'),
          content: Text('Type: ${asset['type']}\nPath: ${asset['path']}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
    await _load();
  }

  Future<void> _editProjectAssociations(Map<String, dynamic> asset) async {
    final projects = await ProjectStorage.getProjects();
    if (!mounted) return;
    final selected = (asset['projectIds'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Associate with Projects'),
          content: SizedBox(
            width: 420,
            child: projects.isEmpty
                ? const Text('Create a project first to associate this asset.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final project in projects)
                          CheckboxListTile(
                            value: selected.contains(project['id'].toString()),
                            title: Text(
                              project['title']?.toString() ?? 'Project',
                            ),
                            onChanged: (checked) => setDialogState(() {
                              final projectId = project['id'].toString();
                              if (checked == true) {
                                selected.add(projectId);
                              } else {
                                selected.remove(projectId);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final id = asset['id']?.toString();
    if (result != null && id != null) {
      await LibraryStorage.setProjectAssociations(id, result.toList());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Library')),
    floatingActionButton: FloatingActionButton(
      onPressed: _addAsset,
      child: const Icon(Icons.add_rounded),
    ),
    body: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Library',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage your asset library.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: searchController,
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: 'Search assets...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                ['All', 'Videos', 'Images', 'Audio', 'References', 'Other']
                    .map(
                      (item) => ChoiceChip(
                        label: Text(item),
                        selected: category == item,
                        onSelected: (_) => setState(() => category = item),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 14),
          Text(
            '${visible.length} assets',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          size: 54,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No assets yet.',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _addAsset,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add Asset'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: visible.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: .92,
                          ),
                      itemBuilder: (_, index) {
                        final asset = visible[index];
                        final type = asset['type']?.toString() ?? 'file';
                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _assetOptions(asset),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline
                                    .withValues(alpha: 0.18),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _icon(type),
                                        size: 44,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  asset['name']?.toString() ?? 'Unnamed asset',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        type,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                    const Icon(Icons.more_horiz, size: 18),
                                  ],
                                ),
                                if ((asset['projectIds'] as List<dynamic>?)
                                        ?.isNotEmpty ==
                                    true)
                                  Text(
                                    '${(asset['projectIds'] as List<dynamic>).length} linked project(s)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

class AssetPreviewDialog extends StatefulWidget {
  const AssetPreviewDialog({super.key, required this.asset});
  final Map<String, dynamic> asset;

  @override
  State<AssetPreviewDialog> createState() => _AssetPreviewDialogState();
}

class _AssetPreviewDialogState extends State<AssetPreviewDialog> {
  VideoPlayerController? _controller;
  Object? _error;

  String get _type => widget.asset['type']?.toString() ?? 'other';
  String get _path => widget.asset['path']?.toString() ?? '';
  String? get _remoteUrl => widget.asset['remoteUrl']?.toString();

  @override
  void initState() {
    super.initState();
    if (_type == 'video' || _type == 'audio') {
      _controller = (_remoteUrl != null && _remoteUrl!.isNotEmpty
          ? VideoPlayerController.networkUrl(Uri.parse(_remoteUrl!))
          : VideoPlayerController.file(File(_path)))
        ..initialize()
            .then((_) {
              if (mounted) setState(() {});
            })
            .catchError((Object error) {
              if (mounted) setState(() => _error = error);
            });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.asset['name']?.toString() ?? 'Asset Preview',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    content: SizedBox(width: 520, child: _previewBody(context)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  Widget _previewBody(BuildContext context) {
    if (_type == 'image') {
      return _remoteUrl != null && _remoteUrl!.isNotEmpty
          ? Image.network(
        _remoteUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _unavailable(context),
      )
          : Image.file(
              File(_path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _unavailable(context),
            );
    }
    if (_error != null) return _unavailable(context);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_type == 'video')
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          )
        else
          const Icon(Icons.graphic_eq, size: 90),
        VideoProgressIndicator(controller, allowScrubbing: true),
        IconButton(
          onPressed: () => setState(() {
            controller.value.isPlaying ? controller.pause() : controller.play();
          }),
          icon: Icon(
            controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
        ),
      ],
    );
  }

  Widget _unavailable(BuildContext context) => SizedBox(
    height: 220,
    child: Center(
      child: Text(
        'Preview is unavailable for this file on this device.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}
