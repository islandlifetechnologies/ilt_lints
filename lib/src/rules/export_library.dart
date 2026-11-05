import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Configuration for a single exporter file in [ExportLibrary].
class ExportLibraryOption {
  const ExportLibraryOption({
    this.exclude = defaultExclude,
    this.exporter = defaultExporter,
    this.include = defaultInclude,
  });

  static const defaultExclude = ['**/g.dart', '**/freezed.dart'];
  static const defaultExporter = r'lib/${packageName}.dart';
  static const defaultInclude = ['src/**/*.dart'];
  static const defaultOption = ExportLibraryOption();

  final List<String> exclude;
  final String exporter;
  final List<String> include;
}

/// Resolved custom configuration options for [ExportLibrary].
class ExportLibraryOptions {
  const ExportLibraryOptions({
    this.options = const [ExportLibraryOption.defaultOption],
  });

  final List<ExportLibraryOption> options;
}

/// A lint rule that ensures all files matching any `include` glob (and not
/// matching any `exclude` glob) for a configured `exporter` file are exported
/// by that exporter.
///
/// If no options are passed in, defaults to:
/// - `exporter`: `lib/${packageName}.dart`
/// - `include`: `['src/**/*.dart']`
/// - `exclude`: `['**/g.dart', '**/freezed.dart']`
class ExportLibrary extends AnalysisRule {
  ExportLibrary({List<ExportLibraryOption>? options})
    : options = options != null
          ? List<ExportLibraryOption>.unmodifiable(options)
          : null,
      super(
        description:
            'Ensure all matching files for an exporter library are exported by it.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'export_library',
    'Missing exports in library exporter: {0}.',
    correctionMessage: 'Try exporting the missing files.',
  );

  /// Optional override for the exporter configurations. When `null`, settings
  /// are read from `analysis_options.yaml` (falling back to
  /// [ExportLibraryOption.defaultOption]).
  final List<ExportLibraryOption>? options;

  /// Computes the sorted list of relative export URIs that [file] is missing
  /// according to [optionsOverride] or `analysis_options.yaml`.
  ///
  /// Returns an empty list if [file] is not a configured exporter or if all
  /// matching files are already exported.
  static List<String> findMissingExports({
    required File file,
    Uri? libraryUri,
    File? optionsFile,
    List<ExportLibraryOption>? optionsOverride,
    required CompilationUnit unit,
  }) {
    final effectiveOptions =
        (optionsOverride != null && optionsOverride.isNotEmpty)
        ? optionsOverride
        : readOptions(file, optionsFile: optionsFile).options;
    if (effectiveOptions.isEmpty) {
      return const [];
    }

    final (packageRoot, packageName) = _resolvePackageRootAndName(
      file,
      libraryUri: libraryUri,
      optionsFile: optionsFile,
    );
    if (packageRoot == null || packageName == null || packageName.isEmpty) {
      return const [];
    }

    final pathContext = file.provider.pathContext;
    if (!pathContext.isWithin(packageRoot.path, file.path)) {
      return const [];
    }

    final fileRelativePath = _toPosixPath(
      pathContext.relative(file.path, from: packageRoot.path),
    );

    final matchingOptions = <ExportLibraryOption>[];
    for (final option in effectiveOptions) {
      final resolvedExporter = _normalizePattern(
        option.exporter.replaceAll(r'${packageName}', packageName),
      );
      if (resolvedExporter.isEmpty) {
        continue;
      }
      if (resolvedExporter == fileRelativePath ||
          Glob(resolvedExporter, context: p.posix).matches(fileRelativePath)) {
        matchingOptions.add(option);
      }
    }

    if (matchingOptions.isEmpty) {
      return const [];
    }

    final exporterDirRelativePath = p.posix.dirname(fileRelativePath);
    final allDartFiles = <File>[];
    _collectDartFiles(packageRoot, allDartFiles);

    final requiredRelativePaths = <String>{};
    for (final candidate in allDartFiles) {
      if (candidate.path == file.path) {
        continue;
      }
      final candidateRelativePath = _toPosixPath(
        pathContext.relative(candidate.path, from: packageRoot.path),
      );
      final candidateRelativeToExporter = exporterDirRelativePath == '.'
          ? candidateRelativePath
          : (p.posix.isWithin(exporterDirRelativePath, candidateRelativePath)
                ? p.posix.relative(
                    candidateRelativePath,
                    from: exporterDirRelativePath,
                  )
                : null);

      for (final option in matchingOptions) {
        final isIncluded = _matchesAnyGlob(
          option.include,
          candidateRelativePath: candidateRelativePath,
          candidateRelativeToExporter: candidateRelativeToExporter,
          packageName: packageName,
        );
        if (!isIncluded) {
          continue;
        }

        final isExcluded = _matchesAnyGlob(
          option.exclude,
          candidateRelativePath: candidateRelativePath,
          candidateRelativeToExporter: candidateRelativeToExporter,
          packageName: packageName,
        );
        if (isExcluded) {
          continue;
        }

        requiredRelativePaths.add(p.posix.normalize(candidateRelativePath));
        break;
      }
    }

    if (requiredRelativePaths.isEmpty) {
      return const [];
    }

    final exportedRelativePaths = <String>{};
    final packagePrefix = 'package:$packageName/';

    for (final directive in unit.directives.whereType<ExportDirective>()) {
      final uriValue = directive.uri.stringValue;
      if (uriValue != null && uriValue.isNotEmpty) {
        if (uriValue.startsWith(packagePrefix)) {
          final subPath = uriValue.substring(packagePrefix.length);
          exportedRelativePaths.add(p.posix.normalize('lib/$subPath'));
        } else if (!uriValue.contains(':')) {
          final resolved = p.posix.normalize(
            p.posix.join(exporterDirRelativePath, uriValue),
          );
          exportedRelativePaths.add(resolved);
        }
      }

      final exportedSourcePath =
          directive.libraryExport?.exportedLibrary?.firstFragment.source.fullName;
      if (exportedSourcePath != null &&
          pathContext.isWithin(packageRoot.path, exportedSourcePath)) {
        final relPath = _toPosixPath(
          pathContext.relative(exportedSourcePath, from: packageRoot.path),
        );
        exportedRelativePaths.add(p.posix.normalize(relPath));
      }
    }

    final missingExportUris = <String>[];
    for (final requiredPath in requiredRelativePaths) {
      if (!exportedRelativePaths.contains(requiredPath)) {
        final exportUri = p.posix.relative(
          requiredPath,
          from: exporterDirRelativePath,
        );
        missingExportUris.add(exportUri);
      }
    }

    missingExportUris.sort();
    return missingExportUris;
  }

