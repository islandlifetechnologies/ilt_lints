import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:path/path.dart' as p;

/// Result of analyzing a [ClassDeclaration] for [ValidJsonSerializable].
class ValidJsonSerializableAnalysis {
  const ValidJsonSerializableAnalysis({
    required this.className,
    required this.classNameToken,
    required this.classNode,
    required this.existingFromJson,
    required this.existingToJson,
    this.expectedPartUri,
    required this.fromJsonFunctionName,
    required this.hasPrimaryConstructor,
    required this.needsFromJson,
    this.needsPartDirective = false,
    required this.needsToJson,
    required this.toJsonFunctionName,
  });

  final String className;
  final Token classNameToken;
  final ClassDeclaration classNode;
  final ClassMember? existingFromJson;
  final MethodDeclaration? existingToJson;
  final String? expectedPartUri;
  final String fromJsonFunctionName;
  final bool hasPrimaryConstructor;
  final bool needsFromJson;
  final bool needsPartDirective;
  final bool needsToJson;
  final String toJsonFunctionName;

  bool get hasIssues => needsPartDirective || needsFromJson || needsToJson;
}

/// A lint rule that ensures classes annotated with `@JsonSerializable` define:
/// 1. A `part '<filename>.g.dart';` directive in the containing file.
/// 2. A `fromJson` factory (or static function) calling `_$<ClassName>FromJson`
///    when `createFactory: true` (or defaulted to true by JsonSerializable).
/// 3. A `toJson` method calling `_$<ClassName>ToJson` when `createToJson: true`
///    (or defaulted to true by JsonSerializable).
class ValidJsonSerializable extends AnalysisRule {
  ValidJsonSerializable()
    : super(
        description: 'Ensure @JsonSerializable classes include the generated part file and define valid fromJson and toJson methods calling the generated functions.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'valid_json_serializable',
    'Invalid @JsonSerializable class {0}: {1}.',
    correctionMessage: 'Try adding the generated part directive and adding or updating fromJson and toJson to call the generated functions.',
  );

  /// Analyzes [node] and returns a [ValidJsonSerializableAnalysis] if [node] is
  /// annotated with `@JsonSerializable`, or `null` otherwise.
  static ValidJsonSerializableAnalysis? analyzeClass(
    ClassDeclaration node, {
    String? filePath,
  }) {
    final config = _extractJsonSerializableConfig(node.metadata);
    if (config == null) {
      return null;
    }
    final (createFactory, createToJson) = config;
    final classNameToken = node.namePart.typeName;
    final className = classNameToken.lexeme;
    final hasPrimaryConstructor =
        node.namePart is PrimaryConstructorDeclaration;

    final unit = node.thisOrAncestorOfType<CompilationUnit>();
    final resolvedPath =
        filePath ??
        unit?.declaredFragment?.source.fullName ??
        unit?.declaredFragment?.source.shortName;
    final expectedPartUri = _expectedPartUri(resolvedPath);
    final hasValidPartDirective =
        expectedPartUri == null ||
        (unit != null &&
            unit.directives.whereType<PartDirective>().any(
              (d) => d.uri.stringValue == expectedPartUri,
            ));
    final needsPartDirective =
        (createFactory || createToJson) && !hasValidPartDirective;

    final body = node.body;
    final members = body is BlockClassBody
        ? body.members
        : const <ClassMember>[];

    ClassMember? existingFromJson;
    MethodDeclaration? existingToJson;

    for (final member in members) {
      if (member is ConstructorDeclaration) {
        if (member.name?.lexeme == 'fromJson') {
          existingFromJson ??= member;
        }
      } else if (member is MethodDeclaration) {
        if (!member.isGetter &&
            !member.isSetter &&
            !member.isOperator &&
            member.name.lexeme == 'fromJson') {
          existingFromJson ??= member;
        } else if (!member.isGetter &&
            !member.isSetter &&
            !member.isOperator &&
            member.name.lexeme == 'toJson') {
          existingToJson ??= member;
        }
      }
    }

    final generatedClassName = className.replaceFirst(RegExp('^_+'), '');
    final fromJsonGenerated = '_\$${generatedClassName}FromJson';
    var hasValidFromJson = false;
    if (existingFromJson is ConstructorDeclaration) {
      hasValidFromJson =
          existingFromJson.factoryKeyword != null &&
          _callsFunction(existingFromJson.body, fromJsonGenerated);
    } else if (existingFromJson is MethodDeclaration) {
      hasValidFromJson =
          existingFromJson.isStatic &&
          _callsFunction(existingFromJson.body, fromJsonGenerated);
    }

    final toJsonGenerated = '_\$${generatedClassName}ToJson';
    final hasValidToJson =
        existingToJson != null &&
        !existingToJson.isStatic &&
        _callsFunction(existingToJson.body, toJsonGenerated);

    return ValidJsonSerializableAnalysis(
      className: className,
      classNameToken: classNameToken,
      classNode: node,
      existingFromJson: existingFromJson,
      existingToJson: existingToJson,
      expectedPartUri: expectedPartUri,
      fromJsonFunctionName: fromJsonGenerated,
      hasPrimaryConstructor: hasPrimaryConstructor,
      needsFromJson: createFactory && !hasValidFromJson,
      needsPartDirective: needsPartDirective,
      needsToJson: createToJson && !hasValidToJson,
      toJsonFunctionName: toJsonGenerated,
    );
  }

