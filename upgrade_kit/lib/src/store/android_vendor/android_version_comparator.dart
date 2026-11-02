/// Numeric Android version comparison without lexicographical ordering bugs.
final class AndroidVersionComparator {
  const AndroidVersionComparator._();

  static int? compareCodes(String? remote, String? current) {
    final remoteCode = remote == null ? null : BigInt.tryParse(remote.trim());
    final currentCode = current == null
        ? null
        : BigInt.tryParse(current.trim());
    if (remoteCode == null || currentCode == null) {
      return null;
    }
    return remoteCode.compareTo(currentCode);
  }

  static int? compareNames(String remote, String current) {
    final remoteParts = _numericParts(remote);
    final currentParts = _numericParts(current);
    if (remoteParts.isEmpty || currentParts.isEmpty) {
      return null;
    }
    final length = remoteParts.length > currentParts.length
        ? remoteParts.length
        : currentParts.length;
    for (var index = 0; index < length; index += 1) {
      final remotePart = index < remoteParts.length
          ? remoteParts[index]
          : BigInt.zero;
      final currentPart = index < currentParts.length
          ? currentParts[index]
          : BigInt.zero;
      final comparison = remotePart.compareTo(currentPart);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }

  static List<BigInt> _numericParts(String value) => RegExp(
    r'\d+',
  ).allMatches(value).map((match) => BigInt.parse(match.group(0)!)).toList();
}
