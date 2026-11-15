import 'dart:io' as io show stderr, stdout;
import 'dart:isolate' show Isolate;

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:yaon/yaon.dart';

export 'package:json_schema/json_schema.dart'
    show ValidationError, ValidationResults;

/// Resolves an input `lints.yaml` file path against [fs], optionally checking
/// standard workspace fallback locations when [allowFallbacks] is `true`.
String? resolveLintInputFilePath(
  FileSystem fs,
  String inputPath, {
  bool allowFallbacks = true,
}) {
  final directFile = fs.file(inputPath);
  if (directFile.existsSync()) {
    return directFile.path;
  }
  if (!allowFallbacks) {
    return null;
  }
  const fallbackCandidates = <String>[
    'packages/ilt_lints/assets/lints.yaml',
    '../ilt_lints/assets/lints.yaml',
    '../../ilt_lints/assets/lints.yaml',
    'assets/lints.yaml',
  ];
  for (final candidate in fallbackCandidates) {
    final candidateFile = fs.file(candidate);
    if (candidateFile.existsSync()) {
      return candidateFile.path;
    }
  }
  return null;
}

/// CLI runner for `jaspr_lint_builder:validate` that validates a `lints.yaml`
/// file against `assets/lint_schema.yaml` without building the site.
///
/// Returns `0` when validation succeeds, or a non-zero exit code when it fails.
Future<int> runJasprLintValidateCli(
  List<String> args, {
  StringSink? err,
  FileSystem fs = const LocalFileSystem(),
  StringSink? out,
  String? schemaFilePath,
}) async {
  final parser = ArgParser()
    ..addOption(
      'input',
      abbr: 'i',
      defaultsTo: '../ilt_lints/assets/lints.yaml',
      help: 'Path to the input lints.yaml file matching lint_schema.yaml.',
    )
    ..addOption(
      'schema',
      abbr: 's',
      help: 'Optional path to the lint_schema.yaml file.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Display usage information.',
      negatable: false,
    );

  final stdoutSink = out ?? io.stdout;
  final stderrSink = err ?? io.stderr;

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (error) {
    stderrSink.writeln('Error: ${error.message}');
    stderrSink.writeln(parser.usage);
    return 64;
  }

  if (parsed['help'] == true) {
    stdoutSink.writeln(
      'Validates a custom lint YAML specification against lint_schema.yaml.',
    );
    stdoutSink.writeln();
    stdoutSink.writeln(parser.usage);
    return 0;
  }

  final explicitInput = parsed.wasParsed('input') || parsed.rest.isNotEmpty;
  final rawInput = parsed.wasParsed('input')
      ? parsed['input'] as String
      : (parsed.rest.isNotEmpty
            ? parsed.rest.first
            : parsed['input'] as String);
  final resolvedSchemaPath = (parsed['schema'] as String?) ?? schemaFilePath;

  final resolvedInput = resolveLintInputFilePath(
    fs,
    rawInput,
    allowFallbacks: !explicitInput,
  );
  if (resolvedInput == null) {
    stderrSink.writeln('Input YAML file does not exist: $rawInput');
    return 66;
  }

  try {
    final validator = LintSchemaValidator(
      fs: fs,
      schemaFilePath: resolvedSchemaPath,
    );
    final results = validator.validateFile(resolvedInput);
    if (!results.isValid) {
      stderrSink.writeln('Invalid lint YAML specification ($resolvedInput):');
      for (final error in results.errors) {
        stderrSink.writeln('  - $error');
      }
      return 65;
    }
    stdoutSink.writeln('Validated $resolvedInput successfully.');
    return 0;
  } on FormatException catch (error) {
    stderrSink.writeln('Invalid lint YAML specification: ${error.message}');
    return 65;
  }
}

/// Validates a custom lint YAML file (`lints.yaml`) against
/// `assets/lint_schema.yaml` and returns the [ValidationResults].
ValidationResults validateLintYamlFile(
  String yamlFilePath, {
  FileSystem fs = const LocalFileSystem(),
  String? schemaFilePath,
}) => LintSchemaValidator(
  fs: fs,
  schemaFilePath: schemaFilePath,
).validateFile(yamlFilePath);

/// Validates a custom lint YAML string against `assets/lint_schema.yaml` and
/// returns the [ValidationResults].
ValidationResults validateLintYamlString(
  String yamlContent, {
  FileSystem fs = const LocalFileSystem(),
  String? schemaFilePath,
  String? schemaYamlContent,
}) => LintSchemaValidator(
  fs: fs,
  schemaFilePath: schemaFilePath,
).validateYamlString(yamlContent, schemaYamlContent: schemaYamlContent);

