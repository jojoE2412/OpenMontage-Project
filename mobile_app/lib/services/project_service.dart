class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.title,
    required this.prompt,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String prompt;
  final String status;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'prompt': prompt,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ProjectRecord.fromMap(Map<String, dynamic> map) {
    return ProjectRecord(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Untitled Project',
      prompt: map['prompt']?.toString() ?? '',
      status: map['status']?.toString() ?? 'draft',
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ProjectService {
  const ProjectService();

  static const bool isConfigured = false;

  Future<List<ProjectRecord>> fetchUserProjects(String userId) async {
    return const [];
  }

  Future<void> createProject(ProjectRecord project) async {}

  Future<void> updateProject(ProjectRecord project) async {}

  Future<void> deleteProject(String projectId) async {}
}
