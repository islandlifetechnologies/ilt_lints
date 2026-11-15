/// Summary of fixes applied to a single file.
class const FileFixResult({
  required final String filePath,
  required final Map<String, int> fixesByRule,
}) {
  int get totalFixes => fixesByRule.values.fold(0, (sum, count) => sum + count);
}
