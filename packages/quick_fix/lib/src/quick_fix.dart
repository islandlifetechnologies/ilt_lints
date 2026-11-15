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
import 'package:args/args.dart';
import 'package:quick_fix/quick_fix.dart';
import 'package:yaml/yaml.dart';

Future<int> runQuickFixCli(
  List<String> args, {
  StringSink? err,
  StringSink? out,
  ResourceProvider? resourceProvider,
  required List<RuleFixEntry> ruleEntries,
  String? sdkPath,
  String? workingDirectory,
}) async {
  final parser = ArgParser()
    ..addOption(
      'max-iterations-per-rule',
      defaultsTo: '50',
      help: 'Maximum number of fixes runs to apply for any given rule',
    )
    ..addMultiOption(
      'exclude',
      abbr: 'e',
      help: 'Exclude rule fix from being applied',
    )
    ..addMultiOption(
      'path',
      abbr: 'p',
      defaultsTo: ['.'],
      help: 'Paths to analyze',
    )
    ..addFlag('dry-run', abbr: 'n', help: 'Dry run mode')
    ..addFlag('help', abbr: 'h', help: 'Show help');

  final parsed = parser.parse(args);

  final stdoutSink = out ?? io.stdout;
  final stderrSink = err ?? io.stderr;
  final provider = resourceProvider ?? PhysicalResourceProvider.INSTANCE;
  final pathContext = provider.pathContext;
  final cwd = workingDirectory ?? pathContext.current;

  final dryRun = parsed['dry-run'] == true;
  final excluded = parsed['exclude'] as List<String>? ?? const [];
  final showHelp = parsed['help'] == true;
  final rawPaths = parsed['path'] as List<String>;

  if (showHelp) {
    _printUsage(stdoutSink, parser.usage);
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
    maxIterationsPerRule:
        int.tryParse(parsed['max-iterations-per-rule'] ?? '') ?? 50,
    resourceProvider: provider,
    ruleEntries: ruleEntries.where((e) => !excluded.contains(e.name)),
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

void _printUsage(StringSink sink, String usage) {
  sink.writeln('Applies automated fixes for all enabled custom rules.');
  sink.writeln();
  sink.writeln(usage);
}

/// Runs enabled custom rules and applies their fixes to Dart files.
class FixRunner({
  final bool dryRun = false,
  final int _maxIterationsPerRule = 50,
  ResourceProvider? resourceProvider,
  required final Iterable<RuleFixEntry> _ruleEntries,
  final String? sdkPath,
}) {
  this
    : _resourceProvider = resourceProvider ?? PhysicalResourceProvider.INSTANCE;

  final ResourceProvider _resourceProvider;
  var _overlayModificationStamp = 1;

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

  List<RuleFixEntry> _enabledRulesForFile(
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

  void _registerRulesInGlobalRegistry() {
    for (final entry in _ruleEntries) {
      Registry.ruleRegistry.registerLintRule(entry.ruleFactory());
    }
  }
}
