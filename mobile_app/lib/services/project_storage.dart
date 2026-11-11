import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ProjectStorage {
  static const String _projectsKey = 'projects';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<List<Map<String, dynamic>>> getProjects() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getStringList(_projectsKey) ?? [];

    return data
        .map((item) => Map<String, dynamic>.from(jsonDecode(item)))
        .toList();
  }

  static Future<Map<String, dynamic>> saveProject({
    String? id,
    String? projectId,
    required String title,
    required String prompt,
    required String style,
    required String duration,
    required int assetCount,
    String status = 'Completed',
    String? videoUrl,
    String? jobId,
    String? aspectRatio,
    String? model,
    String? provider,
    String? mode,
    String? resolution,
    int? fps,
    int? seed,
    String? workflowId,
    String? pipelineId,
    String? templateId,
    Map<String, dynamic>? templateParameters,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final projects = await getProjects();
    final projectKey =
        projectId ?? id ?? DateTime.now().millisecondsSinceEpoch.toString();

    final project = <String, dynamic>{
      'id': projectKey,
      'projectId': projectKey,
      'title': title.trim().isEmpty ? _titleFromPrompt(prompt) : title.trim(),
      'prompt': prompt,
      'style': style,
      'duration': duration,
      'assetCount': assetCount,
      'status': status,
      'videoUrl': videoUrl,
      'jobId': jobId,
      'aspectRatio': aspectRatio ?? '16:9',
      'model': model ?? 'Auto',
      'provider': provider ?? 'auto',
      'mode': mode ?? 'Text to Video',
      'resolution': resolution ?? '720p',
      'fps': fps ?? 24,
      'seed': seed,
      'workflowId': workflowId,
      'pipelineId': pipelineId,
      'templateId': templateId,
      'templateParameters': templateParameters ?? const <String, dynamic>{},
      'createdAt': DateTime.now().toIso8601String(),
    };

    final existingIndex = projects.indexWhere(
      (item) => (item['projectId'] ?? item['id']) == projectKey,
    );
    if (existingIndex >= 0) {
      project['createdAt'] =
          projects[existingIndex]['createdAt'] ?? project['createdAt'];
      projects[existingIndex] = {...projects[existingIndex], ...project};
    } else {
      projects.insert(0, project);
    }

    final data = projects.map((project) => jsonEncode(project)).toList();

    await prefs.setStringList(_projectsKey, data);
    revision.value++;
    return project;
  }

  static Future<void> updateProjectTitle(String id, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) return;

    final projects = await getProjects();
    final index = projects.indexWhere((project) => project['id'] == id);
    if (index == -1) return;

    projects[index]['title'] = normalizedTitle;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_projectsKey, projects.map(jsonEncode).toList());
    revision.value++;
  }

  static String _titleFromPrompt(String prompt) {
    final trimmed = prompt.trim();
    return trimmed.isEmpty ? 'Untitled Video' : trimmed;
  }

  static Future<void> deleteProject(String id) async {
    final prefs = await SharedPreferences.getInstance();

    final projects = await getProjects();

    projects.removeWhere((project) => project['id'] == id);

    final data = projects.map((project) => jsonEncode(project)).toList();

    await prefs.setStringList(_projectsKey, data);
    revision.value++;
  }

  static Future<void> clearProjects() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_projectsKey);
    revision.value++;
  }
}
