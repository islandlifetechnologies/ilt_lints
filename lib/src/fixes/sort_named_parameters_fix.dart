import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/sort_named_parameters.dart';

/// A quick fix that sorts non-ignored named parameters in a
/// [FormalParameterList] or named arguments in an [ArgumentList]
/// alphabetically (and with `required` parameters first in declarations when
/// `required_first` is enabled), leaving ignored names and positional
/// parameters/arguments in their existing positions.
class SortNamedParametersFix extends ResolvedCorrectionProducer {
  SortNamedParametersFix({
    required super.context,
    Iterable<String> ignore = const [],
    bool requiredFirst = false,
  })  : _extraIgnore = Set<String>.unmodifiable(ignore),
        _extraRequiredFirst = requiredFirst;

  static const _fixKind = FixKind(
    'dart.fix.sortNamedParameters',
    DartFixKindPriority.standard,
    'Sort named parameters alphabetically',
  );

  final Set<String> _extraIgnore;
  final bool _extraRequiredFirst;

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final targetNode = node.thisOrAncestorMatching(
      (n) => n is FormalParameterList || n is ArgumentList,
    );
    if (targetNode == null) {
      return;
    }

    final analysisContext = unitResult.session.analysisContext;
    final currentFile =
        unitResult.session.resourceProvider.getFile(unitResult.path);
    final fileOptions = SortNamedParameters.readOptions(
      currentFile,
      optionsFile: analysisContext.contextRoot.optionsFile,
    );
    final ignoredNames = {
      ..._extraIgnore,
      ...fileOptions.ignore,
    };
    final requiredFirst = _extraRequiredFirst || fileOptions.requiredFirst;

    final entries = <_SortableNamedItem>[];
    if (targetNode is FormalParameterList) {
      for (final parameter in targetNode.parameters) {
        if (!parameter.isNamed) {
          continue;
        }
        final nameToken = parameter.name;
        if (nameToken == null) {
          continue;
        }
        final rawName = nameToken.lexeme;
        final name = SortNamedParameters.normalizeParameterName(rawName);
        if (ignoredNames.contains(rawName) || ignoredNames.contains(name)) {
          continue;
        }
        final itemRange = _rangeForItem(parameter);
        entries.add(
          _SortableNamedItem(
            isRequired: parameter.isRequiredNamed,
            name: name,
            originalOrder: entries.length,
            range: itemRange,
            text: utils.getRangeText(itemRange),
          ),
        );
      }
    } else if (targetNode is ArgumentList) {
      for (final argument in targetNode.arguments) {
        if (argument is! NamedArgument) {
          continue;
        }
        final name = argument.name.lexeme;
        if (ignoredNames.contains(name)) {
          continue;
        }
        final itemRange = _rangeForItem(argument);
        entries.add(
          _SortableNamedItem(
            isRequired: false,
            name: name,
            originalOrder: entries.length,
            range: itemRange,
            text: utils.getRangeText(itemRange),
          ),
        );
      }
    }

    if (entries.length < 2) {
      return;
    }

    final sorted = List<_SortableNamedItem>.of(entries)
      ..sort((a, b) {
        if (requiredFirst && a.isRequired != b.isRequired) {
          return a.isRequired ? -1 : 1;
        }
        final cmp = a.name.compareTo(b.name);
        if (cmp != 0) {
          return cmp;
        }
        return a.originalOrder.compareTo(b.originalOrder);
      });

    await builder.addDartFileEdit(file, (builder) {
      for (var i = 0; i < entries.length; i++) {
        final target = entries[i];
        final replacement = sorted[i];
        if (target.text != replacement.text) {
          builder.addSimpleReplacement(target.range, replacement.text);
        }
      }
    });
  }

  SourceRange _rangeForItem(AstNode item) {
    final lineInfo = unitResult.lineInfo;
    final beginToken = item.beginToken;
    final previousToken = beginToken.previous;
    final prevEndLine = previousToken != null
        ? lineInfo.getLocation(previousToken.end).lineNumber
        : 0;

    var startOffset = item.offset;
    Token? comment = beginToken.precedingComments;
    while (comment != null) {
      final commentLine = lineInfo.getLocation(comment.offset).lineNumber;
      if (commentLine > prevEndLine) {
        startOffset = comment.offset;
        break;
      }
      comment = comment.next;
    }

    return range.startOffsetEndOffset(startOffset, item.end);
  }
}

class _SortableNamedItem {
  const _SortableNamedItem({
    required this.isRequired,
    required this.name,
    required this.originalOrder,
    required this.range,
    required this.text,
  });

  final bool isRequired;
  final String name;
  final int originalOrder;
  final SourceRange range;
  final String text;
}
