import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/use_clock.dart';

/// A quick fix that replaces `DateTime.now()` with `clock.now()` (or
/// `DateTime.now` tear-offs with `clock.now`) and adds
/// `import 'package:clock/clock.dart';` when missing.
class UseClockFix extends ResolvedCorrectionProducer {
  UseClockFix({required super.context});

  static const _clockImportLine = "import '$_clockImportUri';";
  static const _clockImportUri = 'package:clock/clock.dart';

  static const _fixKind = FixKind(
    'dart.fix.useClock',
    DartFixKindPriority.standard,
    'Replace with clock.now',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final targetNode = UseClock.findTargetNode(node);
    if (targetNode == null) {
      return;
    }

    final isCall = UseClock.isDateTimeNowCall(targetNode);
    final replacement = isCall ? 'clock.now()' : 'clock.now';

    final unit = unitResult.unit;
    final eol = utils.endOfLine;
    final importInsertion = _computeClockImportInsertion(unit, eol);

    await builder.addDartFileEdit(file, (builder) {
      if (importInsertion != null) {
        final (offset, text) = importInsertion;
        builder.addSimpleInsertion(offset, text);
      }
      builder.addSimpleReplacement(range.node(targetNode), replacement);
    });
  }

  (int, String)? _computeClockImportInsertion(
    CompilationUnit unit,
    String eol,
  ) {
    if (unit.directives.any((d) => d is PartOfDirective)) {
      return null;
    }

    final imports = unit.directives.whereType<ImportDirective>().toList();
    for (final directive in imports) {
      if (directive.uri.stringValue == _clockImportUri) {
        return null;
      }
    }

    if (imports.isNotEmpty) {
      final dartImports = <ImportDirective>[];
      final packageImports = <ImportDirective>[];
      final relativeImports = <ImportDirective>[];

      for (final directive in imports) {
        final uri = directive.uri.stringValue ?? '';
        if (uri.startsWith('dart:')) {
          dartImports.add(directive);
        } else if (uri.startsWith('package:')) {
          packageImports.add(directive);
        } else {
          relativeImports.add(directive);
        }
      }

      if (packageImports.isNotEmpty) {
        for (final existing in packageImports) {
          final existingUri = existing.uri.stringValue;
          if (existingUri != null &&
              existingUri.compareTo(_clockImportUri) > 0) {
            return (existing.offset, '$_clockImportLine$eol');
          }
        }
        final lastPackageImport = packageImports.last;
        return (lastPackageImport.end, '$eol$_clockImportLine');
      }

      if (dartImports.isNotEmpty) {
        final lastDartImport = dartImports.last;
        return (lastDartImport.end, '$eol$eol$_clockImportLine');
      }

      if (relativeImports.isNotEmpty) {
        final firstRelativeImport = relativeImports.first;
        return (firstRelativeImport.offset, '$_clockImportLine$eol$eol');
      }
    }

    LibraryDirective? libraryDirective;
    for (final directive in unit.directives) {
      if (directive is LibraryDirective) {
        libraryDirective = directive;
      }
    }

    if (libraryDirective != null) {
      return (libraryDirective.end, '$eol$eol$_clockImportLine');
    }

    if (unit.directives.isNotEmpty || unit.declarations.isNotEmpty) {
      final firstNode = unit.directives.isNotEmpty
          ? unit.directives.first
          : unit.declarations.first;
      return (firstNode.offset, '$_clockImportLine$eol$eol');
    }

    return (0, '$_clockImportLine$eol');
  }
}
