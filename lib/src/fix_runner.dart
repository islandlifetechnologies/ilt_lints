// ignore_for_file: implementation_imports

import 'dart:io' as io;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/analysis_options/analysis_options.dart';
import 'package:analyzer/src/analysis_rule/rule_context.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/driver_based_analysis_context.dart';
import 'package:analyzer/src/ignore_comments/ignore_info.dart';
import 'package:analyzer/src/lint/linter_visitor.dart';
import 'package:analyzer/src/lint/registry.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:yaml/yaml.dart';

import 'fixes/export_library_fix.dart';
import 'fixes/prefer_const_constructors_fix.dart';
import 'fixes/prefer_primary_constructors_fix.dart';
import 'fixes/sort_fields_fix.dart';
import 'fixes/sort_functions_alphabetically_fix.dart';
import 'fixes/sort_functions_by_scope_fix.dart';
import 'fixes/sort_named_parameters_fix.dart';
import 'fixes/use_clock_fix.dart';
import 'fixes/use_file_system_fix.dart';
import 'fixes/valid_json_serializable_fix.dart';
import 'rules/export_library.dart';
import 'rules/prefer_const_constructors.dart';
import 'rules/prefer_primary_constructors.dart';
import 'rules/sort_fields.dart';
import 'rules/sort_functions_alphabetically.dart';
import 'rules/sort_functions_by_scope.dart';
import 'rules/sort_named_parameters.dart';
import 'rules/use_clock.dart';
import 'rules/use_file_system.dart';
import 'rules/valid_json_serializable.dart';

/// Runs the `ilt_lints` CLI fix tool with [args].
Future<int> runFixCli(
  List<String> args, {
  StringSink? err,
  StringSink? out,
  ResourceProvider? resourceProvider,
  String? sdkPath,
  String? workingDirectory,
}) async {
  final stdoutSink = out ?? io.stdout;
  final stderrSink = err ?? io.stderr;
  final provider = resourceProvider ?? PhysicalResourceProvider.INSTANCE;
  final pathContext = provider.pathContext;
  final cwd = workingDirectory ?? pathContext.current;

  var dryRun = false;
  var showHelp = false;
  final rawPaths = <String>[];

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      showHelp = true;
    } else if (arg == '--dry-run' || arg == '-n') {
      dryRun = true;
    } else if (arg.startsWith('-')) {
      stderrSink.writeln('Unknown option: $arg');
      _printUsage(stderrSink);
      return 64;
    } else {
      rawPaths.add(arg);
    }
  }

  if (showHelp) {
    _printUsage(stdoutSink);
    return 0;
  }

  final targets = rawPaths.isEmpty ? const ['.'] : rawPaths;
  final resolvedTargets = <String>[];
  for (final target in targets) {
    final absolutePath = pathContext.isAbsolute(target)
        ? pathContext.normalize(target)
        : pathContext.normalize(pathContext.join(cwd, target));
    final resource = provider.getResource(absolutePath);
    if (!resource.exists) {
      stderrSink.writeln('Path does not exist: $target');
      return 64;
    }
    resolvedTargets.add(absolutePath);
  }

  stdoutSink.writeln(
    dryRun
        ? 'Computing fixes in [${targets.join(', ')}] (dry run)...'
        : 'Computing fixes in [${targets.join(', ')}]...',
  );

  final runner = FixRunner(
    dryRun: dryRun,
    resourceProvider: provider,
    sdkPath: sdkPath,
  );
  final result = await runner.run(resolvedTargets);

  if (result.fileResults.isEmpty) {
    stdoutSink.writeln('Nothing to fix!');
    return 0;
  }

  stdoutSink.writeln(
    dryRun ? 'Fixes that would be applied:' : 'Applying fixes...',
  );
  for (final fileResult in result.fileResults) {
    final relativePath = pathContext.relative(fileResult.filePath, from: cwd);
    stdoutSink.writeln('  $relativePath');
    for (final entry in fileResult.fixesByRule.entries) {
      final count = entry.value;
      final label = count == 1 ? 'fix' : 'fixes';
      stdoutSink.writeln('    ${entry.key} ($count $label)');
    }
  }

  final totalFixes = result.totalFixes;
  final totalFiles = result.totalFilesFixed;
  final fixWord = totalFixes == 1 ? 'fix' : 'fixes';
  final fileWord = totalFiles == 1 ? 'file' : 'files';
  if (dryRun) {
    stdoutSink.writeln(
      '$totalFixes $fixWord would be applied in $totalFiles $fileWord.',
    );
  } else {
    stdoutSink.writeln(
      'Applied $totalFixes $fixWord in $totalFiles $fileWord.',
    );
  }
  return 0;
}

