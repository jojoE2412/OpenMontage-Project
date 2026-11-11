import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LibraryStorage {
  static const String _assetsKey = 'my_library_assets';
  static const String _backendProjectKey = 'openmontage_library_project_id';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<List<Map<String, dynamic>>> getAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_assetsKey) ?? [];
    return data
        .map((item) => Map<String, dynamic>.from(jsonDecode(item)))
        .toList();
  }

  static Future<void> saveAsset({
    required String name,
    required String path,
    required String type,
    bool isReference = false,
    String? id,
    String? backendProjectId,
    String? remoteUrl,
    String? storage,
    String? uploadError,
  }) async {
    final assets = await getAssets();
    final existingById = id == null
        ? -1
        : assets.indexWhere((asset) => asset['id'] == id);
    final existingByPath = path.isEmpty
        ? -1
        : assets.indexWhere((asset) => asset['path'] == path);
    final existingIndex = existingById >= 0 ? existingById : existingByPath;
    final value = <String, dynamic>{
      'id': id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name,
      'path': path,
      'type': type,
      'isReference': isReference,
      'createdAt': existingIndex >= 0
          ? assets[existingIndex]['createdAt']
          : DateTime.now().toIso8601String(),
      ...?(backendProjectId == null
          ? null
          : {'backendProjectId': backendProjectId}),
      ...?(remoteUrl == null ? null : {'remoteUrl': remoteUrl}),
      ...?(storage == null ? null : {'storage': storage}),
      ...?(uploadError == null ? null : {'uploadError': uploadError}),
    };
    if (existingIndex >= 0) {
      assets[existingIndex] = {...assets[existingIndex], ...value};
    } else {
      assets.insert(0, value);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_assetsKey, assets.map(jsonEncode).toList());
    revision.value++;
  }

  static Future<String?> getBackendProjectId() async =>
      (await SharedPreferences.getInstance()).getString(_backendProjectKey);

  static Future<void> setBackendProjectId(String id) async =>
      (await SharedPreferences.getInstance()).setString(_backendProjectKey, id);

  static Future<void> upsertRemoteAsset({
    required String id,
    required String name,
    required String type,
    required String projectId,
    required String remoteUrl,
    String? mimeType,
  }) async {
    final assets = await getAssets();
    final index = assets.indexWhere((asset) => asset['id'] == id);
    final value = <String, dynamic>{
      'id': id,
      'name': name,
      'path': '',
      'type': type,
      'backendProjectId': projectId,
      'remoteUrl': remoteUrl,
      'mimeType': mimeType,
      'storage': 'backend',
      'createdAt': index >= 0
          ? assets[index]['createdAt']
          : DateTime.now().toIso8601String(),
    };
    if (index < 0) {
      assets.insert(0, value);
    } else {
      assets[index] = {...assets[index], ...value};
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_assetsKey, assets.map(jsonEncode).toList());
    revision.value++;
  }

  static Future<void> setReference(String id, bool isReference) async {
    final assets = await getAssets();
    final index = assets.indexWhere((asset) => asset['id'] == id);
    if (index < 0) return;
    assets[index]['isReference'] = isReference;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_assetsKey, assets.map(jsonEncode).toList());
    revision.value++;
  }

  static Future<void> setProjectAssociations(
    String id,
    List<String> projectIds,
  ) async {
    final assets = await getAssets();
    final index = assets.indexWhere((asset) => asset['id'] == id);
    if (index < 0) return;
    assets[index]['projectIds'] = projectIds.toSet().toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_assetsKey, assets.map(jsonEncode).toList());
    revision.value++;
  }

  static Future<void> renameAsset(String id, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    final assets = await getAssets();
    final index = assets.indexWhere((asset) => asset['id'] == id);
    if (index < 0) return;
    assets[index]['name'] = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_assetsKey, assets.map(jsonEncode).toList());
    revision.value++;
  }

  static Future<void> deleteAsset(String id) async {
    final assets = await getAssets();
    assets.removeWhere((asset) => asset['id'] == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_assetsKey, assets.map(jsonEncode).toList());
    revision.value++;
  }
}
