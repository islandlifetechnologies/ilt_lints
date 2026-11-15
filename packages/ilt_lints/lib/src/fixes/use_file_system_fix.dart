import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/sort_fields.dart';
import '../rules/sort_named_parameters.dart';
import '../rules/use_file_system.dart';

/// A quick fix for [UseFileSystem] that replaces `dart:io` `File`, `Directory`,
/// `FileSystemEntity`, and `Link` usages with `package:file/file.dart`'s
/// `FileSystem` (`fs` when `io_ext` is imported, `_fs` on classes, or `fs` on
/// top-level functions) and updates imports accordingly.
class UseFileSystemFix extends ResolvedCorrectionProducer {
  UseFileSystemFix({required super.context});

  static const _fileImportUri = 'package:file/file.dart';

  static const _fixKind = FixKind(
    'dart.fix.useFileSystem',
    DartFixKindPriority.standard,
    'Use FileSystem from package:file',
  );

  static const _localImportUri = 'package:file/local.dart';
  static const _metaImportUri = 'package:meta/meta.dart';

  static const _otherDartIoSymbols = {
    'BytesBuilder',
    'CompressionOptions',
    'ConnectionTask',
    'ContentType',
    'Cookie',
    'Datagram',
    'DetachedSocket',
    'FileLock',
    'FileMode',
    'FileStat',
    'FileSystemCreateEvent',
    'FileSystemDeleteEvent',
    'FileSystemEvent',
    'FileSystemException',
    'FileSystemModifyEvent',
    'FileSystemMoveEvent',
    'GZipCodec',
    'HeaderValue',
    'HttpClient',
    'HttpClientBasicCredentials',
    'HttpClientCredentials',
    'HttpClientDigestCredentials',
    'HttpClientRequest',
    'HttpClientResponse',
    'HttpConnectionInfo',
    'HttpConnectionsInfo',
    'HttpDate',
    'HttpException',
    'HttpHeaders',
    'HttpOverrides',
    'HttpRequest',
    'HttpResponse',
    'HttpServer',
    'HttpSession',
    'HttpStatus',
    'IOException',
    'IOSink',
    'InternetAddress',
    'InternetAddressType',
    'NetworkInterface',
    'OSError',
    'Platform',
    'Process',
    'ProcessException',
    'ProcessInfo',
    'ProcessResult',
    'ProcessSignal',
    'ProcessStartMode',
    'RandomAccessFile',
    'RawDatagramSocket',
    'RawSecureServerSocket',
    'RawSecureSocket',
    'RawServerSocket',
    'RawSocket',
    'RawSocketEvent',
    'RawSocketOption',
    'RawSynchronousSocket',
    'RawZLibFilter',
    'RedirectException',
    'RedirectInfo',
    'SecureServerSocket',
    'SecureSocket',
    'SecurityContext',
    'ServerSocket',
    'SignalException',
    'Socket',
    'SocketDirection',
    'SocketException',
    'SocketOption',
    'Stdin',
    'StdinException',
    'StdioType',
    'Stdout',
    'StdoutException',
    'SystemEncoding',
    'TlsException',
    'WebSocket',
    'WebSocketException',
    'WebSocketStatus',
    'WebSocketTransformer',
    'X509Certificate',
    'ZLibCodec',
    'ZLibDecoder',
    'ZLibEncoder',
    'ZLibOption',
    'exit',
    'exitCode',
    'gzip',
    'pid',
    'sleep',
    'stderr',
    'stdin',
    'stdout',
    'stdioType',
    'systemEncoding',
    'zlib',
  };

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final targetNode = UseFileSystem.findTargetNode(node);
    if (targetNode == null) {
      return;
    }

    final unit = unitResult.unit;
    final eol = utils.endOfLine;
    final hasIoExt = _isIoExtImported(unit);

    final analysisContext = unitResult.session.analysisContext;
    final currentFile = unitResult.session.resourceProvider.getFile(
      unitResult.path,
    );
    final optionsFile = analysisContext.contextRoot.optionsFile;
    final requiredFirst = SortNamedParameters.readOptions(
      currentFile,
      optionsFile: optionsFile,
    ).requiredFirst;
    final finalFirst = SortFields.readOptions(
      currentFile,
      optionsFile: optionsFile,
    ).finalFirst;

    var needsLocalFileSystem = false;
    var needsVisibleForTesting = false;