void _printUsage(StringSink sink) {
  sink.writeln('Usage: dart run ilt_lints:fix [options] [<paths>...]');
  sink.writeln();
  sink.writeln(
    'Applies automated fixes for all enabled custom ilt_lints rules.',
  );
  sink.writeln();
  sink.writeln('Options:');
  sink.writeln(
    '  -n, --dry-run    Show which fixes would be applied without modifying files.',
  );
  sink.writeln('  -h, --help       Print this usage information.');
}

/// Summary of fixes applied to a single file.
class FileFixResult {
  const FileFixResult({required this.filePath, required this.fixesByRule});

  final String filePath;
  final Map<String, int> fixesByRule;

  int get totalFixes => fixesByRule.values.fold(0, (sum, count) => sum + count);
}

/// Summary of fixes applied across a [FixRunner.run] invocation.
class FixRunResult {
  const FixRunResult({required this.fileResults});

  final List<FileFixResult> fileResults;

  int get totalFilesFixed => fileResults.length;

  int get totalFixes =>
      fileResults.fold(0, (sum, file) => sum + file.totalFixes);
}

/// Runs enabled custom `ilt_lints` rules and applies their fixes to Dart files.
class FixRunner {
  FixRunner({
    this.dryRun = false,
    ResourceProvider? resourceProvider,
    this.sdkPath,
  }) : _resourceProvider =
           resourceProvider ?? PhysicalResourceProvider.INSTANCE;

  static const _maxIterationsPerRule = 50;

  static final _ruleEntries = [
    _RuleFixEntry(
      fixGenerator: ExportLibraryFix.new,
      name: ExportLibrary.code.lowerCaseName,
      ruleFactory: ExportLibrary.new,
    ),
    _RuleFixEntry(
      fixGenerator: PreferConstConstructorsFix.new,
      name: PreferConstConstructors.code.lowerCaseName,
      ruleFactory: PreferConstConstructors.new,
    ),
    _RuleFixEntry(
      fixGenerator: PreferPrimaryConstructorsFix.new,
      name: PreferPrimaryConstructors.code.lowerCaseName,
      ruleFactory: PreferPrimaryConstructors.new,
    ),
    _RuleFixEntry(
      fixGenerator: SortFieldsFix.new,
      name: SortFields.code.lowerCaseName,
      ruleFactory: SortFields.new,
    ),
    _RuleFixEntry(
      fixGenerator: SortFunctionsByScopeFix.new,
      name: SortFunctionsByScope.code.lowerCaseName,
      ruleFactory: SortFunctionsByScope.new,
    ),
    _RuleFixEntry(
      fixGenerator: SortFunctionsAlphabeticallyFix.new,
      name: SortFunctionsAlphabetically.code.lowerCaseName,
      ruleFactory: SortFunctionsAlphabetically.new,
    ),
    _RuleFixEntry(
      fixGenerator: SortNamedParametersFix.new,
      name: SortNamedParameters.code.lowerCaseName,
      ruleFactory: SortNamedParameters.new,
    ),
    _RuleFixEntry(
      fixGenerator: UseClockFix.new,
      name: UseClock.code.lowerCaseName,
      ruleFactory: UseClock.new,
    ),
    _RuleFixEntry(
      fixGenerator: UseFileSystemFix.new,
      name: UseFileSystem.code.lowerCaseName,
      ruleFactory: UseFileSystem.new,
    ),
    _RuleFixEntry(
      fixGenerator: ValidJsonSerializableFix.new,
      name: ValidJsonSerializable.code.lowerCaseName,
      ruleFactory: ValidJsonSerializable.new,
    ),
  ];

