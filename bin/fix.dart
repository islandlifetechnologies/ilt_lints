import 'dart:io';

import 'package:ilt_lints/src/fix_runner.dart';

Future<void> main(List<String> args) async {
  exitCode = await runFixCli(args);
}
