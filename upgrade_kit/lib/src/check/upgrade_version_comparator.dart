import 'upgrade_models.dart';

/// Positive means remote is newer; zero means equal; negative means older.
/// Return null when the versions cannot be compared.
typedef UpgradeVersionComparator =
    int? Function(UpgradeVersion remote, UpgradeVersion current);

/// Prefers numeric build numbers when both are present, otherwise uses SemVer.
/// Invalid values return null rather than a false no-update result.
int? compareUpgradeVersions(UpgradeVersion remote, UpgradeVersion current) {
  if (remote.buildNumber != null && current.buildNumber != null) {
    final remoteCode = _buildNumber(remote.buildNumber!);
    final currentCode = _buildNumber(current.buildNumber!);
    if (remoteCode == null || currentCode == null) return null;
    return remoteCode.compareTo(currentCode);
  }
  final remoteVersion = _SemanticVersion.parse(remote.versionName);
  final currentVersion = _SemanticVersion.parse(current.versionName);
  if (remoteVersion == null || currentVersion == null) return null;
  return remoteVersion.compareTo(currentVersion);
}

BigInt? _buildNumber(String value) {
  if (!_matchesEntirely(RegExp(r'[0-9]+'), value)) return null;
  return BigInt.tryParse(value);
}

bool _matchesEntirely(RegExp pattern, String value) {
  final match = pattern.matchAsPrefix(value);
  return match != null && match.end == value.length;
}

final class _SemanticVersion {
  _SemanticVersion(this.core, this.preRelease);

  static final _pattern = RegExp(
    r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?',
  );
  static final _numeric = RegExp(r'[0-9]+');

  final List<BigInt> core;
  final List<String> preRelease;

  static _SemanticVersion? parse(String value) {
    final match = _pattern.matchAsPrefix(value);
    if (match == null || match.end != value.length) return null;
    final preRelease = match.group(4)?.split('.') ?? <String>[];
    for (final identifier in preRelease) {
      if (_matchesEntirely(_numeric, identifier) &&
          identifier.length > 1 &&
          identifier.startsWith('0')) {
        return null;
      }
    }
    return _SemanticVersion([
      for (var index = 1; index <= 3; index++)
        BigInt.parse(match.group(index)!),
    ], preRelease);
  }

  int compareTo(_SemanticVersion other) {
    for (var index = 0; index < core.length; index++) {
      final comparison = core[index].compareTo(other.core[index]);
      if (comparison != 0) return comparison;
    }
    if (preRelease.isEmpty || other.preRelease.isEmpty) {
      if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
      return preRelease.isEmpty ? 1 : -1;
    }
    final length = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < length; index++) {
      final left = preRelease[index];
      final right = other.preRelease[index];
      final leftNumeric = _matchesEntirely(_numeric, left);
      final rightNumeric = _matchesEntirely(_numeric, right);
      final int comparison;
      if (leftNumeric && rightNumeric) {
        comparison = BigInt.parse(left).compareTo(BigInt.parse(right));
      } else if (leftNumeric != rightNumeric) {
        comparison = leftNumeric ? -1 : 1;
      } else {
        comparison = left.compareTo(right);
      }
      if (comparison != 0) return comparison;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }
}
