import 'package:jaspr/dom.dart' show RawText;
import 'package:jaspr/jaspr.dart';

import '../models/custom_lint_config.dart';

/// Shared `dart.dev`-inspired documentation layout shell for the linter site.
class const SiteLayout({
  final String? activeRuleName,
  required final List<Component> breadcrumbs,
  required final Component child,
  super.key,
  required final String rootPrefix,
  required final List<CustomLintRule> rules,
  required final String siteTitle,
}) extends StatelessComponent {
  static const _dartLogoSvg =
      '<svg class="brand-logo" viewBox="0 0 32 32" width="26" height="26" '
      'aria-hidden="true" focusable="false">'
      '<path fill="#00D2B8" d="M6.4 6.4L16 1.6l12.8 12.8v11.2H17.6L6.4 14.4z"/>'
      '<path fill="#0081C6" d="M6.4 6.4L17.6 17.6h11.2L16 4.8z"/>'
      '<path fill="#00559E" d="M6.4 14.4v11.2l5.6 4.8h12.8l-7.2-7.2z"/>'
      '</svg>';

  static const _sunMoonSvg =
      '<svg class="theme-icon" viewBox="0 0 24 24" width="18" height="18" '
      'fill="none" stroke="currentColor" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
      '<circle cx="12" cy="12" r="4"/>'
      '<path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41'
      'M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>'
      '</svg>';

  @override
  Component build(BuildContext context) {
    final indexHref = '${rootPrefix}index.html';
    return Component.element(
      children: [
        _buildHeader(indexHref),
        Component.element(
          children: [
            _buildLeftSidebar(indexHref),
            Component.element(
              children: [
                Component.element(
                  children: [_buildBreadcrumbs(), child],
                  classes: 'doc-article',
                  tag: 'article',
                ),
              ],
              classes: 'site-main',
              id: 'main-content',
              tag: 'main',
            ),
          ],
          classes: 'site-body',
          tag: 'div',
        ),
      ],
      classes: 'site-wrapper',
      tag: 'div',
    );
  }

  Component _buildBreadcrumbs() => Component.element(
    attributes: const {'aria-label': 'Breadcrumbs'},
    children: [
      Component.element(
        children: breadcrumbs,
        classes: 'breadcrumb-list',
        tag: 'ol',
      ),
    ],
    classes: 'breadcrumbs-nav',
    tag: 'nav',
  );

  Component _buildHeader(String indexHref) => Component.element(
    children: [
      Component.element(
        children: [
          Component.element(
            children: [
              Component.element(
                attributes: const {
                  'aria-controls': 'site-sidebar',
                  'aria-expanded': 'false',
                  'aria-label': 'Toggle navigation sidebar',
                  'type': 'button',
                },
                children: const [Component.text('☰')],
                classes: 'sidebar-toggle-btn',
                id: 'sidebar-toggle',
                tag: 'button',
              ),
              Component.element(
                attributes: {'href': indexHref},
                children: [
                  const RawText(_dartLogoSvg),
                  Component.element(
                    children: [Component.text(siteTitle)],
                    classes: 'brand-title',
                    tag: 'span',
                  ),
                ],
                classes: 'site-brand',
                tag: 'a',
              ),
            ],
            classes: 'header-left',
            tag: 'div',
          ),
          Component.element(
            children: [
              Component.element(
                attributes: {'href': indexHref},
                children: const [Component.text('Linter rules')],
                classes: activeRuleName == null
                    ? 'header-nav-link active'
                    : 'header-nav-link',
                tag: 'a',
              ),
              Component.element(
                attributes: {'href': '$indexHref#all-linter-rules'},
                children: [Component.text('All rules (${rules.length})')],
                classes: 'header-nav-link',
                tag: 'a',
              ),
              Component.element(
                attributes: const {
                  'aria-label': 'Toggle dark or light theme',
                  'title': 'Toggle theme',
                  'type': 'button',
                },
                children: const [RawText(_sunMoonSvg)],
                classes: 'theme-toggle-btn',
                id: 'theme-toggle',
                tag: 'button',
              ),
            ],
            classes: 'header-right',
            tag: 'nav',
          ),
        ],
        classes: 'site-header-inner',
        tag: 'div',
      ),
    ],
    classes: 'site-header',
    tag: 'header',
  );

  Component _buildLeftSidebar(String indexHref) => Component.element(
    attributes: const {'aria-label': 'Section navigation'},
    children: [
      Component.element(
        children: [
          Component.element(
            children: const [Component.text('Tools')],
            classes: 'sidebar-section-title',
            tag: 'div',
          ),
          Component.element(
            children: [
              Component.element(
                children: [
                  Component.element(
                    attributes: {'href': indexHref},
                    children: const [Component.text('Linter rules')],
                    classes: activeRuleName == null
                        ? 'sidebar-link active'
                        : 'sidebar-link',
                    tag: 'a',
                  ),
                ],
                tag: 'li',
              ),
              Component.element(
                children: [
                  Component.element(
                    attributes: {'href': '$indexHref#all-linter-rules'},
                    children: const [Component.text('All linter rules')],
                    classes: 'sidebar-link',
                    tag: 'a',
                  ),
                ],
                tag: 'li',
              ),
            ],
            classes: 'sidebar-nav-list',
            tag: 'ul',
          ),
          Component.element(
            children: [Component.text('Individual rules (${rules.length})')],
            classes: 'sidebar-section-title',
            tag: 'div',
          ),
          Component.element(
            children: [
              for (final rule in rules)
                Component.element(
                  children: [
                    Component.element(
                      attributes: {
                        'href': '${rootPrefix}linter-rules/${rule.name}.html',
                      },
                      children: [
                        Component.element(
                          children: [Component.text(rule.name)],
                          tag: 'code',
                        ),
                      ],
                      classes: activeRuleName == rule.name
                          ? 'sidebar-link sidebar-rule-link active'
                          : 'sidebar-link sidebar-rule-link',
                      tag: 'a',
                    ),
                  ],
                  tag: 'li',
                ),
            ],
            classes: 'sidebar-nav-list sidebar-rules-list',
            tag: 'ul',
          ),
        ],
        classes: 'sidebar-inner',
        tag: 'div',
      ),
    ],
    classes: 'site-sidebar',
    id: 'site-sidebar',
    tag: 'aside',
  );
}
