import 'package:jaspr/dom.dart';

/// Builds Jaspr [StyleRule] definitions injected into the [Document] head.
List<StyleRule> buildJasprStyleRules() => [
  StyleRule(
    selector: const Selector(':root'),
    styles: const Styles(
      raw: {
        '--bg-canvas': '#ffffff',
        '--bg-surface': '#f8fafc',
        '--bg-elevated': '#f1f5f9',
        '--bg-header': '#121826',
        '--text-primary': '#1e293b',
        '--text-secondary': '#475569',
        '--text-muted': '#64748b',
        '--border-color': '#e2e8f0',
        '--brand-blue': '#0175c2',
        '--brand-link': '#1967d2',
        '--brand-teal': '#00b4ab',
      },
    ),
  ),
  StyleRule(
    selector: const Selector('body'),
    styles: const Styles(
      raw: {
        'background-color': 'var(--bg-canvas)',
        'color': 'var(--text-primary)',
        'font-family':
            "'Google Sans', 'Inter', -apple-system, BlinkMacSystemFont, "
            "'Segoe UI', Roboto, sans-serif",
        'line-height': '1.6',
        'margin': '0',
      },
    ),
  ),
];

/// Returns the complete CSS stylesheet generated into `styles.css`.
String buildSiteStylesheet() => r'''
:root {
  --bg-canvas: #ffffff;
  --bg-surface: #f8f9fa;
  --bg-elevated: #f1f3f4;
  --bg-header: #121826;
  --bg-code: #f8f9fa;
  --text-primary: #202124;
  --text-secondary: #4a4e54;
  --text-muted: #5f6368;
  --border-color: #dadce0;
  --brand-blue: #0175c2;
  --brand-link: #1967d2;
  --brand-link-hover: #1557b0;
  --brand-teal: #00b4ab;
  --badge-stable-bg: #e6f4ea;
  --badge-stable-fg: #137333;
  --badge-fix-bg: #e8f0fe;
  --badge-fix-fg: #1967d2;
  --badge-tag-bg: #f1f5f9;
  --badge-tag-fg: #334155;
  --badge-tag-border: #cbd5e1;
  --bad-border: #d93025;
  --bad-header-bg: #fce8e6;
  --bad-header-fg: #c5221f;
  --good-border: #1e8e3e;
  --good-header-bg: #e6f4ea;
  --good-header-fg: #137333;
  --yaml-header-bg: #e8f0fe;
  --yaml-header-fg: #185abc;
  --inline-code-bg: #f1f3f4;
  --inline-code-fg: #1f1f1f;
  --shadow-sm: 0 1px 2px rgba(60, 64, 67, 0.08);
  --shadow-md: 0 2px 6px rgba(60, 64, 67, 0.12);
}

[data-theme="dark"] {
  --bg-canvas: #0f141c;
  --bg-surface: #161d27;
  --bg-elevated: #1e2736;
  --bg-header: #0b0f17;
  --bg-code: #141b24;
  --text-primary: #e8eaed;
  --text-secondary: #bdc1c6;
  --text-muted: #9aa0a6;
  --border-color: #2b3545;
  --brand-blue: #58a6ff;
  --brand-link: #8ab4f8;
  --brand-link-hover: #aecbfa;
  --brand-teal: #00d2b8;
  --badge-stable-bg: rgba(46, 160, 67, 0.18);
  --badge-stable-fg: #56d364;
  --badge-fix-bg: rgba(56, 139, 253, 0.18);
  --badge-fix-fg: #79c0ff;
  --badge-tag-bg: rgba(148, 163, 184, 0.14);
  --badge-tag-fg: #cbd5e1;
  --badge-tag-border: #334155;
  --bad-border: #f85149;
  --bad-header-bg: rgba(248, 81, 73, 0.16);
  --bad-header-fg: #ff7b72;
  --good-border: #3fb950;
  --good-header-bg: rgba(63, 185, 80, 0.16);
  --good-header-fg: #56d364;
  --yaml-header-bg: rgba(56, 139, 253, 0.15);
  --yaml-header-fg: #79c0ff;
  --inline-code-bg: #1f2937;
  --inline-code-fg: #e2e8f0;
  --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.35);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.45);
}

* {
  box-sizing: border-box;
}

html {
  scroll-behavior: smooth;
  scroll-padding-top: 76px;
}

body {
  margin: 0;
  background-color: var(--bg-canvas);
  color: var(--text-primary);
  font-family: 'Google Sans', 'Inter', -apple-system, BlinkMacSystemFont,
    'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
  font-size: 16px;
  line-height: 1.65;
  -webkit-font-smoothing: antialiased;
}

a {
  color: var(--brand-link);
  text-decoration: none;
}

a:hover {
  color: var(--brand-link-hover);
  text-decoration: underline;
}

code, pre {
  font-family: 'JetBrains Mono', 'Roboto Mono', 'Fira Code', ui-monospace,
    SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}

/* Header */
.site-header {
  position: sticky;
  top: 0;
  z-index: 100;
  height: 60px;
  background-color: var(--bg-header);
  color: #ffffff;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.2);
}

.site-header-inner {
  max-width: 1560px;
  height: 100%;
  margin: 0 auto;
  padding: 0 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.sidebar-toggle-btn {
  display: none;
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.25);
  color: #ffffff;
  border-radius: 6px;
  padding: 4px 10px;
  font-size: 18px;
  cursor: pointer;
}

.site-brand {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  color: #ffffff;
  font-weight: 600;
  font-size: 1.15rem;
  letter-spacing: -0.01em;
}

.site-brand:hover {
  color: #ffffff;
  text-decoration: none;
  opacity: 0.92;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 18px;
}

.header-nav-link {
  color: rgba(255, 255, 255, 0.82);
  font-size: 0.94rem;
  font-weight: 500;
  padding: 6px 10px;
  border-radius: 6px;
  transition: background-color 0.15s ease, color 0.15s ease;
}

.header-nav-link:hover,
.header-nav-link.active {
  color: #ffffff;
  background-color: rgba(255, 255, 255, 0.1);
  text-decoration: none;
}

.theme-toggle-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.2);
  background: rgba(255, 255, 255, 0.06);
  color: #ffffff;
  cursor: pointer;
  transition: background-color 0.15s ease;
}

.theme-toggle-btn:hover {
  background: rgba(255, 255, 255, 0.16);
}

/* 2-Column Body Layout */
.site-body {
  margin: 0 auto;
  display: grid;
  grid-template-columns: 340px minmax(0, 1fr);
  min-height: calc(100vh - 60px);
}

/* Left Sidebar */
.site-sidebar {
  border-right: 1px solid var(--border-color);
  background-color: var(--bg-surface);
  position: sticky;
  top: 60px;
  height: calc(100vh - 60px);
  overflow-y: auto;
  padding: 20px 14px 36px;
}

.sidebar-section-title {
  font-size: 0.78rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-muted);
  margin: 16px 10px 8px;
}

.sidebar-section-title:first-child {
  margin-top: 4px;
}

.sidebar-nav-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.sidebar-link {
  display: block;
  padding: 6px 10px;
  border-radius: 6px;
  color: var(--text-secondary);
  font-size: 0.9rem;
  line-height: 1.4;
  transition: background-color 0.12s ease, color 0.12s ease;
  overflow-wrap: anywhere;
}

.sidebar-link code {
  font-size: 0.84rem;
  color: inherit;
}

.sidebar-link:hover {
  background-color: var(--bg-elevated);
  color: var(--text-primary);
  text-decoration: none;
}

.sidebar-link.active {
  background-color: var(--badge-fix-bg);
  color: var(--badge-fix-fg);
  font-weight: 600;
}

/* Main Content */
.site-main {
  min-width: 0;
  padding: 32px 48px 64px;
}

.doc-article {
  margin: 0 auto;
}

/* Breadcrumbs */
.breadcrumbs-nav {
  margin-bottom: 16px;
}

.breadcrumb-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  font-size: 0.875rem;
  color: var(--text-muted);
}

.breadcrumb-item + .breadcrumb-item::before {
  content: "›";
  margin-right: 6px;
  color: var(--text-muted);
}

.breadcrumb-item.active {
  color: var(--text-primary);
  font-weight: 500;
}

/* Hero & Headings */
.hero-header {
  border-bottom: 1px solid var(--border-color);
  padding-bottom: 24px;
  margin-bottom: 28px;
}

.rule-title-row {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.page-title {
  margin: 0 0 12px;
  font-size: 2.25rem;
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.2;
}

.rule-page-title {
  margin-bottom: 0;
}

.rule-heading-code {
  font-size: 2rem;
  font-weight: 600;
  color: var(--text-primary);
}

.page-lead {
  font-size: 1.125rem;
  color: var(--text-secondary);
  margin: 14px 0 0;
}

.rule-meta-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
  margin-top: 14px;
}

.meta-pill,
.badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 0.82rem;
  font-weight: 600;
  padding: 4px 11px;
  border-radius: 999px;
  line-height: 1.3;
}

.status-stable {
  background-color: var(--badge-stable-bg);
  color: var(--badge-stable-fg);
}

.status-fix,
.badge-fix {
  background-color: var(--badge-fix-bg);
  color: var(--badge-fix-fg);
}

.status-muted {
  background-color: var(--bg-elevated);
  color: var(--text-muted);
}

.badge-tag {
  background-color: var(--badge-tag-bg);
  color: var(--badge-tag-fg);
  border: 1px solid var(--badge-tag-border);
  cursor: pointer;
  font-family: inherit;
  text-decoration: none;
  transition: background-color 0.15s ease, color 0.15s ease, border-color 0.15s ease;
}

.badge-tag:hover,
.badge-tag.active {
  background-color: var(--badge-fix-bg);
  color: var(--badge-fix-fg);
  border-color: var(--brand-link);
  text-decoration: none;
}

/* Sections */
.doc-section {
  margin-bottom: 36px;
}

.doc-section h2 {
  font-size: 1.5rem;
  font-weight: 600;
  margin: 32px 0 14px;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--border-color);
}

.inline-code {
  background-color: var(--inline-code-bg);
  color: var(--inline-code-fg);
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 0.88em;
}

.callout-box {
  padding: 14px 18px;
  border-radius: 8px;
  border-left: 4px solid var(--brand-link);
  background-color: var(--bg-surface);
  margin: 16px 0;
  color: var(--text-secondary);
}

.avoid-guideline-paragraph {
  font-size: 1.06rem;
  background-color: var(--bg-surface);
  border-left: 4px solid var(--bad-border);
  padding: 12px 16px;
  border-radius: 0 8px 8px 0;
  margin: 16px 0;
}

.avoid-keyword,
.avoid-prefix {
  color: var(--bad-border);
  font-weight: 700;
  letter-spacing: 0.03em;
}

.do-guideline-paragraph {
  font-size: 1.06rem;
  background-color: var(--bg-surface);
  border-left: 4px solid var(--brand-teal);
  padding: 12px 16px;
  border-radius: 0 8px 8px 0;
  margin: 16px 0;
}

.do-keyword,
.do-prefix {
  color: var(--brand-teal);
  font-weight: 700;
  letter-spacing: 0.03em;
}

/* Code Cards (BAD / GOOD / YAML) */
.code-card {
  margin: 18px 0;
  border-radius: 8px;
  border: 1px solid var(--border-color);
  overflow: hidden;
  background-color: var(--bg-code);
  box-shadow: var(--shadow-sm);
}

.code-card.bad-card {
  border-color: var(--bad-border);
  border-left-width: 4px;
}

.code-card.good-card {
  border-color: var(--good-border);
  border-left-width: 4px;
}

.code-block-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 14px;
  font-size: 0.82rem;
  font-weight: 700;
  border-bottom: 1px solid var(--border-color);
}

.bad-header {
  background-color: var(--bad-header-bg);
  color: var(--bad-header-fg);
}

.good-header {
  background-color: var(--good-header-bg);
  color: var(--good-header-fg);
}

.yaml-header,
.dart-header {
  background-color: var(--yaml-header-bg);
  color: var(--yaml-header-fg);
}

.markdown-content > :first-child {
  margin-top: 0;
}

.markdown-content > :last-child {
  margin-bottom: 0;
}

.markdown-paragraph {
  margin: 0 0 12px;
}

.markdown-list {
  margin: 8px 0 14px;
  padding-left: 24px;
}

.markdown-list li {
  margin-bottom: 4px;
}

.markdown-hr {
  border: 0;
  border-top: 1px solid var(--border-color);
  margin: 18px 0;
}

.markdown-link {
  color: var(--brand-link);
  font-weight: 500;
  text-decoration: underline;
  text-underline-offset: 2px;
}

.markdown-link:hover {
  color: var(--brand-link-hover);
}

.markdown-code-card {
  margin: 14px 0;
  font-size: 1rem;
}

.example-label {
  letter-spacing: 0.04em;
}

.code-block {
  margin: 0;
  padding: 16px 18px;
  overflow-x: auto;
  font-size: 0.88rem;
  line-height: 1.55;
  background-color: var(--bg-code);
  color: var(--text-primary);
}

.copy-code-btn,
.icon-copy-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  background: transparent;
  border: 1px solid currentColor;
  border-radius: 5px;
  color: inherit;
  padding: 3px 8px;
  font-size: 0.76rem;
  font-weight: 600;
  cursor: pointer;
  opacity: 0.82;
  transition: opacity 0.15s ease, background-color 0.15s ease;
}

.icon-copy-btn {
  border-color: var(--border-color);
  color: var(--text-muted);
  padding: 5px;
}

.icon-copy-btn.large {
  padding: 6px 8px;
}

.copy-code-btn:hover,
.icon-copy-btn:hover {
  opacity: 1;
  background-color: rgba(127, 127, 127, 0.12);
}

/* Search & Filter Toolbar on Index Page */
.rules-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin: 18px 0 12px;
}

.search-box-wrapper {
  flex: 1 1 280px;
}

.search-input {
  width: 100%;
  padding: 10px 14px;
  font-size: 0.95rem;
  border: 1px solid var(--border-color);
  border-radius: 8px;
  background-color: var(--bg-surface);
  color: var(--text-primary);
  outline: none;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.search-input:focus {
  border-color: var(--brand-link);
  box-shadow: 0 0 0 3px rgba(25, 103, 210, 0.18);
}

.filter-chips {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.filter-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border-radius: 999px;
  border: 1px solid var(--border-color);
  background-color: var(--bg-surface);
  color: var(--text-secondary);
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s ease;
}

.filter-chip:hover {
  background-color: var(--bg-elevated);
}

.filter-chip.active {
  background-color: var(--badge-fix-bg);
  color: var(--badge-fix-fg);
  border-color: var(--brand-link);
}

.rules-count-status {
  font-size: 0.85rem;
  color: var(--text-muted);
  margin-bottom: 16px;
}

/* Rule Cards on Index Page */
.rule-cards-grid {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.rule-card {
  border: 1px solid var(--border-color);
  border-radius: 10px;
  padding: 18px 20px;
  background-color: var(--bg-canvas);
  box-shadow: var(--shadow-sm);
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.rule-card:hover {
  border-color: var(--brand-link);
  box-shadow: var(--shadow-md);
}

.rule-card-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 10px;
}

.rule-card-title-group {
  display: flex;
  align-items: center;
  gap: 8px;
}

.rule-card-name {
  font-size: 1.08rem;
  font-weight: 600;
  color: var(--brand-link);
}

.rule-card-badges {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.rule-details-link {
  font-size: 0.86rem;
  font-weight: 600;
}

.rule-card-avoid,
.rule-card-do {
  margin: 8px 0 6px;
  font-weight: 500;
  color: var(--text-primary);
}

.rule-card-description {
  margin: 0;
  font-size: 0.93rem;
  color: var(--text-secondary);
}

.empty-search-state {
  padding: 32px;
  text-align: center;
  border: 1px dashed var(--border-color);
  border-radius: 10px;
  color: var(--text-muted);
}

/* Pagination */
.page-pagination {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
  margin-top: 44px;
  padding-top: 24px;
  border-top: 1px solid var(--border-color);
}

.page-nav-card {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 14px 18px;
  border: 1px solid var(--border-color);
  border-radius: 8px;
  background-color: var(--bg-surface);
  transition: border-color 0.15s ease;
}

.page-nav-card.next {
  text-align: right;
  align-items: flex-end;
}

.page-nav-card:hover {
  border-color: var(--brand-link);
  text-decoration: none;
}

.page-nav-label {
  font-size: 0.8rem;
  color: var(--text-muted);
}

.page-nav-rule {
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--brand-link);
}

/* Syntax Highlighting */
.tok-kw { color: #d73a49; font-weight: 600; }
.tok-key { color: #005cc5; }
.tok-obj { color: #005cc5; }
.tok-str { color: #22863a; }
.tok-cmt { color: #6a737d; font-style: italic; }
.tok-cmt-code {
  font-style: normal;
  font-weight: 500;
  color: #3b424b;
  background-color: rgba(27, 31, 35, 0.08);
  border: 1px solid rgba(27, 31, 35, 0.14);
  border-radius: 4px;
  padding: 1px 5px;
  font-size: 0.92em;
}
.tok-ann { color: #6f42c1; }
.tok-num { color: #005cc5; }

[data-theme="dark"] .tok-kw { color: #ff7b72; }
[data-theme="dark"] .tok-key { color: #79c0ff; }
[data-theme="dark"] .tok-obj { color: #79c0ff; }
[data-theme="dark"] .tok-str { color: #7ee787; }
[data-theme="dark"] .tok-cmt { color: #8b949e; }
[data-theme="dark"] .tok-cmt-code {
  color: #c9d1d9;
  background-color: rgba(240, 246, 252, 0.12);
  border-color: rgba(240, 246, 252, 0.2);
}
[data-theme="dark"] .tok-ann { color: #d2a8ff; }
[data-theme="dark"] .tok-num { color: #79c0ff; }

/* Responsive Breakpoints */
@media (max-width: 820px) {
  .sidebar-toggle-btn {
    display: inline-flex;
  }
  .site-body {
    grid-template-columns: minmax(0, 1fr);
  }
  .site-sidebar {
    display: none;
    position: fixed;
    top: 60px;
    left: 0;
    width: 340px;
    z-index: 90;
    box-shadow: var(--shadow-md);
  }
  .site-sidebar.open {
    display: block;
  }
  .site-main {
    padding: 24px 18px 48px;
  }
  .page-pagination {
    grid-template-columns: 1fr;
  }
}
''';