    final enclosingClass = targetNode.thisOrAncestorOfType<ClassDeclaration>();
    final enclosingMethod = targetNode
        .thisOrAncestorOfType<MethodDeclaration>();
    final enclosingFunction = targetNode
        .thisOrAncestorOfType<FunctionDeclaration>();

    final callRewrites = <AstNode, String>{};
    final prefixRemovals = <SourceRange>[];

    for (final namedType in _collectFlaggedNamedTypes(unit)) {
      final importPrefix = namedType.importPrefix;
      if (importPrefix != null) {
        prefixRemovals.add(
          range.startOffsetEndOffset(
            importPrefix.offset,
            namedType.name.offset,
          ),
        );
      }
    }

    void collectRewritesIn(AstNode scope, String fsAccess) {
      for (final callNode in _collectOutermostCalls(scope)) {
        final rewritten = UseFileSystem.rewriteCallOrAccess(
          callNode,
          fsAccess: fsAccess,
          getNodeText: (n) => utils.getRangeText(range.node(n)),
        );
        if (rewritten != null) {
          callRewrites[callNode] = rewritten;
        }
      }
    }

    var addToPrimaryConstructor = false;
    var addToStandardClass = false;
    FormalParameterList? targetFunctionParams;

    if (enclosingClass != null &&
        (enclosingMethod == null || !enclosingMethod.isStatic)) {
      final instanceCalls = _collectOutermostCallsInClassInstance(
        enclosingClass,
      );
      if (hasIoExt) {
        for (final callNode in instanceCalls) {
          final rewritten = UseFileSystem.rewriteCallOrAccess(
            callNode,
            fsAccess: 'fs',
            getNodeText: (n) => utils.getRangeText(range.node(n)),
          );
          if (rewritten != null) {
            callRewrites[callNode] = rewritten;
          }
        }
      } else if (instanceCalls.isNotEmpty) {
        final existingFieldName = _existingClassFsName(enclosingClass);
        final fsName = existingFieldName ?? '_fs';
        for (final callNode in instanceCalls) {
          final rewritten = UseFileSystem.rewriteCallOrAccess(
            callNode,
            fsAccess: fsName,
            getNodeText: (n) => utils.getRangeText(range.node(n)),
          );
          if (rewritten != null) {
            callRewrites[callNode] = rewritten;
          }
        }
        if (existingFieldName == null) {
          needsLocalFileSystem = true;
          needsVisibleForTesting = true;
          if (enclosingClass.namePart is PrimaryConstructorDeclaration) {
            addToPrimaryConstructor = true;
          } else {
            addToStandardClass = true;
          }
        }
      }
    } else if (enclosingMethod != null && enclosingMethod.isStatic) {
      if (hasIoExt) {
        collectRewritesIn(enclosingMethod, 'fs');
      } else {
        final params = enclosingMethod.parameters;
        if (params != null) {
          final existingParam = _existingParamFsName(params);
          final fsName = existingParam ?? 'fs';
          collectRewritesIn(enclosingMethod, fsName);
          if (callRewrites.isNotEmpty && existingParam == null) {
            needsLocalFileSystem = true;
            needsVisibleForTesting = true;
            targetFunctionParams = params;
          }
        } else {
          collectRewritesIn(enclosingMethod, 'const LocalFileSystem()');
          if (callRewrites.isNotEmpty) {
            needsLocalFileSystem = true;
          }
        }
      }
    } else if (enclosingFunction != null) {
      if (hasIoExt) {
        collectRewritesIn(enclosingFunction, 'fs');
      } else {
        final params = enclosingFunction.functionExpression.parameters;
        if (params != null) {
          final existingParam = _existingParamFsName(params);
          final fsName = existingParam ?? 'fs';
          collectRewritesIn(enclosingFunction, fsName);
          if (callRewrites.isNotEmpty && existingParam == null) {
            needsLocalFileSystem = true;
            needsVisibleForTesting = true;
            targetFunctionParams = params;
          }
        } else {
          collectRewritesIn(enclosingFunction, 'const LocalFileSystem()');
          if (callRewrites.isNotEmpty) {
            needsLocalFileSystem = true;
          }
        }
      }
    } else if (UseFileSystem.isFileSystemCallOrAccess(targetNode)) {
      final fsAccess = hasIoExt ? 'fs' : 'const LocalFileSystem()';
      final rewritten = UseFileSystem.rewriteCallOrAccess(
        targetNode,
        fsAccess: fsAccess,
        getNodeText: (n) => utils.getRangeText(range.node(n)),
      );
      if (rewritten != null) {
        callRewrites[targetNode] = rewritten;
        if (!hasIoExt) {
          needsLocalFileSystem = true;
        }
      }
    }

