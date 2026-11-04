import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../rules/export_library.dart';

/// A quick fix that adds missing `export` directives to a configured exporter
/// library file in alphabetical order.
class ExportLibraryFix extends ResolvedCorrectionProducer {
  ExportLibraryFix({
    required super.context,
    List<ExportLibraryOption>? options,
  }) : _optionsOverride = options;

  static const _fixKind = FixKind(
    'dart.fix.exportLibrary',
    DartFixKindPriority.standard,
    'Export missing library files',
  );

  final List<ExportLibraryOption>? _optionsOverride;

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final analysisContext = unitResult.session.analysisContext;
    final currentFile = unitResult.session.resourceProvider.getFile(
      unitResult.path,
    );
    final missingUris = ExportLibrary.findMissingExports(
      file: currentFile,
      libraryUri: unitResult.libraryElement.uri,
      optionsFile: analysisContext.contextRoot.optionsFile,
      optionsOverride: _optionsOverride,
      unit: unitResult.unit,
    );
    if (missingUris.isEmpty) {
      return;
    }

    final eol = utils.endOfLine;
    final unit = unitResult.unit;
    final existingExports = unit.directives
        .whereType<ExportDirective>()
        .toList();

    if (existingExports.isNotEmpty) {
      final insertionsByOffset = <int, List<String>>{};
      final appendedExports = <String>[];

      for (final missingUri in missingUris) {
        final exportLine = "export '$missingUri';";
        ExportDirective? insertBefore;
        for (final existing in existingExports) {
          final existingUri = existing.uri.stringValue;
          if (existingUri != null && existingUri.compareTo(missingUri) > 0) {
            insertBefore = existing;
            break;
          }
        }
        if (insertBefore != null) {
          insertionsByOffset
              .putIfAbsent(insertBefore.offset, () => [])
              .add('$exportLine$eol');
        } else {
          appendedExports.add(exportLine);
        }
      }

      if (appendedExports.isNotEmpty) {
        final lastExport = existingExports.last;
        insertionsByOffset
            .putIfAbsent(lastExport.end, () => [])
            .add('$eol${appendedExports.join(eol)}');
      }

      await builder.addDartFileEdit(file, (builder) {
        final sortedOffsets = insertionsByOffset.keys.toList()..sort();
        for (final offset in sortedOffsets) {
          builder.addSimpleInsertion(
            offset,
            insertionsByOffset[offset]!.join(),
          );
        }
      });
      return;
    }

    final exportLines = [for (final uri in missingUris) "export '$uri';"];
    Directive? anchorDirective;
    for (final directive in unit.directives) {
      if (directive is LibraryDirective || directive is ImportDirective) {
        anchorDirective = directive;
      }
    }

    await builder.addDartFileEdit(file, (builder) {
      if (anchorDirective != null) {
        builder.addSimpleInsertion(
          anchorDirective.end,
          '$eol$eol${exportLines.join(eol)}',
        );
      } else if (unit.directives.isNotEmpty || unit.declarations.isNotEmpty) {
        final firstNode = unit.directives.isNotEmpty
            ? unit.directives.first
            : unit.declarations.first;
        builder.addSimpleInsertion(
          firstNode.offset,
          '${exportLines.join(eol)}$eol$eol',
        );
      } else {
        final content = unitResult.content;
        if (content.isEmpty) {
          builder.addSimpleInsertion(0, '${exportLines.join(eol)}$eol');
        } else {
          final prefix = content.endsWith('\n') ? '' : eol;
          builder.addSimpleInsertion(
            content.length,
            '$prefix${exportLines.join(eol)}$eol',
          );
        }
      }
    });
  }
}