  /// Reads the configured [ExportLibraryOptions] for `export_library` from
  /// `analysis_options.yaml` starting from [startFile] or [optionsFile].
  static ExportLibraryOptions readOptions(
    File? startFile, {
    File? optionsFile,
  }) {
    final resolvedOptionsFile =
        optionsFile ?? _findFileUpwards(startFile, 'analysis_options.yaml');
    if (resolvedOptionsFile == null || !resolvedOptionsFile.exists) {
      return const ExportLibraryOptions();
    }
    try {
      final content = resolvedOptionsFile.readAsStringSync();
      final root = loadYamlNode(content);
      if (root is! YamlMap) {
        return const ExportLibraryOptions();
      }
      final collected = <ExportLibraryOption>[];

      void collectList(YamlList list) {
        final parsed = <ExportLibraryOption>[];
        for (final item in list.nodes) {
          if (item is YamlMap) {
            final option = _parseOptionMap(item);
            if (option != null) {
              parsed.add(option);
            }
          }
        }
        if (parsed.isNotEmpty) {
          collected
            ..clear()
            ..addAll(parsed);
        }
      }

      void collect(Object? node) {
        if (node is YamlList) {
          collectList(node);
        } else if (node is YamlMap) {
          if (node['options'] case final YamlList optionsList) {
            collectList(optionsList);
          } else {
            final single = _parseOptionMap(node);
            if (single != null) {
              collected
                ..clear()
                ..add(single);
            }
          }
        }
      }

      collect(root['export_library']);

      final iltLints = root['ilt_lints'];
      if (iltLints is YamlMap) {
        collect(iltLints['export_library']);
        final rules = iltLints['rules'];
        if (rules is YamlMap) {
          collect(rules['export_library']);
        }
      }

      final plugins = root['plugins'];
      if (plugins is YamlMap) {
        final pluginConfig = plugins['ilt_lints'];
        if (pluginConfig is YamlMap) {
          collect(pluginConfig['export_library']);
          final diagnostics = pluginConfig['diagnostics'];
          if (diagnostics is YamlMap) {
            collect(diagnostics['export_library']);
          }
        }
      }

      final linter = root['linter'];
      if (linter is YamlMap) {
        final rules = linter['rules'];
        if (rules is YamlMap) {
          collect(rules['export_library']);
        }
      }

      if (collected.isEmpty) {
        return const ExportLibraryOptions();
      }
      return ExportLibraryOptions(
        options: List<ExportLibraryOption>.unmodifiable(collected),
      );
    } on Object {
      return const ExportLibraryOptions();
    }
  }

  static void _collectDartFiles(Folder folder, List<File> results) {
    try {
      for (final child in folder.getChildren()) {
        if (child is File) {
          if (child.shortName.endsWith('.dart')) {
            results.add(child);
          }
        } else if (child is Folder) {
          if (!child.shortName.startsWith('.')) {
            _collectDartFiles(child, results);
          }
        }
      }
    } on FileSystemException {
      // Ignore unreadable directories.
    }
  }

  static File? _findFileUpwards(File? startFile, String fileName) {
    var folder = startFile?.parent;
    while (folder != null) {
      final candidate = folder.getFile(fileName);
      if (candidate.exists) {
        return candidate;
      }
      final parent = folder.parent;
      if (parent.path == folder.path) {
        break;
      }
      folder = parent;
    }
    return null;
  }