    await builder.addDartFileEdit(file, (editBuilder) {
      _applyImportsEdit(
        editBuilder,
        eol: eol,
        needsLocalFileSystem: needsLocalFileSystem,
        needsVisibleForTesting: needsVisibleForTesting,
        unit: unit,
      );

      if (addToPrimaryConstructor && enclosingClass != null) {
        final primary =
            enclosingClass.namePart as PrimaryConstructorDeclaration;
        _insertNamedParameter(
          editBuilder,
          eol: eol,
          normalizedName: 'fs',
          parameterList: primary.formalParameters,
          parameterText: '@visibleForTesting final FileSystem _fs = const LocalFileSystem()',
          requiredFirst: requiredFirst,
        );
      } else if (addToStandardClass && enclosingClass != null) {
        _insertIntoStandardClass(
          editBuilder,
          classNode: enclosingClass,
          eol: eol,
          finalFirst: finalFirst,
          requiredFirst: requiredFirst,
        );
      } else if (targetFunctionParams != null) {
        _insertNamedParameter(
          editBuilder,
          eol: eol,
          normalizedName: 'fs',
          parameterList: targetFunctionParams,
          parameterText:
              '@visibleForTesting FileSystem fs = const LocalFileSystem()',
          requiredFirst: requiredFirst,
        );
      }

      for (final prefixRange in prefixRemovals) {
        editBuilder.addSimpleReplacement(prefixRange, '');
      }

      for (final entry in callRewrites.entries) {
        editBuilder.addSimpleReplacement(range.node(entry.key), entry.value);
      }
    });
  }

  void _applyImportsEdit(
    DartFileEditBuilder editBuilder, {
    required String eol,
    required bool needsLocalFileSystem,
    required bool needsVisibleForTesting,
    required CompilationUnit unit,
  }) {
    if (unit.directives.any((d) => d is PartOfDirective)) {
      return;
    }

    final imports = unit.directives.whereType<ImportDirective>().toList();
    final usesOtherDartIo = _usesOtherDartIoSymbols(unit);

    final dartImportEntries = <(String, String)>[];
    final packageImportEntries = <(String, String)>[];
    final relativeImportEntries = <(String, String)>[];

    var hasFileImport = false;
    var hasLocalImport = false;
    var hasMetaImport = false;

    for (final directive in imports) {
      final uri = directive.uri.stringValue ?? '';
      if (uri == _fileImportUri) {
        hasFileImport = true;
      } else if (uri == _localImportUri) {
        hasLocalImport = true;
      } else if (uri == _metaImportUri ||
          uri == 'package:flutter/foundation.dart' ||
          uri == 'package:flutter/material.dart' ||
          uri == 'package:flutter/widgets.dart') {
        hasMetaImport = true;
      }

      if (uri == 'dart:io') {
        if (usesOtherDartIo) {
          final updated = _buildDartIoImportWithHide(directive);
          if (updated != null) {
            dartImportEntries.add((uri, updated));
          }
        }
        continue;
      }

      final text = utils.getRangeText(range.node(directive));
      if (uri.startsWith('dart:')) {
        dartImportEntries.add((uri, text));
      } else if (uri.startsWith('package:')) {
        packageImportEntries.add((uri, text));
      } else {
        relativeImportEntries.add((uri, text));
      }
    }

    if (!hasFileImport) {
      packageImportEntries.add((_fileImportUri, "import '$_fileImportUri';"));
    }
    if (needsLocalFileSystem && !hasLocalImport) {
      packageImportEntries.add((_localImportUri, "import '$_localImportUri';"));
    }
    if (needsVisibleForTesting && !hasMetaImport) {
      packageImportEntries.add((_metaImportUri, "import '$_metaImportUri';"));
    }

    packageImportEntries.sort((a, b) => a.$1.compareTo(b.$1));

    final groups = <String>[
      if (dartImportEntries.isNotEmpty)
        dartImportEntries.map((e) => e.$2).join(eol),
      if (packageImportEntries.isNotEmpty)
        packageImportEntries.map((e) => e.$2).join(eol),
      if (relativeImportEntries.isNotEmpty)
        relativeImportEntries.map((e) => e.$2).join(eol),
    ];
    final newImportsBlock = groups.join('$eol$eol');

    if (imports.isNotEmpty) {
      final existingRange = range.startOffsetEndOffset(
        imports.first.offset,
        imports.last.end,
      );
      if (utils.getRangeText(existingRange) != newImportsBlock) {
        editBuilder.addSimpleReplacement(existingRange, newImportsBlock);
      }
      return;
    }

    if (newImportsBlock.isEmpty) {
      return;
    }

    LibraryDirective? libraryDirective;
    for (final directive in unit.directives) {
      if (directive is LibraryDirective) {
        libraryDirective = directive;
      }
    }

    if (libraryDirective != null) {
      editBuilder.addSimpleInsertion(
        libraryDirective.end,
        '$eol$eol$newImportsBlock',
      );
    } else if (unit.directives.isNotEmpty || unit.declarations.isNotEmpty) {
      final firstNode = unit.directives.isNotEmpty
          ? unit.directives.first
          : unit.declarations.first;
      editBuilder.addSimpleInsertion(
        firstNode.offset,
        '$newImportsBlock$eol$eol',
      );
    } else {
      editBuilder.addSimpleInsertion(0, '$newImportsBlock$eol');
    }
  }

  String? _buildDartIoImportWithHide(ImportDirective directive) {
    final prefixClause = directive.prefix != null
        ? ' as ${directive.prefix!.name}'
        : '';
    final hiddenNames = <String>{...UseFileSystem.targetTypeNames};
    final shownNames = <String>[];
    var hadShow = false;

    for (final combinator in directive.combinators) {
      if (combinator is HideCombinator) {
        for (final id in combinator.hiddenNames) {
          hiddenNames.add(id.name);
        }
      } else if (combinator is ShowCombinator) {
        hadShow = true;
        for (final id in combinator.shownNames) {
          if (!UseFileSystem.targetTypeNames.contains(id.name)) {
            shownNames.add(id.name);
          }
        }
      }
    }

    if (hadShow) {
      if (shownNames.isEmpty) {
        return null;
      }
      shownNames.sort();
      return "import 'dart:io'$prefixClause show ${shownNames.join(', ')};";
    }

    final sortedHidden = hiddenNames.toList()..sort();
    return "import 'dart:io'$prefixClause hide ${sortedHidden.join(', ')};";
  }

  List<NamedType> _collectFlaggedNamedTypes(CompilationUnit unit) {
    final collector = _FlaggedNamedTypeCollector();
    unit.accept(collector);
    return collector.nodes;
  }

  List<AstNode> _collectOutermostCalls(AstNode scope) {
    final collector = _OutermostCallCollector();
    scope.accept(collector);
    return collector.calls;
  }

  List<AstNode> _collectOutermostCallsInClassInstance(
    ClassDeclaration classNode,
  ) {
    final body = classNode.body;
    if (body is! BlockClassBody) {
      return const [];
    }
    final results = <AstNode>[];
    for (final member in body.members) {
      if (member is MethodDeclaration && member.isStatic) {
        continue;
      }
      if (member is FieldDeclaration && member.isStatic) {
        continue;
      }
      results.addAll(_collectOutermostCalls(member));
    }
    return results;
  }

  String? _existingClassFsName(ClassDeclaration classNode) {
    final namePart = classNode.namePart;
    if (namePart is PrimaryConstructorDeclaration) {
      final paramName = _existingParamFsName(namePart.formalParameters);
      if (paramName != null) {
        return paramName;
      }
    }
    final body = classNode.body;
    if (body is BlockClassBody) {
      for (final member in body.members) {
        if (member is FieldDeclaration && !member.isStatic) {
          for (final variable in member.fields.variables) {
            final name = variable.name.lexeme;
            if (name == '_fs' || name == 'fs') {
              return name;
            }
          }
        }
      }
    }
    return null;
  }

  String? _existingParamFsName(FormalParameterList parameterList) {
    for (final param in parameterList.parameters) {
      final name = param.name?.lexeme;
      if (name == '_fs' || name == 'fs') {
        return name;
      }
    }
    return null;
  }

  void _insertIntoStandardClass(
    DartFileEditBuilder editBuilder, {
    required ClassDeclaration classNode,
    required String eol,
    required bool finalFirst,
    required bool requiredFirst,
  }) {
    final body = classNode.body;
    if (body is! BlockClassBody) {
      return;
    }

    final classIndent = utils.getLinePrefix(classNode.offset);
    final memberIndent = '$classIndent  ';
    final className = classNode.namePart.typeName.lexeme;

    final generativeConstructors = body.members
        .whereType<ConstructorDeclaration>()
        .where(
          (c) => c.factoryKeyword == null && c.redirectedConstructor == null,
        )
        .toList();
    final existingFields = body.members.whereType<FieldDeclaration>().toList();

    const fieldLine = 'final FileSystem _fs;';
    const ctorParamText =
        '@visibleForTesting this._fs = const LocalFileSystem()';

    if (generativeConstructors.isEmpty && existingFields.isEmpty) {
      final ctorLine = '$className({$ctorParamText});';
      if (body.members.isEmpty) {
        editBuilder.addSimpleInsertion(
          body.leftBracket.end,
          '$eol$memberIndent$ctorLine$eol$eol$memberIndent$fieldLine$eol$classIndent',
        );
      } else {
        final firstMemberOffset = _startOffsetWithLeadingComments(
          body.members.first,
        );
        editBuilder.addSimpleInsertion(
          firstMemberOffset,
          '$ctorLine$eol$eol$memberIndent$fieldLine$eol$eol$memberIndent',
        );
      }
      return;
    }

    if (generativeConstructors.isEmpty) {
      final ctorLine = '$className({$ctorParamText});';
      final firstMemberOffset = _startOffsetWithLeadingComments(
        body.members.first,
      );
      editBuilder.addSimpleInsertion(
        firstMemberOffset,
        '$ctorLine$eol$eol$memberIndent',
      );
    } else {
      for (final ctor in generativeConstructors) {
        _insertNamedParameter(
          editBuilder,
          eol: eol,
          normalizedName: 'fs',
          parameterList: ctor.parameters,
          parameterText: ctorParamText,
          requiredFirst: requiredFirst,
        );
      }
    }

    // Insert `final FileSystem _fs;` in its sorted FieldScope.privateInstance
    // position.
    if (existingFields.isEmpty) {
      final lastCtor = generativeConstructors.last;
      editBuilder.addSimpleInsertion(
        lastCtor.end,
        '$eol$eol$memberIndent$fieldLine',
      );
      return;
    }

    FieldDeclaration? insertBeforeField;
    for (final field in existingFields) {
      final scope = FieldScope.of(field);
      if (scope != FieldScope.privateInstance) {
        continue;
      }
      final isFinal = field.fields.isFinal;
      final name = field.fields.variables.first.name.lexeme;
      if (finalFirst && !isFinal) {
        insertBeforeField = field;
        break;
      }
      if ((!finalFirst || isFinal) && name.compareTo('_fs') > 0) {
        insertBeforeField = field;
        break;
      }
    }

    if (insertBeforeField != null) {
      final offset = _startOffsetWithLeadingComments(insertBeforeField);
      editBuilder.addSimpleInsertion(offset, '$fieldLine$eol$memberIndent');
    } else {
      final lastField = existingFields.last;
      editBuilder.addSimpleInsertion(
        lastField.end,
        '$eol$memberIndent$fieldLine',
      );
    }
  }

  void _insertNamedParameter(
    DartFileEditBuilder editBuilder, {
    required String eol,
    required String normalizedName,
    required FormalParameterList parameterList,
    required String parameterText,
    required bool requiredFirst,
  }) {
    if (_existingParamFsName(parameterList) != null) {
      return;
    }

    final params = parameterList.parameters;
    final namedParams = params.where((p) => p.isNamed).toList();

    if (namedParams.isEmpty) {
      if (params.isEmpty) {
        editBuilder.addSimpleReplacement(
          range.node(parameterList),
          '({$parameterText})',
        );
      } else {
        final lastPositional = params.last;
        editBuilder.addSimpleInsertion(
          lastPositional.end,
          ', {$parameterText}',
        );
      }
      return;
    }

    FormalParameter? insertBefore;
    for (final existing in namedParams) {
      if (requiredFirst && existing.isRequiredNamed) {
        continue;
      }
      final rawName = existing.name?.lexeme;
      if (rawName == null) {
        continue;
      }
      final existingNormalized = SortNamedParameters.normalizeParameterName(
        rawName,
      );
      if (existingNormalized.compareTo(normalizedName) > 0) {
        insertBefore = existing;
        break;
      }
    }

    final lineInfo = unitResult.lineInfo;
    final isMultiline =
        lineInfo.getLocation(parameterList.leftParenthesis.offset).lineNumber !=
        lineInfo.getLocation(parameterList.rightParenthesis.offset).lineNumber;

    if (isMultiline) {
      if (insertBefore != null) {
        final targetOffset = _startOffsetWithLeadingComments(insertBefore);
        final indent = utils.getLinePrefix(targetOffset);
        editBuilder.addSimpleInsertion(
          targetOffset,
          '$parameterText,$eol$indent',
        );
      } else {
        final lastNamed = namedParams.last;
        final indent = utils.getLinePrefix(lastNamed.offset);
        final nextToken = lastNamed.endToken.next;
        if (nextToken != null && nextToken.lexeme == ',') {
          editBuilder.addSimpleInsertion(
            nextToken.end,
            '$eol$indent$parameterText,',
          );
        } else {
          editBuilder.addSimpleInsertion(
            lastNamed.end,
            ',$eol$indent$parameterText',
          );
        }
      }
    } else {
      if (insertBefore != null) {
        final targetOffset = _startOffsetWithLeadingComments(insertBefore);
        editBuilder.addSimpleInsertion(targetOffset, '$parameterText, ');
      } else {
        final lastNamed = namedParams.last;
        final nextToken = lastNamed.endToken.next;
        if (nextToken != null && nextToken.lexeme == ',') {
          editBuilder.addSimpleInsertion(nextToken.end, ' $parameterText,');
        } else {
          editBuilder.addSimpleInsertion(lastNamed.end, ', $parameterText');
        }
      }
    }
  }

  bool _isIoExtImported(CompilationUnit unit) {
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri != null && uri.startsWith('package:io_ext/')) {
        return true;
      }
    }
    return false;
  }

  int _startOffsetWithLeadingComments(AstNode item) {
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
    return startOffset;
  }

  bool _usesOtherDartIoSymbols(CompilationUnit unit) {
    final checker = _OtherDartIoUsageChecker(
      UseFileSystemFix._otherDartIoSymbols,
    );
    for (final declaration in unit.declarations) {
      declaration.accept(checker);
      if (checker.found) {
        return true;
      }
    }
    return false;
  }
}

