import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/fixes/sort_fields_fix.dart';
import 'src/fixes/sort_functions_alphabetically_fix.dart';
import 'src/fixes/sort_functions_by_scope_fix.dart';
import 'src/fixes/sort_named_parameters_fix.dart';
import 'src/rules/sort_fields.dart';
import 'src/rules/sort_functions_alphabetically.dart';
import 'src/rules/sort_functions_by_scope.dart';
import 'src/rules/sort_named_parameters.dart';

/// The analyzer plugin entry point for `ilt_lints`.
final plugin = IltLintsPlugin();

/// Analyzer plugin that registers custom `ilt_lints` rules and quick fixes.
class IltLintsPlugin extends Plugin {
  @override
  String get name => 'ilt_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(SortFields());
    registry.registerFixForRule(
      SortFields.code,
      SortFieldsFix.new,
    );
    registry.registerLintRule(SortFunctionsByScope());
    registry.registerFixForRule(
      SortFunctionsByScope.code,
      SortFunctionsByScopeFix.new,
    );
    registry.registerLintRule(SortFunctionsAlphabetically());
    registry.registerFixForRule(
      SortFunctionsAlphabetically.code,
      SortFunctionsAlphabeticallyFix.new,
    );
    registry.registerLintRule(SortNamedParameters());
    registry.registerFixForRule(
      SortNamedParameters.code,
      SortNamedParametersFix.new,
    );
  }
}
