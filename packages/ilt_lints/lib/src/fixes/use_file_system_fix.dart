import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/use_file_system.dart';

/// A quick fix for [UseFileSystem] that replaces `dart:io` `File`, `Directory`,
/// `FileSystemEntity`, and `Link` usages with the zone-aware `fs` accessor from
/// `package:io_ext/io_ext.dart` (for example, `File(path)` becomes
/// `fs.file(path)` and `Directory.systemTemp` becomes
/// `fs.systemTempDirectory`).  Tests can then override `fs` using
/// `withFileSystem`.  Imports are updated accordingly: `dart:io` no longer
/// provides `File`, `Directory`, `FileSystemEntity`, or `Link`, `package:file`
/// provides the types when still referenced, and `package:io_ext` provides
/// `fs`.
class UseFileSystemFix({required super.context})
    extends ResolvedCorrectionProducer {
  static const _fileImportUri = 'package:file/file.dart';

  static const _fixKind = FixKind(
    'dart.fix.useFileSystem',
    DartFixKindPriority.standard,
    'Use fs from package:io_ext',
  );

  static const _ioExtImportUri = 'package:io_ext/io_ext.dart';

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

    final callRewrites = <AstNode, String>{};
    final prefixRemovals = <SourceRange>[];

    final namedTypes = _collectFlaggedNamedTypes(unit);
    for (final namedType in namedTypes) {
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

    for (final callNode in _collectOutermostCalls(unit)) {
      final rewritten = UseFileSystem.rewriteCallOrAccess(
        callNode,
        fsAccess: 'fs',
        getNodeText: (n) => utils.getRangeText(range.node(n)),
      );
      if (rewritten != null) {
        callRewrites[callNode] = rewritten;
      }
    }

    await builder.addDartFileEdit(file, (editBuilder) {
      _applyImportsEdit(
        editBuilder,
        eol: eol,
        needsFileImport: namedTypes.isNotEmpty,
        unit: unit,
      );

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
    required bool needsFileImport,
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
    var hasIoExtImport = false;

    for (final directive in imports) {
      final uri = directive.uri.stringValue ?? '';
      if (uri == _fileImportUri) {
        hasFileImport = true;
      } else if (uri.startsWith('package:io_ext/') ||
          uri == 'package:file_ext/file_ext.dart') {
        hasIoExtImport = true;
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

    if (needsFileImport && !hasFileImport) {
      packageImportEntries.add((_fileImportUri, "import '$_fileImportUri';"));
    }
    if (!hasIoExtImport) {
      packageImportEntries.add((_ioExtImportUri, "import '$_ioExtImportUri';"));
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

class _FlaggedNamedTypeCollector() extends RecursiveAstVisitor<void> {
  final nodes = <NamedType>[];

  @override
  void visitNamedType(NamedType node) {
    if (UseFileSystem.isFileSystemNamedType(node)) {
      nodes.add(node);
    }
    super.visitNamedType(node);
  }
}

class _OtherDartIoUsageChecker(final Set<String> knownDartIoNames)
    extends RecursiveAstVisitor<void> {
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

class _OutermostCallCollector() extends RecursiveAstVisitor<void> {
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