  static Folder? _findLibParentFolder(File? startFile) {
    var folder = startFile?.parent;
    while (folder != null) {
      if (folder.shortName == 'lib') {
        final parent = folder.parent;
        if (parent.path != folder.path) {
          return parent;
        }
      }
      final parent = folder.parent;
      if (parent.path == folder.path) {
        break;
      }
      folder = parent;
    }
    return null;
  }

  static bool _matchesAnyGlob(
    List<String> patterns, {
    required String candidateRelativePath,
    required String? candidateRelativeToExporter,
    required String packageName,
  }) {
    for (final rawPattern in patterns) {
      final pattern = _normalizePattern(
        rawPattern.replaceAll(r'${packageName}', packageName),
      );
      if (pattern.isEmpty) {
        continue;
      }
      final glob = Glob(pattern, context: p.posix);
      if (glob.matches(candidateRelativePath)) {
        return true;
      }
      if (candidateRelativeToExporter != null &&
          glob.matches(candidateRelativeToExporter)) {
        return true;
      }
    }
    return false;
  }

  static String _normalizePattern(String pattern) {
    var normalized = pattern.replaceAll(r'\', '/').trim();
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  static ExportLibraryOption? _parseOptionMap(YamlMap map) {
    final hasExporter = map.containsKey('exporter');
    final hasInclude = map.containsKey('include');
    final hasExclude = map.containsKey('exclude');
    if (!hasExporter && !hasInclude && !hasExclude) {
      return null;
    }
    final exporter = map['exporter'] is String
        ? map['exporter'] as String
        : ExportLibraryOption.defaultExporter;
    final include =
        _parsePatternList(map['include']) ?? ExportLibraryOption.defaultInclude;
    final exclude = hasExclude
        ? (_parsePatternList(map['exclude']) ?? const <String>[])
        : ExportLibraryOption.defaultExclude;
    return ExportLibraryOption(
      exclude: List<String>.unmodifiable(exclude),
      exporter: exporter,
      include: List<String>.unmodifiable(include),
    );
  }

  static List<String>? _parsePatternList(Object? raw) {
    if (raw is YamlList) {
      final result = <String>[];
      for (final item in raw.nodes) {
        if (item case YamlScalar(value: final String pattern)) {
          result.add(pattern);
        }
      }
      return result;
    }
    if (raw is String) {
      return [raw];
    }
    return null;
  }

  static String? _readPackageNameFromPubspec(File pubspecFile) {
    try {
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYamlNode(content);
      if (yaml is YamlMap) {
        final name = yaml['name'];
        if (name is String && name.trim().isNotEmpty) {
          return name.trim();
        }
      }
    } on Object {
      // Fall back to other package name sources.
    }
    return null;
  }

  static (Folder?, String?) _resolvePackageRootAndName(
    File startFile, {
    Uri? libraryUri,
    File? optionsFile,
  }) {
    Folder? packageRoot;
    String? packageName;

    final pubspecFile = _findFileUpwards(startFile, 'pubspec.yaml');
    if (pubspecFile != null && pubspecFile.exists) {
      packageRoot = pubspecFile.parent;
      packageName = _readPackageNameFromPubspec(pubspecFile);
    }

    packageRoot ??= _findLibParentFolder(startFile);
    if (packageRoot == null) {
      final resolvedOptionsFile =
          optionsFile ?? _findFileUpwards(startFile, 'analysis_options.yaml');
      if (resolvedOptionsFile != null && resolvedOptionsFile.exists) {
        packageRoot = resolvedOptionsFile.parent;
      }
    }

    if (packageName == null || packageName.isEmpty) {
      if (libraryUri != null &&
          libraryUri.scheme == 'package' &&
          libraryUri.pathSegments.isNotEmpty) {
        packageName = libraryUri.pathSegments.first;
      } else if (packageRoot != null && packageRoot.shortName.isNotEmpty) {
        packageName = packageRoot.shortName;
      }
    }

    return (packageRoot, packageName);
  }

  static String _toPosixPath(String path) => path.replaceAll(r'\', '/');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    File? optionsFile;
    Uri? libraryUri;
    try {
      final libraryElement = context.libraryElement;
      libraryUri = libraryElement?.uri;
      optionsFile =
          libraryElement?.session.analysisContext.contextRoot.optionsFile;
    } on Object {
      optionsFile = null;
    }
    final visitor = _Visitor(
      this,
      file: context.definingUnit.file,
      libraryUri: libraryUri,
      optionsFile: optionsFile,
      optionsOverride: options,
    );
    registry.addCompilationUnit(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(
    this.rule, {
    required this.file,
    required this.libraryUri,
    required this.optionsFile,
    required this.optionsOverride,
  });

  final File file;
  final Uri? libraryUri;
  final File? optionsFile;
  final List<ExportLibraryOption>? optionsOverride;
  final ExportLibrary rule;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final missingExports = ExportLibrary.findMissingExports(
      file: file,
      libraryUri: libraryUri,
      optionsFile: optionsFile,
      optionsOverride: optionsOverride,
      unit: node,
    );
    if (missingExports.isEmpty) {
      return;
    }
    rule.reportAtNode(
      node,
      arguments: [missingExports.map((uri) => "'$uri'").join(', ')],
    );
  }
}
