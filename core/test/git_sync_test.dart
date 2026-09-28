import 'dart:io';

import 'package:handles_core/handles_core.dart';
import 'package:test/test.dart';

Future<void> _run(String executable, List<String> args, String workingDirectory) async {
  final result = await Process.run(executable, args, workingDirectory: workingDirectory);
  if (result.exitCode != 0) {
    fail('$executable ${args.join(' ')} failed: ${result.stderr}');
  }
}

void main() {
  group('GitSync', () {
    late Directory tempRoot;
    late Directory remoteDir;
    late Directory workingDir;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('handles-git-sync-test-');
      remoteDir = Directory('${tempRoot.path}/remote.git');
      workingDir = Directory('${tempRoot.path}/working');

      // A real local bare repo as the "remote" - exercises an actual push,
      // not a mock of one.
      await _run('git', ['init', '--bare', remoteDir.path], tempRoot.path);
      await _run('git', ['clone', remoteDir.path, workingDir.path], tempRoot.path);
      await _run('git', ['config', 'user.email', 'test@example.com'], workingDir.path);
      await _run('git', ['config', 'user.name', 'Test'], workingDir.path);

      // A bare repo has no commits yet, so the initial clone has no HEAD -
      // give it one so `git push` has something to push against.
      await File('${workingDir.path}/.gitkeep').writeAsString('');
      await _run('git', ['add', '-A'], workingDir.path);
      await _run('git', ['commit', '-m', 'initial'], workingDir.path);
      await _run('git', ['push'], workingDir.path);
    });

    tearDown(() async {
      await tempRoot.delete(recursive: true);
    });

    test('commits and pushes a real file change', () async {
      await File('${workingDir.path}/item.json').writeAsString('{"sku":"a"}');

      await GitSync(workingDir.path).commitAndPush('add item');

      final log = await Process.run('git', ['log', '--oneline'], workingDirectory: remoteDir.path);
      expect(log.stdout.toString(), contains('add item'));
    });

    test('does not create an empty commit when nothing changed', () async {
      await GitSync(workingDir.path).commitAndPush('should not appear');

      final log = await Process.run('git', ['log', '--oneline'], workingDirectory: remoteDir.path);
      expect(log.stdout.toString(), isNot(contains('should not appear')));
    });

    test('throws GitSyncException with the real git error on failure', () async {
      // Not a git repo at all - every git command in here will fail.
      final notARepo = await Directory.systemTemp.createTemp('handles-not-a-repo-');
      addTearDown(() => notARepo.delete(recursive: true));

      await File('${notARepo.path}/item.json').writeAsString('{}');

      expect(
        () => GitSync(notARepo.path).commitAndPush('x'),
        throwsA(isA<GitSyncException>()),
      );
    });
  });
}