  final bool dryRun;
  final String? sdkPath;
  final ResourceProvider _resourceProvider;
  var _overlayModificationStamp = 1;

  static void _registerRulesInGlobalRegistry() {
    for (final entry in _ruleEntries) {
      Registry.ruleRegistry.registerLintRule(entry.ruleFactory());
    }
  }

  /// Analyzes [targetPaths] and applies fixes for all enabled custom lints.
  Future<FixRunResult> run(List<String> targetPaths) async {
    _registerRulesInGlobalRegistry();

    final pathContext = _resourceProvider.pathContext;
    final includedPaths = [
      for (final target in targetPaths)
        pathContext.normalize(pathContext.absolute(target)),
    ];

    final overlayProvider = OverlayResourceProvider(_resourceProvider);
    final collection = AnalysisContextCollectionImpl(
      includedPaths: includedPaths,
      resourceProvider: overlayProvider,
      sdkPath: sdkPath,
    );

    final fileResults = <FileFixResult>[];
    try {
      for (final context in collection.contexts) {
        final dartFiles =
            context.contextRoot
                .analyzedFiles()
                .where((path) => path.endsWith('.dart'))
                .where((path) => _isWithinTargets(path, includedPaths))
                .toList()
              ..sort();

        for (final filePath in dartFiles) {
          final fileResult = await _processFile(
            context: context,
            filePath: filePath,
            overlayProvider: overlayProvider,
          );
          if (fileResult != null) {
            fileResults.add(fileResult);
          }
        }
      }
    } finally {
      await collection.dispose();
    }

    return FixRunResult(fileResults: fileResults);
  }

  void _applyYamlRuleOverrides(YamlMap root, Set<String> enabled) {
    void updateRuleState(String name, Object? value) {
      final lower = name.toLowerCase();
      if (!_ruleEntries.any((e) => e.name == lower)) {
        return;
      }
      if (value is bool) {
        if (value) {
          enabled.add(lower);
        } else {
          enabled.remove(lower);
        }
      } else if (value is String) {
        final normalized = value.toLowerCase();
        if (normalized == 'ignore' ||
            normalized == 'false' ||
            normalized == 'disable') {
          enabled.remove(lower);
        } else if (normalized == 'true' ||
            normalized == 'enable' ||
            normalized == 'info' ||
            normalized == 'warning' ||
            normalized == 'error') {
          enabled.add(lower);
        }
      } else if (value is YamlList) {
        enabled.add(lower);
      } else if (value is YamlMap) {
        if (value['enabled'] == false) {
          enabled.remove(lower);
        } else {
          enabled.add(lower);
        }
      }
    }

    void collectFromRulesNode(Object? rulesNode) {
      if (rulesNode is YamlList) {
        for (final item in rulesNode.nodes) {
          if (item case YamlScalar(value: final String ruleName)) {
            updateRuleState(ruleName, true);
          }
        }
      } else if (rulesNode is YamlMap) {
        for (final entry in rulesNode.entries) {
          final key = entry.key;
          if (key is String) {
            updateRuleState(key, entry.value);
          }
        }
      }
    }

    final linter = root['linter'];
    if (linter is YamlMap) {
      collectFromRulesNode(linter['rules']);
    }

    final plugins = root['plugins'];
    if (plugins is YamlMap) {
      final iltPlugin = plugins['ilt_lints'];
      if (iltPlugin is bool && !iltPlugin) {
        enabled.clear();
      } else if (iltPlugin is YamlMap) {
        if (iltPlugin['enabled'] == false) {
          enabled.clear();
        } else {
          collectFromRulesNode(iltPlugin['diagnostics']);
        }
      }
    }

    final iltLints = root['ilt_lints'];
    if (iltLints is YamlMap) {
      collectFromRulesNode(iltLints['diagnostics']);
      collectFromRulesNode(iltLints['rules']);
    }

    final analyzer = root['analyzer'];
    if (analyzer is YamlMap) {
      final errors = analyzer['errors'];
      if (errors is YamlMap) {
        for (final entry in errors.entries) {
          final key = entry.key;
          if (key is String) {
            final value = entry.value?.toString().toLowerCase();
            if (value == 'ignore') {
              updateRuleState(key, 'ignore');
            }
          }
        }
      }
    }
  }

