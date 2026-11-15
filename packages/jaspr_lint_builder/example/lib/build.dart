import 'dart:async';
import 'dart:io' show HttpServer, stdout;

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:jaspr_lint_builder/jaspr_lint_builder.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

/// Builds the static linter documentation site from [yamlFilePath] into
/// [outputDirectoryPath].
Future<LintSiteBuildResult> buildExampleSite({
  String? faviconFilePath,
  FileSystem fs = const LocalFileSystem(),
  String outputDirectoryPath = 'build/web',
  required String yamlFilePath,
}) {
  final resolvedYamlPath = yamlFilePath;
  final resolvedFaviconPath = faviconFilePath ?? _resolveExampleFaviconPath(fs);
  final builder = JasprLintSiteBuilder(
    faviconFilePath: resolvedFaviconPath,
    fs: fs,
  );
  return builder.buildFromYamlFile(
    outputDirectoryPath: outputDirectoryPath,
    yamlFilePath: resolvedYamlPath,
  );
}

/// Creates a [shelf] [Handler] that serves the generated static site in
/// [webDirectoryPath].
Handler createExampleSiteHandler(
  String webDirectoryPath, {
  bool enableLogging = true,
}) {
  final staticHandler = createStaticHandler(
    webDirectoryPath,
    defaultDocument: 'index.html',
  );
  if (!enableLogging) {
    return staticHandler;
  }
  return const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(staticHandler);
}

/// Builds the example documentation site and starts a [shelf] HTTP server on
/// [host]:[port].
Future<HttpServer> serveExampleSite({
  bool enableLogging = true,
  String? faviconFilePath,
  FileSystem fs = const LocalFileSystem(),
  Object host = 'localhost',
  String outputDirectoryPath = 'build/web',
  int port = 8080,
  required String yamlFilePath,
}) async {
  final result = await buildExampleSite(
    faviconFilePath: faviconFilePath,
    fs: fs,
    outputDirectoryPath: outputDirectoryPath,
    yamlFilePath: yamlFilePath,
  );
  stdout.writeln(
    'Built ${result.generatedFiles.length} static site files for '
    '${result.rules.length} lints in ${result.outputDirectoryPath}.',
  );

  final handler = createExampleSiteHandler(
    result.outputDirectoryPath,
    enableLogging: enableLogging,
  );
  final server = await shelf_io.serve(handler, host, port);
  stdout.writeln(
    'Serving ${result.title} documentation at '
    'http://${server.address.host}:${server.port}',
  );
  return server;
}

/// Parses CLI arguments, builds the example website, and serves it via [shelf].
Future<void> runExampleServeCli(
  List<String> args, {
  FileSystem fs = const LocalFileSystem(),
}) async {
  final parser = ArgParser()
    ..addOption(
      'favicon',
      abbr: 'f',
      help: 'Optional path to a PNG image file used to generate site favicons.',
    )
    ..addOption(
      'host',
      defaultsTo: 'localhost',
      help: 'Hostname or IP address to bind the shelf server to.',
    )
    ..addOption(
      'input',
      abbr: 'i',
      defaultsTo: '../../ilt_lints/assets/lints.yaml',
      help: 'Path to the input lints.yaml file.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'build/web',
      help: 'Directory where the static website files are generated.',
    )
    ..addOption(
      'port',
      abbr: 'p',
      defaultsTo: '8080',
      help: 'Port number for the shelf server.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show usage information.',
      negatable: false,
    );

  final parsed = parser.parse(args);
  if (parsed['help'] == true) {
    stdout.writeln('Builds and serves the custom lint documentation website.');
    stdout.writeln();
    stdout.writeln(parser.usage);
    return;
  }

  final faviconPath = parsed['favicon'] as String?;
  final host = parsed['host'] as String;
  final inputPath = parsed['input'] as String;
  final outputDir = parsed['output'] as String;
  final port = int.tryParse(parsed['port'] as String? ?? '') ?? 8080;

  var restart = Completer<void>();

  void restartServer() async {
    while (true) {
      final r = restart;
      final server = await serveExampleSite(
        faviconFilePath: faviconPath,
        fs: fs,
        host: host,
        outputDirectoryPath: outputDir,
        port: port,
        yamlFilePath: inputPath,
      );

      await r.future;

      await server.close();
    }
  }

  restartServer();

  final inputFile = fs.file(inputPath);
  inputFile.watch().listen((_) {
    restart.complete();
    restart = Completer<void>();
  });
}

String? _resolveExampleFaviconPath(FileSystem fs) {
  const candidates = <String>[
    '../../ilt_lints/assets/favicon.png',
    '../ilt_lints/assets/favicon.png',
    'packages/ilt_lints/assets/favicon.png',
  ];
  for (final candidate in candidates) {
    if (fs.file(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}
