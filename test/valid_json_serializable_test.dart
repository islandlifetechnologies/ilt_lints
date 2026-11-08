// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ilt_lints/ilt_lints.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ValidJsonSerializableTest);
  });
}

@reflectiveTest
class ValidJsonSerializableTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ValidJsonSerializable();
    super.setUp();
  }

  Future<void> test_bothFalseNoDiagnostics() async {
    await assertNoDiagnostics(r'''
class JsonSerializable {
  const JsonSerializable({bool createFactory = true, bool createToJson = true});
}

@JsonSerializable(createFactory: false, createToJson: false)
class User {
  final String name;

  User(this.name);
}
''');
  }

  Future<void> test_createFactoryFalseOnlyRequiresToJson() async {
    await assertDiagnostics(
      r'''
class JsonSerializable {
  const JsonSerializable({bool createFactory = true, bool createToJson = true});
}

@JsonSerializable(createFactory: false)
class User {
  final String name;

  User(this.name);
}
''',
      [lint(155, 4)],
    );

    newFile(testFile.path, r'''
class JsonSerializable {
  const JsonSerializable({bool createFactory = true, bool createToJson = true});
}

@JsonSerializable(createFactory: false)
class User {
  final String name;

  User(this.name);

  Map<String, dynamic> toJson() => _$UserToJson(this);
}

Map<String, dynamic> _$UserToJson(User instance) => {'name': instance.name};
''');
    await assertNoDiagnosticsInFile(testFile.path);
  }

  Future<void> test_createToJsonFalseOnlyRequiresFromJson() async {
    await assertDiagnostics(
      r'''
class JsonSerializable {
  const JsonSerializable({bool createFactory = true, bool createToJson = true});
}

@JsonSerializable(createToJson: false)
class User {
  final String name;

  User(this.name);
}
''',
      [lint(154, 4)],
    );

    newFile(testFile.path, r'''
class JsonSerializable {
  const JsonSerializable({bool createFactory = true, bool createToJson = true});
}

@JsonSerializable(createToJson: false)
class User {
  final String name;

  User(this.name);

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

User _$UserFromJson(Map<String, dynamic> json) => User(json['name'] as String);
''');
    await assertNoDiagnosticsInFile(testFile.path);
  }

  Future<void> test_missingFromJsonAndToJsonFlagsDiagnostic() async {
    await assertDiagnostics(
      r'''
class JsonSerializable {
  const JsonSerializable();
}

@JsonSerializable()
class User {
  final String name;

  User(this.name);
}
''',
      [lint(82, 4)],
    );
  }

  Future<void> test_quickFixAddsFactoryAndToJson() async {
    const original = r'''
class JsonSerializable {
  const JsonSerializable();
}

@JsonSerializable()
class User {
  final String name;

  User(this.name);
}
''';

    final fixed = await _applyFix(original);
    expect(
      fixed,
      contains(
        r'factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);',
      ),
    );
    expect(
      fixed,
      contains(r'Map<String, dynamic> toJson() => _$UserToJson(this);'),
    );
  }

  Future<void> test_quickFixUpdatesInvalidFromJsonOrToJson() async {
    const original = r'''
class JsonSerializable {
  const JsonSerializable();
}

@JsonSerializable()
class User {
  final String name;

  User(this.name);

  factory User.fromJson(Map<String, dynamic> json) => User('');

  Map<String, dynamic> toJson() => {};
}
''';

    final fixed = await _applyFix(original);
    expect(
      fixed,
      contains(
        r'factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);',
      ),
    );
    expect(
      fixed,
      contains(r'Map<String, dynamic> toJson() => _$UserToJson(this);'),
    );
    expect(fixed, isNot(contains("User('')")));
  }

  Future<void> test_quickFixUsesSimplifiedFactoryForPrimaryConstructor() async {
    const original = r'''
class JsonSerializable {
  const JsonSerializable();
}

@JsonSerializable()
class User(final String name) {
}
''';

    final fixed = await _applyFix(original);
    expect(
      fixed,
      contains(
        r'factory fromJson(Map<String, dynamic> json) => _$UserFromJson(json);',
      ),
    );
    expect(fixed, isNot(contains('factory User.fromJson')));
    expect(
      fixed,
      contains(r'Map<String, dynamic> toJson() => _$UserToJson(this);'),
    );
  }

  Future<void> test_validClassWithFactoryAndToJson() async {
    await assertNoDiagnostics(r'''
class JsonSerializable {
  const JsonSerializable();
}

@JsonSerializable()
class User {
  final String name;

  User(this.name);

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);
}

User _$UserFromJson(Map<String, dynamic> json) => User(json['name'] as String);
Map<String, dynamic> _$UserToJson(User instance) => {'name': instance.name};
''');
  }

  Future<void> test_validClassWithStaticFromJson() async {
    await assertNoDiagnostics(r'''
class JsonSerializable {
  const JsonSerializable();
}

@JsonSerializable()
class User {
  final String name;

  User(this.name);

  static User fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);
}

User _$UserFromJson(Map<String, dynamic> json) => User(json['name'] as String);
Map<String, dynamic> _$UserToJson(User instance) => {'name': instance.name};
''');
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == ValidJsonSerializable.code)
        .toList();
    expect(diagnostics, isNotEmpty);

    final diagnostic = diagnostics.first;
    final context = CorrectionProducerContext.createResolved(
      diagnostic: diagnostic,
      libraryResult: libraryResult,
      selectionLength: diagnostic.length,
      selectionOffset: diagnostic.offset,
      unitResult: unitResult,
    );
    final producer = ValidJsonSerializableFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
