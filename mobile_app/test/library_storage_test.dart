import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/library_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('library assets persist reference and project associations', () async {
    await LibraryStorage.saveAsset(
      name: 'source.mp4',
      path: '/tmp/source.mp4',
      type: 'video',
    );
    final asset = (await LibraryStorage.getAssets()).single;
    final id = asset['id'].toString();

    await LibraryStorage.setReference(id, true);
    await LibraryStorage.setProjectAssociations(id, ['project-a', 'project-b']);

    final saved = (await LibraryStorage.getAssets()).single;
    expect(saved['isReference'], isTrue);
    expect(saved['projectIds'], ['project-a', 'project-b']);
  });

  test('backend upload upgrades the matching local asset entry', () async {
    await LibraryStorage.saveAsset(
      name: 'source.mp4',
      path: '/tmp/source.mp4',
      type: 'video',
    );
    final local = (await LibraryStorage.getAssets()).single;

    await LibraryStorage.saveAsset(
      id: 'asset-backend-1',
      name: 'source.mp4',
      path: '/tmp/source.mp4',
      type: 'video',
      backendProjectId: 'project-1',
      remoteUrl: 'http://localhost/api/assets/asset-backend-1/file',
      storage: 'backend',
    );

    final saved = await LibraryStorage.getAssets();
    expect(saved, hasLength(1));
    expect(saved.single['id'], 'asset-backend-1');
    expect(saved.single['backendProjectId'], 'project-1');
    expect(saved.single['storage'], 'backend');
    expect(saved.single['remoteUrl'], isNotEmpty);
    expect(saved.single['createdAt'], local['createdAt']);
  });
}
