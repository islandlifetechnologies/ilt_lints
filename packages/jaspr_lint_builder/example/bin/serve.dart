import 'dart:async';
import 'dart:io';

import 'package:jaspr_lint_builder_example/build.dart';

Future<void> main(List<String> args) async {
  await runExampleServeCli(args);

  final shutdownCompleter = Completer<void>();
  StreamSubscription<ProcessSignal>? sigintSub;
  StreamSubscription<ProcessSignal>? sigtermSub;

  Future<void> handleSignal(ProcessSignal signal) async {
    stdout.writeln('\nReceived $signal, shutting down server...');
    await sigintSub?.cancel();
    await sigtermSub?.cancel();
    shutdownCompleter.complete();
  }

  sigintSub = ProcessSignal.sigint.watch().listen(handleSignal);
  if (!Platform.isWindows) {
    sigtermSub = ProcessSignal.sigterm.watch().listen(handleSignal);
  }

  await shutdownCompleter.future;
  exit(0);
}
