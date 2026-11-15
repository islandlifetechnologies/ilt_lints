import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';

class const RuleFixEntry({
  required final ResolvedCorrectionProducer Function({
    required CorrectionProducerContext context,
  })
  fixGenerator,
  required final String name,
  required final AnalysisRule Function() ruleFactory,
});
