import 'package:jaspr/dom.dart' show RawText;
import 'package:jaspr/jaspr.dart';

import '../models/custom_lint_config.dart';
import 'inline_code_text.dart';
import 'site_layout.dart';

/// Renders the main Linter Rules directory page modeled after
/// `https://dart.dev/tools/linter-rules`.
class const LintIndexPage({
  super.key,
  required final String rootPrefix,
  required final List<CustomLintRule> rules,
  required final String siteTitle,
}) extends StatelessComponent {
  static const _copyIconSvg =
      '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true">'
      '<rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>'
      '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>'
      '</svg>';

  static const _fixWrenchSvg =
      '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true">'
      '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77'
      'a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91'
      'a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>'
      '</svg>';

  @override
  Component build(BuildContext context) {
    final quickFixCount = rules.where((r) => r.quickFix).length;

    return SiteLayout(
      breadcrumbs: [
        Component.element(
          children: const [Component.text('Tools')],
          classes: 'breadcrumb-item',
          tag: 'li',
        ),
        Component.element(
          children: const [Component.text('Linter rules')],
          classes: 'breadcrumb-item active',
          tag: 'li',
        ),
      ],
      child: Component.element(
        children: [
          _buildHeroSection(quickFixCount),
          _buildOverviewSection(),
          _buildEnablingSection(),
          _buildRulesListSection(quickFixCount),
        ],
        classes: 'index-page-content',
        tag: 'div',
      ),
      rootPrefix: rootPrefix,
      rules: rules,
      siteTitle: siteTitle,
    );
  }

  Component _buildEnablingSection() {
    final sampleRulesYaml = [
      'plugins:',
      '  ilt_lints:',
      '    version: ^2.0.0',
      '    diagnostics:',
      for (final rule in rules) '      ${rule.name}: true',
    ].join('\n');

    return Component.element(
      children: [
        Component.element(
          children: const [Component.text('Enabling rules')],
          id: 'enabling-rules',
          tag: 'h2',
        ),
        Component.element(
          children: const [
            InlineCodeText(
              content:
                  'To enable custom lint rules in your project, configure the '
                  'plugin diagnostics in your `analysis_options.yaml` file:',
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
                    'aria-label': 'Copy YAML configuration',
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
                  children: [Component.text(sampleRulesYaml)],
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
  }

  Component _buildHeroSection(int quickFixCount) => Component.element(
    children: [
      Component.element(
        children: const [Component.text('Linter rules')],
        classes: 'page-title',
        tag: 'h1',
      ),
      Component.element(
        children: const [
          Component.text(
            'Enforce consistent style, catch potential bugs early, and keep '
            'your Dart codebase maintainable with automated lint rules and '
            'quick fixes.',
          ),
        ],
        classes: 'page-lead',
        tag: 'p',
      ),
      Component.element(
        children: [
          Component.element(
            children: [Component.text('${rules.length} Total Rules')],
            classes: 'meta-pill status-stable',
            tag: 'span',
          ),
          Component.element(
            children: [
              const RawText(_fixWrenchSvg),
              Component.text(' $quickFixCount with Quick Fix'),
            ],
            classes: 'meta-pill status-fix',
            tag: 'span',
          ),
        ],
        classes: 'rule-meta-bar',
        tag: 'div',
      ),
    ],
    classes: 'hero-header',
    tag: 'header',
  );

  Component _buildOverviewSection() => Component.element(
    children: [
      Component.element(
        children: const [Component.text('Overview')],
        id: 'overview',
        tag: 'h2',
      ),
      Component.element(
        children: const [
          InlineCodeText(
            content:
                'Each linter rule below documents what the rule checks, why '
                'it matters, `BAD` and `GOOD` Dart code examples, and how to '
                'enable or configure the rule in `analysis_options.yaml`.',
          ),
        ],
        tag: 'p',
      ),
      Component.element(
        children: [
          Component.element(
            children: const [
              RawText(_fixWrenchSvg),
              Component.text(' Quick fixes: '),
            ],
            tag: 'strong',
          ),
          const InlineCodeText(
            content:
                'Rules marked with the quick fix badge include an automated '
                'fix that can be applied directly in your IDE or via the CLI.',
          ),
        ],
        classes: 'callout-box info-callout',
        tag: 'div',
      ),
    ],
    classes: 'doc-section',
    tag: 'section',
  );

  Component _buildRuleCard(CustomLintRule rule) {
    final detailHref = '${rootPrefix}linter-rules/${rule.name}.html';
    final searchText = '${rule.name} ${rule.doStatement} ${rule.description}'
        .toLowerCase();

    return Component.element(
      attributes: {
        'data-quick-fix': rule.quickFix ? 'true' : 'false',
        'data-rule-name': rule.name,
        'data-search-text': searchText,
      },
      children: [
        Component.element(
          children: [
            Component.element(
              children: [
                Component.element(
                  attributes: {'href': detailHref},
                  children: [
                    Component.element(
                      children: [Component.text(rule.name)],
                      classes: 'rule-card-name',
                      tag: 'code',
                    ),
                  ],
                  classes: 'rule-card-link',
                  tag: 'a',
                ),
                Component.element(
                  attributes: {
                    'aria-label': 'Copy rule name ${rule.name}',
                    'data-copy': rule.name,
                    'title': 'Copy ${rule.name}',
                    'type': 'button',
                  },
                  children: const [RawText(_copyIconSvg)],
                  classes: 'icon-copy-btn',
                  tag: 'button',
                ),
              ],
              classes: 'rule-card-title-group',
              tag: 'div',
            ),
            Component.element(
              children: [
                if (rule.quickFix)
                  Component.element(
                    attributes: const {'title': 'Has an automated quick fix'},
                    children: const [
                      RawText(_fixWrenchSvg),
                      Component.text(' Fix available'),
                    ],
                    classes: 'badge badge-fix',
                    tag: 'span',
                  ),
                Component.element(
                  attributes: {'href': detailHref},
                  children: const [Component.text('View details →')],
                  classes: 'rule-details-link',
                  tag: 'a',
                ),
              ],
              classes: 'rule-card-badges',
              tag: 'div',
            ),
          ],
          classes: 'rule-card-header',
          tag: 'div',
        ),
        Component.element(
          children: [
            Component.element(
              children: const [Component.text('DO ')],
              classes: 'do-prefix',
              tag: 'strong',
            ),
            InlineCodeText(content: _stripLeadingDo(rule.doStatement)),
          ],
          classes: 'rule-card-do',
          tag: 'p',
        ),
        Component.element(
          children: [InlineCodeText(content: rule.description)],
          classes: 'rule-card-description',
          tag: 'p',
        ),
      ],
      classes: 'rule-card',
      id: 'rule-${rule.name}',
      tag: 'div',
    );
  }

  Component _buildRulesListSection(int quickFixCount) => Component.element(
    children: [
      Component.element(
        children: const [Component.text('All linter rules')],
        id: 'all-linter-rules',
        tag: 'h2',
      ),
      Component.element(
        children: [
          Component.element(
            children: [
              Component.element(
                attributes: const {
                  'aria-label': 'Filter linter rules by name or description',
                  'autocomplete': 'off',
                  'placeholder': 'Filter rules by name or keyword...',
                  'type': 'search',
                },
                classes: 'search-input',
                id: 'lint-search-input',
                tag: 'input',
              ),
            ],
            classes: 'search-box-wrapper',
            tag: 'div',
          ),
          Component.element(
            children: [
              Component.element(
                attributes: const {'data-filter': 'all', 'type': 'button'},
                children: [Component.text('All (${rules.length})')],
                classes: 'filter-chip active',
                tag: 'button',
              ),
              Component.element(
                attributes: const {
                  'data-filter': 'quick-fix',
                  'type': 'button',
                },
                children: [
                  const RawText(_fixWrenchSvg),
                  Component.text(' Fix available ($quickFixCount)'),
                ],
                classes: 'filter-chip',
                tag: 'button',
              ),
            ],
            classes: 'filter-chips',
            tag: 'div',
          ),
        ],
        classes: 'rules-toolbar',
        tag: 'div',
      ),
      Component.element(
        children: [
          Component.text('Showing ${rules.length} of ${rules.length} rules'),
        ],
        classes: 'rules-count-status',
        id: 'rules-count-status',
        tag: 'div',
      ),
      Component.element(
        children: [for (final rule in rules) _buildRuleCard(rule)],
        classes: 'rule-cards-grid',
        id: 'lint-cards-container',
        tag: 'div',
      ),
      Component.element(
        attributes: const {'hidden': 'hidden'},
        children: const [
          Component.text('No linter rules match your current search filter.'),
        ],
        classes: 'empty-search-state',
        id: 'empty-search-state',
        tag: 'div',
      ),
    ],
    classes: 'doc-section',
    tag: 'section',
  );

  String _stripLeadingDo(String text) {
    final trimmed = text.trim();
    if (trimmed.toLowerCase().startsWith('do ')) {
      return trimmed.substring(3);
    }
    return trimmed;
  }
}
