import 'dart:convert';
import 'dart:io';

/// Commits and pushes changes in a working directory - what makes the
/// catalog repo's commit history a real audit trail (PROJECT_PLAN.md
/// section 2) rather than just a design intention. Shells out to the
/// system `git`, same as a human would, rather than reimplementing git
/// plumbing.
///
/// The daemon's checkout (docker-compose's mounted volume) already has
/// push access configured on the host - SSH key or credential helper set
/// up out of band - so its calls never pass [authToken]. The app's
/// checkout has no such thing (a fresh Windows/Android install), so its
/// calls do: see [_authArgs] for why that's a per-command header rather
/// than anything written to disk.
class GitSync {
  GitSync(this.workingDirectory);

  final String workingDirectory;

  /// Clones [remoteUrl] into [workingDirectory] if it isn't a git checkout
  /// there yet - lets a caller treat "first run on this device" and
  /// "every run after" identically instead of branching on it themselves.
  Future<void> cloneIfMissing(String remoteUrl, {String? authToken}) async {
    if (await Directory('$workingDirectory/.git').exists()) return;

    final parent = Directory(workingDirectory).parent;
    await parent.create(recursive: true);
    await _run(
      [..._authArgs(authToken), 'clone', remoteUrl, workingDirectory],
      workingDirectory: parent.path,
    );
  }

  /// Fast-forward only - this app has no merge-conflict UI, so a history
  /// that can't fast-forward should surface as a clear error rather than
  /// silently attempt a merge.
  Future<void> pull({String? authToken}) async {
    await _run([..._authArgs(authToken), 'pull', '--ff-only']);
  }

  /// Stages everything under [workingDirectory], commits with [message],
  /// and pushes - a no-op (not an error) if there was nothing to commit,
  /// since a reconciliation pass with no changes is the common case, not
  /// an exceptional one.
  Future<void> commitAndPush(String message, {String? authToken}) async {
    await _run(['add', '-A']);

    final status = await _run(['status', '--porcelain']);
    if (status.stdout.toString().trim().isEmpty) {
      return; // nothing changed - not an error, don't create an empty commit
    }

    await _run(['commit', '-m', message]);
    await _run([..._authArgs(authToken), 'push']);
  }

  /// A per-invocation `-c http.extraHeader=...` rather than embedding the
  /// token in the remote URL or running `git remote set-url` - either of
  /// those would land the token in plain text in `.git/config` on disk.
  /// This way it only ever exists in memory and in whatever secure store
  /// the caller read it from.
  List<String> _authArgs(String? authToken) {
    if (authToken == null || authToken.isEmpty) return const [];
    final basic = base64Encode(utf8.encode('x-access-token:$authToken'));
    return ['-c', 'http.extraHeader=Authorization: Basic $basic'];
  }

  Future<ProcessResult> _run(List<String> args, {String? workingDirectory}) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: workingDirectory ?? this.workingDirectory,
    );
    if (result.exitCode != 0) {
      throw GitSyncException(
        'git ${args.join(' ')} failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    return result;
  }
}

class GitSyncException implements Exception {
  GitSyncException(this.message);
  final String message;

  @override
  String toString() => 'GitSyncException: $message';
}
