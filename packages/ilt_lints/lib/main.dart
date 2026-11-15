import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/fixes/export_library_fix.dart';
import 'src/fixes/prefer_const_constructors_fix.dart';
import 'src/fixes/prefer_primary_constructors_fix.dart';
import 'src/fixes/sort_fields_fix.dart';
import 'src/fixes/sort_functions_alphabetically_fix.dart';
import 'src/fixes/sort_functions_by_scope_fix.dart';
import 'src/fixes/sort_named_parameters_fix.dart';
import 'src/fixes/use_clock_fix.dart';
import 'src/fixes/use_file_system_fix.dart';
import 'src/fixes/valid_json_serializable_fix.dart';
import 'src/rules/export_library.dart';
import 'src/rules/prefer_const_constructors.dart';
import 'src/rules/prefer_primary_constructors.dart';
import 'src/rules/sort_fields.dart';
import 'src/rules/sort_functions_alphabetically.dart';
import 'src/rules/sort_functions_by_scope.dart';
import 'src/rules/sort_named_parameters.dart';
import 'src/rules/use_clock.dart';
import 'src/rules/use_file_system.dart';
import 'src/rules/valid_json_serializable.dart';

/// The analyzer plugin entry point for `ilt_lints`.
final plugin = IltLintsPlugin();

/// Analyzer plugin that registers custom `ilt_lints` rules and quick fixes.
class IltLintsPlugin extends Plugin {
  @override
  String get name => 'ilt_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(ExportLibrary());
    registry.registerFixForRule(ExportLibrary.code, ExportLibraryFix.new);
    registry.registerLintRule(PreferConstConstructors());
    registry.registerFixForRule(
      PreferConstConstructors.code,
      PreferConstConstructorsFix.new,
    );
    registry.registerLintRule(PreferPrimaryConstructors());
    registry.registerFixForRule(
      PreferPrimaryConstructors.code,
      PreferPrimaryConstructorsFix.new,
    );
    registry.registerLintRule(SortFields());
    registry.registerFixForRule(SortFields.code, SortFieldsFix.new);
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
    registry.registerLintRule(UseClock());
    registry.registerFixForRule(UseClock.code, UseClockFix.new);
    registry.registerLintRule(UseFileSystem());
    registry.registerFixForRule(UseFileSystem.code, UseFileSystemFix.new);
    registry.registerLintRule(ValidJsonSerializable());
    registry.registerFixForRule(
      ValidJsonSerializable.code,
      ValidJsonSerializableFix.new,
    );
  }
}
