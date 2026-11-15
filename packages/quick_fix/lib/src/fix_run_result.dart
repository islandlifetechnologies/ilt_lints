import 'package:quick_fix/quick_fix.dart';

/// Summary of fixes applied across a [FixRunner.run] invocation.
class const FixRunResult({required final List<FileFixResult> fileResults}) {
  int get totalFilesFixed => fileResults.length;

  int get totalFixes =>
      fileResults.fold(0, (sum, file) => sum + file.totalFixes);
}
