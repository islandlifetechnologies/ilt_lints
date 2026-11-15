import 'package:jaspr/dom.dart' show RawText;
import 'package:jaspr/jaspr.dart';

import '../models/custom_lint_config.dart';
import 'inline_code_text.dart';
import 'site_layout.dart';

/// Renders an individual linter rule page modeled after
/// `https://dart.dev/tools/linter-rules/avoid_print`.
class const LintDetailPage({
  super.key,
  final CustomLintRule? nextRule,
  final CustomLintRule? previousRule,
  required final String rootPrefix,
  required final CustomLintRule rule,
  required final List<CustomLintRule> rules,
  required final String siteTitle,
}) extends StatelessComponent {
  static const _checkCircleSvg =
      '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true">'
      '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>'
      '<polyline points="22 4 12 14.01 9 11.01"/>'
      '</svg>';

  static const _copyIconSvg =
      '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true">'
      '<rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>'
      '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>'
      '</svg>';

  static const _fixWrenchSvg =
      '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true">'
      '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77'
      'a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91'
      'a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>'
      '</svg>';

  @override
  Component build(BuildContext context) {
    final indexHref = '${rootPrefix}index.html';

    return SiteLayout(
      activeRuleName: rule.name,
      breadcrumbs: [
        Component.element(
          children: const [Component.text('Tools')],
          classes: 'breadcrumb-item',
          tag: 'li',
        ),
        Component.element(
          children: [
            Component.element(
              attributes: {'href': indexHref},
              children: const [Component.text('Linter rules')],
              tag: 'a',
            ),
          ],
          classes: 'breadcrumb-item',
          tag: 'li',
        ),
        Component.element(
          children: [Component.text(rule.name)],
          classes: 'breadcrumb-item active',
          tag: 'li',
        ),
      ],
      child: Component.element(
        children: [
          _buildRuleHeader(),
          _buildDetailsSection(),
          _buildExamplesSection(),
          _buildEnableSection(),
          _buildPrevNextNav(),
        ],
        classes: 'rule-detail-content',
        tag: 'div',
      ),
      rootPrefix: rootPrefix,
      rules: rules,
      siteTitle: siteTitle,
    );
  }

  Component _buildCodeExampleBlock({
    required bool isGood,
    required String snippet,
  }) {
    final kindLabel = isGood ? 'GOOD' : 'BAD';
    final cardClass = isGood ? 'code-card good-card' : 'code-card bad-card';
    final headerClass = isGood
        ? 'code-block-header good-header'
        : 'code-block-header bad-header';
    final preClass = isGood ? 'code-block good-code' : 'code-block bad-code';

    return Component.element(
      children: [
        Component.element(
          children: [
            Component.element(
              children: [Component.text('$kindLabel:')],
              classes: isGood ? 'example-label good' : 'example-label bad',
              tag: 'span',
            ),
            Component.element(
              attributes: {
                'aria-label': 'Copy $kindLabel Dart example',
                'type': 'button',
              },
              children: const [RawText(_copyIconSvg), Component.text(' Copy')],
              classes: 'copy-code-btn',
              tag: 'button',
            ),
          ],
          classes: headerClass,
          tag: 'div',
        ),
        Component.element(
          children: [
            Component.element(
              children: [Component.text(snippet)],
              classes: 'language-dart',
              tag: 'code',
            ),
          ],
          classes: preClass,
          tag: 'pre',
        ),
      ],
      classes: cardClass,
      tag: 'div',
    );
  }

  Component _buildDetailsSection() => Component.element(
    children: [
      Component.element(
        children: const [Component.text('Details')],
        id: 'details',
        tag: 'h2',
      ),
      Component.element(
        children: [
          Component.element(
            children: const [Component.text('DO ')],
            classes: 'do-keyword',
            tag: 'strong',
          ),
          InlineCodeText(content: _stripLeadingDo(rule.doStatement)),
        ],
        classes: 'do-guideline-paragraph',
        tag: 'p',
      ),
      Component.element(
        children: [InlineCodeText(content: rule.description)],
        classes: 'rule-description-paragraph',
        tag: 'p',
      ),
    ],
    classes: 'doc-section',
    tag: 'section',
  );

  Component _buildEnableSection() => Component.element(
    children: [
      Component.element(
        children: const [Component.text('How to enable')],
        id: 'enable',
        tag: 'h2',
      ),
      Component.element(
        children: [
          InlineCodeText(
            content:
                'To enable the `${rule.name}` rule, add it to your '
                '`analysis_options.yaml` file:',
          ),
        ],
        tag: 'p',
      ),
      Component.element(
        children: [
          Component.element(
            children: [
              Component.element(
                children: const [Component.text('analysis_options.yaml')],
                classes: 'code-block-title',
                tag: 'span',
              ),
              Component.element(
                attributes: const {
                  'aria-label': 'Copy analysis_options.yaml configuration',
                  'type': 'button',
                },
                children: const [
                  RawText(_copyIconSvg),
                  Component.text(' Copy'),
                ],
                classes: 'copy-code-btn',
                tag: 'button',
              ),
            ],
            classes: 'code-block-header yaml-header',
            tag: 'div',
          ),
          Component.element(
            children: [
              Component.element(
                children: [Component.text(rule.enable.trimRight())],
                classes: 'language-yaml',
                tag: 'code',
              ),
            ],
            classes: 'code-block yaml-code',
            tag: 'pre',
          ),
        ],
        classes: 'code-card',
        tag: 'div',
      ),
    ],
    classes: 'doc-section',
    tag: 'section',
  );

  Component _buildExamplesSection() => Component.element(
    children: [
      Component.element(
        children: const [Component.text('Examples')],
        id: 'examples',
        tag: 'h2',
      ),
      for (final badSnippet in rule.bad)
        _buildCodeExampleBlock(isGood: false, snippet: badSnippet),
      for (final goodSnippet in rule.good)
        _buildCodeExampleBlock(isGood: true, snippet: goodSnippet),
    ],
    classes: 'doc-section',
    tag: 'section',
  );

  Component _buildPrevNextNav() => Component.element(
    attributes: const {'aria-label': 'Rule pagination'},
    children: [
      if (previousRule != null)
        Component.element(
          attributes: {
            'href': '${rootPrefix}linter-rules/${previousRule!.name}.html',
          },
          children: [
            Component.element(
              children: const [Component.text('← Previous rule')],
              classes: 'page-nav-label',
              tag: 'span',
            ),
            Component.element(
              children: [Component.text(previousRule!.name)],
              classes: 'page-nav-rule',
              tag: 'code',
            ),
          ],
          classes: 'page-nav-card prev',
          tag: 'a',
        )
      else
        Component.element(
          children: const [],
          classes: 'page-nav-spacer',
          tag: 'div',
        ),
      if (nextRule != null)
        Component.element(
          attributes: {
            'href': '${rootPrefix}linter-rules/${nextRule!.name}.html',
          },
          children: [
            Component.element(
              children: const [Component.text('Next rule →')],
              classes: 'page-nav-label',
              tag: 'span',
            ),
            Component.element(
              children: [Component.text(nextRule!.name)],
              classes: 'page-nav-rule',
              tag: 'code',
            ),
          ],
          classes: 'page-nav-card next',
          tag: 'a',
        ),
    ],
    classes: 'page-pagination',
    tag: 'nav',
  );

  Component _buildRuleHeader() => Component.element(
    children: [
      Component.element(
        children: [
          Component.element(
            children: [
              Component.element(
                children: [Component.text(rule.name)],
                classes: 'rule-heading-code',
                tag: 'code',
              ),
            ],
            classes: 'page-title rule-page-title',
            tag: 'h1',
          ),
          Component.element(
            attributes: {
              'aria-label': 'Copy rule name ${rule.name}',
              'data-copy': rule.name,
              'title': 'Copy ${rule.name}',
              'type': 'button',
            },
            children: const [RawText(_copyIconSvg)],
            classes: 'icon-copy-btn large',
            tag: 'button',
          ),
        ],
        classes: 'rule-title-row',
        tag: 'div',
      ),
      Component.element(
        children: [
          Component.element(
            children: const [
              RawText(_checkCircleSvg),
              Component.text(' Stable'),
            ],
            classes: 'meta-pill status-stable',
            tag: 'span',
          ),
          if (rule.quickFix)
            Component.element(
              attributes: const {
                'title': 'Has an automated quick fix via dart fix or CLI',
              },
              children: const [
                RawText(_fixWrenchSvg),
                Component.text(' Fix available'),
              ],
              classes: 'meta-pill status-fix',
              tag: 'span',
            )
          else
            Component.element(
              children: const [Component.text('No quick fix')],
              classes: 'meta-pill status-muted',
              tag: 'span',
            ),
        ],
        classes: 'rule-meta-bar',
        tag: 'div',
      ),
      Component.element(
        children: [InlineCodeText(content: rule.doStatement)],
        classes: 'page-lead',
        tag: 'p',
      ),
    ],
    classes: 'hero-header rule-hero-header',
    tag: 'header',
  );

  String _stripLeadingDo(String text) {
    final trimmed = text.trim();
    if (trimmed.toLowerCase().startsWith('do ')) {
      final remainder = trimmed.substring(3).trimLeft();
      if (remainder.isNotEmpty) {
        return remainder[0].toLowerCase() + remainder.substring(1);
      }
    }
    if (trimmed.isNotEmpty) {
      return trimmed[0].toLowerCase() + trimmed.substring(1);
    }
    return trimmed;
  }
}