  List<Diagnostic> _computeDiagnosticsForRules({
    required DriverBasedAnalysisContext context,
    required List<AnalysisRule> rules,
    required ResolvedUnitResult unitResult,
  }) {
    final listener = RecordingDiagnosticListener();
    final contextUnit = RuleContextUnit(
      content: unitResult.content,
      diagnosticReporter: DiagnosticReporter(
        listener,
        unitResult.libraryElement.firstFragment.source,
      ),
      file: unitResult.file,
      unit: unitResult.unit,
    );
    final package = context.contextRoot.workspace.findPackageFor(
      unitResult.path,
    );
    final ruleContext = RuleContextWithResolvedResults(
      [contextUnit],
      contextUnit,
      unitResult.typeProvider,
      unitResult.typeSystem,
      package,
    )..currentUnit = contextUnit;

    final ruleVisitorRegistry = RuleVisitorRegistryImpl(enableTiming: false);
    for (final rule in rules) {
      rule.reporter = contextUnit.diagnosticReporter;
      rule.registerNodeProcessors(ruleVisitorRegistry, ruleContext);
    }

    unitResult.unit.accept(
      AnalysisRuleVisitor(ruleVisitorRegistry, shouldPropagateExceptions: true),
    );

    final ignoreInfo = IgnoreInfo.forDart(unitResult.unit, unitResult.content);
    return listener.diagnostics
        .where((d) => !ignoreInfo.ignored(d, pluginName: 'ilt_lints'))
        .toList();
  }

  List<_RuleFixEntry> _enabledRulesForFile(
    DriverBasedAnalysisContext context,
    File file,
  ) {
    final enabledNames = <String>{};
    final options = context.getAnalysisOptionsForFile(file);

    if (options is AnalysisOptionsImpl) {
      for (final entry in _ruleEntries) {
        if (options.isLintEnabled(entry.name)) {
          enabledNames.add(entry.name);
        }
      }
      for (final pluginConfig in options.pluginConfigurations) {
        if (pluginConfig.name.toLowerCase() != 'ilt_lints') {
          continue;
        }
        if (!pluginConfig.isEnabled) {
          enabledNames.clear();
          continue;
        }
        for (final diagEntry in pluginConfig.diagnosticConfigs.entries) {
          final diagName = diagEntry.key.toLowerCase();
          if (diagEntry.value.isEnabled) {
            enabledNames.add(diagName);
          } else {
            enabledNames.remove(diagName);
          }
        }
      }
      for (final processor in options.errorProcessors) {
        if (processor.severity == null) {
          enabledNames.remove(processor.code.toLowerCase());
        }
      }
    }

    final optionsFile =
        _findNearestOptionsFile(file) ?? context.contextRoot.optionsFile;
    if (optionsFile != null && optionsFile.exists) {
      try {
        final content = optionsFile.readAsStringSync();
        final yaml = loadYamlNode(content);
        if (yaml is YamlMap) {
          _applyYamlRuleOverrides(yaml, enabledNames);
        }
      } on Object {
        // Ignore malformed YAML and rely on AnalysisOptionsImpl.
      }
    }

    return [
      for (final entry in _ruleEntries)
        if (enabledNames.contains(entry.name)) entry,
    ];
  }