  static bool _callsFunction(FunctionBody body, String functionName) {
    final finder = _FunctionCallFinder(functionName);
    body.accept(finder);
    return finder.found;
  }

  static String? _expectedPartUri(String? filePath) {
    if (filePath == null || filePath.isEmpty) {
      return null;
    }
    final baseName = p.basenameWithoutExtension(filePath);
    if (baseName.isEmpty) {
      return null;
    }
    return '$baseName.g.dart';
  }

  static (bool, bool)? _extractJsonSerializableConfig(
    NodeList<Annotation> metadata,
  ) {
    for (final annotation in metadata) {
      if (!_isJsonSerializableAnnotation(annotation)) {
        continue;
      }
      var createFactory = true;
      var createToJson = true;

      final constValue = annotation.elementAnnotation?.computeConstantValue();
      if (constValue != null) {
        final factoryField = constValue
            .getField('createFactory')
            ?.toBoolValue();
        if (factoryField != null) {
          createFactory = factoryField;
        }
        final toJsonField = constValue.getField('createToJson')?.toBoolValue();
        if (toJsonField != null) {
          createToJson = toJsonField;
        }
      }

      final arguments = annotation.arguments?.arguments;
      if (arguments != null) {
        for (final argument in arguments) {
          if (argument is! NamedArgument) {
            continue;
          }
          final name = argument.name.lexeme;
          final expr = argument.argumentExpression;
          if (name == 'createFactory' && expr is BooleanLiteral) {
            createFactory = expr.value;
          } else if (name == 'createToJson' && expr is BooleanLiteral) {
            createToJson = expr.value;
          }
        }
      }

      return (createFactory, createToJson);
    }
    return null;
  }

  static bool _isJsonSerializableAnnotation(Annotation annotation) {
    final identifier = annotation.name;
    if (identifier is SimpleIdentifier) {
      if (identifier.name == 'JsonSerializable') {
        return true;
      }
    } else if (identifier is PrefixedIdentifier) {
      if (identifier.identifier.name == 'JsonSerializable') {
        return true;
      }
    }
    final elementTypeName = annotation.elementAnnotation
        ?.computeConstantValue()
        ?.type
        ?.element
        ?.name;
    return elementTypeName == 'JsonSerializable';
  }

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final filePath =
        context.currentUnit?.file.path ?? context.definingUnit.file.path;
    final visitor = _Visitor(this, filePath: filePath);
    registry.addClassDeclaration(this, visitor);
  }
}

class _FunctionCallFinder extends RecursiveAstVisitor<void> {
  _FunctionCallFinder(this.targetName);

  final String targetName;
  var found = false;

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.function case SimpleIdentifier(:final name)) {
      if (name == targetName) {
        found = true;
        return;
      }
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == targetName) {
      found = true;
      return;
    }
    super.visitMethodInvocation(node);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.filePath});

  final String filePath;
  final ValidJsonSerializable rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final analysis = ValidJsonSerializable.analyzeClass(
      node,
      filePath: filePath,
    );
    if (analysis == null || !analysis.hasIssues) {
      return;
    }

    final className = analysis.className;
    final problems = <String>[];
    if (analysis.needsPartDirective && analysis.expectedPartUri != null) {
      problems.add("missing \"part '${analysis.expectedPartUri}';\"");
    }
    if (analysis.needsFromJson) {
      problems.add(
        "missing valid 'fromJson' calling '${analysis.fromJsonFunctionName}'",
      );
    }
    if (analysis.needsToJson) {
      problems.add(
        "missing valid 'toJson' calling '${analysis.toJsonFunctionName}'",
      );
    }

    rule.reportAtToken(
      analysis.classNameToken,
      arguments: [className, problems.join(' and ')],
    );
  }
}