class _FlaggedNamedTypeCollector extends RecursiveAstVisitor<void> {
  final nodes = <NamedType>[];

  @override
  void visitNamedType(NamedType node) {
    if (UseFileSystem.isFileSystemNamedType(node)) {
      nodes.add(node);
    }
    super.visitNamedType(node);
  }
}

class _OtherDartIoUsageChecker extends RecursiveAstVisitor<void> {
  _OtherDartIoUsageChecker(this.knownDartIoNames);

  final Set<String> knownDartIoNames;
  var found = false;

  @override
  void visitNamedType(NamedType node) {
    if (found) {
      return;
    }
    final name = node.name.lexeme;
    if (!UseFileSystem.targetTypeNames.contains(name)) {
      if (_isFromDartIo(node.element, name)) {
        found = true;
        return;
      }
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (found) {
      return;
    }
    final name = node.name;
    if (!UseFileSystem.targetTypeNames.contains(name)) {
      if (_isFromDartIo(node.element, name)) {
        found = true;
        return;
      }
    }
    super.visitSimpleIdentifier(node);
  }

  bool _isFromDartIo(Element? element, String identifierName) {
    if (element != null) {
      final enclosing = element.enclosingElement;
      if (enclosing is InterfaceElement &&
          UseFileSystem.targetTypeNames.contains(enclosing.name)) {
        return false;
      }
      final library = element.library;
      if (library != null) {
        final uri = library.uri.toString();
        return uri == 'dart:io';
      }
    }
    return knownDartIoNames.contains(identifierName);
  }
}

class _OutermostCallCollector extends RecursiveAstVisitor<void> {
  final calls = <AstNode>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (UseFileSystem.isFileSystemCallOrAccess(node)) {
      calls.add(node);
      return;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (UseFileSystem.isFileSystemCallOrAccess(node)) {
      calls.add(node);
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (UseFileSystem.isFileSystemCallOrAccess(node)) {
      calls.add(node);
      return;
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (UseFileSystem.isFileSystemCallOrAccess(node)) {
      calls.add(node);
      return;
    }
    super.visitPropertyAccess(node);
  }
}
