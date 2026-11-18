import 'dart:io';

import 'package:ilt_lints/ilt_lints.dart';
import 'package:quick_fix/quick_fix.dart';

Future<void> main(List<String> args) async {
  exitCode = await runQuickFixCli(
    args,
    ruleEntries: [
      RuleFixEntry(
        fixGenerator: ExportLibraryFix.new,
        name: ExportLibrary.code.lowerCaseName,
        ruleFactory: ExportLibrary.new,
      ),
      RuleFixEntry(
        fixGenerator: PreferConstConstructorsFix.new,
        name: PreferConstConstructors.code.lowerCaseName,
        ruleFactory: PreferConstConstructors.new,
      ),
      RuleFixEntry(
        fixGenerator: PreferNamedParametersFix.new,
        name: PreferNamedParameters.code.lowerCaseName,
        ruleFactory: PreferNamedParameters.new,
      ),
      RuleFixEntry(
        fixGenerator: PreferPrimaryConstructorsFix.new,
        name: PreferPrimaryConstructors.code.lowerCaseName,
        ruleFactory: PreferPrimaryConstructors.new,
      ),
      RuleFixEntry(
        fixGenerator: SortFieldsFix.new,
        name: SortFields.code.lowerCaseName,
        ruleFactory: SortFields.new,
      ),
      RuleFixEntry(
        fixGenerator: SortWidgetFunctionsFix.new,
        name: SortWidgetFunctions.code.lowerCaseName,
        ruleFactory: SortWidgetFunctions.new,
      ),
      RuleFixEntry(
        fixGenerator: SortFunctionsByScopeFix.new,
        name: SortFunctionsByScope.code.lowerCaseName,
        ruleFactory: SortFunctionsByScope.new,
      ),
      RuleFixEntry(
        fixGenerator: SortFunctionsAlphabeticallyFix.new,
        name: SortFunctionsAlphabetically.code.lowerCaseName,
        ruleFactory: SortFunctionsAlphabetically.new,
      ),
      RuleFixEntry(
        fixGenerator: SortNamedParametersFix.new,
        name: SortNamedParameters.code.lowerCaseName,
        ruleFactory: SortNamedParameters.new,
      ),
      RuleFixEntry(
        fixGenerator: UseClockFix.new,
        name: UseClock.code.lowerCaseName,
        ruleFactory: UseClock.new,
      ),
      RuleFixEntry(
        fixGenerator: UseFileSystemFix.new,
        name: UseFileSystem.code.lowerCaseName,
        ruleFactory: UseFileSystem.new,
      ),
      RuleFixEntry(
        fixGenerator: ValidJsonSerializableFix.new,
        name: ValidJsonSerializable.code.lowerCaseName,
        ruleFactory: ValidJsonSerializable.new,
      ),
    ],
  );
}
