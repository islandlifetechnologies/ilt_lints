import 'dart:io';

import 'package:jaspr_lint_builder/jaspr_lint_builder.dart';

Future<void> main(List<String> args) async {
  exitCode = await runJasprLintBuilderCli(args);
}