/// Validates custom lint YAML specifications against `assets/lint_schema.yaml`
/// using `package:json_schema` and `package:yaon`.
class const LintSchemaValidator({
  final FileSystem fs = const LocalFileSystem(),
  final String? schemaFilePath,
}) {
  static const _schemaRelativeCandidates = <String>[
    'assets/lint_schema.yaml',
    'packages/jaspr_lint_builder/assets/lint_schema.yaml',
    '../assets/lint_schema.yaml',
    '../jaspr_lint_builder/assets/lint_schema.yaml',
    '../../jaspr_lint_builder/assets/lint_schema.yaml',
  ];

  /// Validates [data] against `assets/lint_schema.yaml` and throws a
  /// [FormatException] if validation fails.
  void assertValidData(Object? data, {String? schemaYamlContent}) {
    final results = validateData(data, schemaYamlContent: schemaYamlContent);
    if (!results.isValid) {
      final details = results.errors.map((e) => e.toString()).join('; ');
      throw FormatException('Lint YAML failed schema validation: $details');
    }
  }

  /// Reads [yamlFilePath], validates it against `assets/lint_schema.yaml`, and
  /// throws a [FormatException] if validation fails.
  void assertValidFile(String yamlFilePath) {
    final results = validateFile(yamlFilePath);
    if (!results.isValid) {
      final details = results.errors.map((e) => e.toString()).join('; ');
      throw FormatException(
        'Lint YAML file "$yamlFilePath" failed schema validation: $details',
      );
    }
  }

  /// Parses [yamlContent] using `yaon`, validates it against
  /// `assets/lint_schema.yaml`, and throws a [FormatException] if validation
  /// fails.
  void assertValidYamlString(String yamlContent, {String? schemaYamlContent}) {
    final results = validateYamlString(
      yamlContent,
      schemaYamlContent: schemaYamlContent,
    );
    if (!results.isValid) {
      final details = results.errors.map((e) => e.toString()).join('; ');
      throw FormatException('Lint YAML failed schema validation: $details');
    }
  }

  /// Loads and compiles `assets/lint_schema.yaml` into a [JsonSchema] using
  /// `yaon` and `json_schema`.
  JsonSchema loadSchema({String? schemaYamlContent}) {
    final rawSchemaYaml = schemaYamlContent ?? _readSchemaYamlContent();
    final Object? parsedSchema;
    try {
      parsedSchema = yaon.parse(rawSchemaYaml);
    } on Object catch (error) {
      throw FormatException('Invalid schema YAML: $error');
    }
    if (parsedSchema is! Map) {
      throw const FormatException(
        'Invalid schema YAML: expected a top-level YAML mapping.',
      );
    }
    return JsonSchema.create(parsedSchema);
  }

  /// Validates an already-parsed YAML/JSON object [data] against the compiled
  /// `assets/lint_schema.yaml` [JsonSchema].
  ValidationResults validateData(Object? data, {String? schemaYamlContent}) {
    final schema = loadSchema(schemaYamlContent: schemaYamlContent);
    return schema.validate(data);
  }

  /// Reads [yamlFilePath] using `yaon` and validates it against
  /// `assets/lint_schema.yaml`.
  ValidationResults validateFile(String yamlFilePath) {
    final file = fs.file(yamlFilePath);
    if (!file.existsSync()) {
      throw FormatException('YAML file does not exist: $yamlFilePath');
    }
    final yamlContent = file.readAsStringSync();
    return validateYamlString(yamlContent);
  }

  /// Parses [yamlContent] using `yaon` and validates it against
  /// `assets/lint_schema.yaml`.
  ValidationResults validateYamlString(
    String yamlContent, {
    String? schemaYamlContent,
  }) {
    final Object? parsedData;
    try {
      parsedData = yaon.parse(yamlContent);
    } on Object catch (error) {
      throw FormatException('Invalid YAML document: $error');
    }
    return validateData(parsedData, schemaYamlContent: schemaYamlContent);
  }

  String _readSchemaYamlContent() {
    if (schemaFilePath != null) {
      final customFile = fs.file(schemaFilePath!);
      if (!customFile.existsSync()) {
        throw FormatException(
          'Schema YAML file does not exist: $schemaFilePath',
        );
      }
      return customFile.readAsStringSync();
    }

    for (final candidate in _schemaRelativeCandidates) {
      final candidateFile = fs.file(candidate);
      if (candidateFile.existsSync()) {
        return candidateFile.readAsStringSync();
      }
    }

    const localFs = LocalFileSystem();
    final packageUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:jaspr_lint_builder/jaspr_lint_builder.dart'),
    );
    if (packageUri != null && packageUri.scheme == 'file') {
      final packageRoot = p.dirname(p.dirname(p.fromUri(packageUri)));
      final resolvedPath = p.join(packageRoot, 'assets', 'lint_schema.yaml');
      final fsFile = fs.file(resolvedPath);
      if (fsFile.existsSync()) {
        return fsFile.readAsStringSync();
      }
      final localFile = localFs.file(resolvedPath);
      if (localFile.existsSync()) {
        return localFile.readAsStringSync();
      }
    }

    for (final candidate in _schemaRelativeCandidates) {
      final localFile = localFs.file(candidate);
      if (localFile.existsSync()) {
        return localFile.readAsStringSync();
      }
    }

    throw const FormatException('Could not locate assets/lint_schema.yaml.');
  }
}