  File? _findNearestOptionsFile(File startFile) {
    Folder? folder = startFile.parent;
    while (folder != null) {
      final candidate = folder.getFile('analysis_options.yaml');
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

  bool _isWithinTargets(String filePath, List<String> targets) {
    final pathContext = _resourceProvider.pathContext;
    for (final target in targets) {
      if (filePath == target || pathContext.isWithin(target, filePath)) {
        return true;
      }
    }
    return false;
  }

  Future<FileFixResult?> _processFile({
    required DriverBasedAnalysisContext context,
    required String filePath,
    required OverlayResourceProvider overlayProvider,
  }) async {
    final diskFile = _resourceProvider.getFile(filePath);
    if (!diskFile.exists) {
      return null;
    }

    final enabledEntries = _enabledRulesForFile(context, diskFile);
    if (enabledEntries.isEmpty) {
      return null;
    }

    final originalContent = diskFile.readAsStringSync();
    var currentContent = originalContent;

    await context.driver.applyPendingFileChanges();
    final initialUnit = await context.currentSession.getResolvedUnit(filePath);
    if (initialUnit is! ResolvedUnitResult) {
      return null;
    }

    final initialDiagnostics = _computeDiagnosticsForRules(
      context: context,
      rules: [for (final entry in enabledEntries) entry.ruleFactory()],
      unitResult: initialUnit,
    );
    if (initialDiagnostics.isEmpty) {
      return null;
    }

    final fixesByRule = <String, int>{};

    for (final entry in enabledEntries) {
      for (var iteration = 0; iteration < _maxIterationsPerRule; iteration++) {
        await context.driver.applyPendingFileChanges();
        final unitResult = await context.currentSession.getResolvedUnit(
          filePath,
        );
        if (unitResult is! ResolvedUnitResult) {
          break;
        }

        final diagnostics = _computeDiagnosticsForRules(
          context: context,
          rules: [entry.ruleFactory()],
          unitResult: unitResult,
        );
        if (diagnostics.isEmpty) {
          break;
        }

        final libraryResult = await unitResult.session
            .getResolvedLibraryByElement(unitResult.libraryElement);
        if (libraryResult is! ResolvedLibraryResult) {
          break;
        }

        var appliedChange = false;
        for (final diagnostic in diagnostics) {
          final producerContext = CorrectionProducerContext.createResolved(
            diagnostic: diagnostic,
            libraryResult: libraryResult,
            selectionLength: diagnostic.length,
            selectionOffset: diagnostic.offset,
            unitResult: unitResult,
          );
          final producer = entry.fixGenerator(context: producerContext);
          final builder = ChangeBuilder(session: unitResult.session);
          await producer.compute(builder);
          final fileEdits = builder.sourceChange.edits;
          if (fileEdits.isEmpty || fileEdits.first.edits.isEmpty) {
            continue;
          }

          final nextContent = SourceEdit.applySequence(
            currentContent,
            fileEdits.first.edits,
          );
          if (nextContent == currentContent) {
            continue;
          }

          currentContent = nextContent;
          fixesByRule[entry.name] = (fixesByRule[entry.name] ?? 0) + 1;
          overlayProvider.setOverlay(
            filePath,
            content: currentContent,
            modificationStamp: _overlayModificationStamp++,
          );
          context.driver.changeFile(filePath);
          appliedChange = true;
          break;
        }

        if (!appliedChange) {
          break;
        }
      }
    }

    if (currentContent == originalContent) {
      return null;
    }

    if (overlayProvider.hasOverlay(filePath)) {
      overlayProvider.removeOverlay(filePath);
    }

    if (!dryRun) {
      diskFile.writeAsStringSync(currentContent);
      context.driver.changeFile(filePath);
    }

    return FileFixResult(filePath: filePath, fixesByRule: fixesByRule);
  }
}

class _RuleFixEntry {
  const _RuleFixEntry({
    required this.fixGenerator,
    required this.name,
    required this.ruleFactory,
  });

  final ResolvedCorrectionProducer Function({
    required CorrectionProducerContext context,
  })
  fixGenerator;
  final String name;
  final AnalysisRule Function() ruleFactory;
}
