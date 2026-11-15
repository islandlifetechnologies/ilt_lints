/// Returns the client-side JavaScript generated into `main.js`.
String buildSiteScript() => r'''
(function () {
  'use strict';

  var STORAGE_KEY = 'jaspr_lint_theme';

  function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem(STORAGE_KEY, theme);
    } catch (_) {}
  }

  function initTheme() {
    var saved = null;
    try {
      saved = localStorage.getItem(STORAGE_KEY);
    } catch (_) {}
    if (saved === 'dark' || saved === 'light') {
      document.documentElement.setAttribute('data-theme', saved);
    } else if (
      window.matchMedia &&
      window.matchMedia('(prefers-color-scheme: dark)').matches
    ) {
      document.documentElement.setAttribute('data-theme', 'dark');
    }

    var toggleBtn = document.getElementById('theme-toggle');
    if (toggleBtn) {
      toggleBtn.addEventListener('click', function () {
        var current =
          document.documentElement.getAttribute('data-theme') === 'dark'
            ? 'dark'
            : 'light';
        applyTheme(current === 'dark' ? 'light' : 'dark');
      });
    }
  }

  function initSidebarToggle() {
    var btn = document.getElementById('sidebar-toggle');
    var sidebar = document.getElementById('site-sidebar');
    if (!btn || !sidebar) return;
    btn.addEventListener('click', function () {
      var isOpen = sidebar.classList.toggle('open');
      btn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });
  }

  function copyText(text, onDone) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(onDone, function () {});
      return;
    }
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
      onDone();
    } catch (_) {}
    document.body.removeChild(textarea);
  }

  function initCopyButtons() {
    var codeBtns = document.querySelectorAll('.copy-code-btn');
    codeBtns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var card = btn.closest('.code-card');
        if (!card) return;
        var codeEl = card.querySelector('pre code');
        if (!codeEl) return;
        var raw = codeEl.getAttribute('data-raw-code') || codeEl.textContent || '';
        var originalHtml = btn.innerHTML;
        copyText(raw, function () {
          btn.textContent = '✓ Copied';
          setTimeout(function () {
            btn.innerHTML = originalHtml;
          }, 1600);
        });
      });
    });

    var ruleBtns = document.querySelectorAll('.icon-copy-btn[data-copy]');
    ruleBtns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var ruleName = btn.getAttribute('data-copy') || '';
        var originalTitle = btn.getAttribute('title') || '';
        copyText(ruleName, function () {
          btn.setAttribute('title', 'Copied!');
          setTimeout(function () {
            btn.setAttribute('title', originalTitle);
          }, 1400);
        });
      });
    });
  }

  function initRuleFilter() {
    var searchInput = document.getElementById('lint-search-input');
    var filterChips = document.querySelectorAll('.filter-chip');
    var cardTagBtns = document.querySelectorAll('[data-tag-select]');
    var cards = document.querySelectorAll('#lint-cards-container .rule-card');
    var statusEl = document.getElementById('rules-count-status');
    var emptyEl = document.getElementById('empty-search-state');

    if (!cards.length) return;

    var activeFilter = 'all';

    function syncActiveChipUi() {
      filterChips.forEach(function (chip) {
        var chipFilter = chip.getAttribute('data-filter') || 'all';
        if (chipFilter === activeFilter) {
          chip.classList.add('active');
        } else {
          chip.classList.remove('active');
        }
      });

      var activeTag =
        activeFilter.indexOf('tag:') === 0
          ? activeFilter.substring(4).toLowerCase()
          : '';
      cardTagBtns.forEach(function (btn) {
        var btnTag = (btn.getAttribute('data-tag-select') || '').toLowerCase();
        if (activeTag && btnTag === activeTag) {
          btn.classList.add('active');
        } else {
          btn.classList.remove('active');
        }
      });
    }

    function updateFilter() {
      var query = searchInput ? searchInput.value.trim().toLowerCase() : '';
      var visibleCount = 0;

      cards.forEach(function (card) {
        var searchText = (card.getAttribute('data-search-text') || '').toLowerCase();
        var hasQuickFix = card.getAttribute('data-quick-fix') === 'true';
        var cardTags = (card.getAttribute('data-tags') || '')
          .split(',')
          .map(function (t) {
            return t.trim().toLowerCase();
          })
          .filter(Boolean);
        var matchesQuery = !query || searchText.indexOf(query) !== -1;
        var matchesChip = false;
        if (activeFilter === 'all') {
          matchesChip = true;
        } else if (activeFilter === 'quick-fix') {
          matchesChip = hasQuickFix;
        } else if (activeFilter.indexOf('tag:') === 0) {
          var targetTag = activeFilter.substring(4).toLowerCase();
          matchesChip = cardTags.indexOf(targetTag) !== -1;
        }

        if (matchesQuery && matchesChip) {
          card.removeAttribute('hidden');
          visibleCount++;
        } else {
          card.setAttribute('hidden', 'hidden');
        }
      });

      if (statusEl) {
        statusEl.textContent =
          'Showing ' + visibleCount + ' of ' + cards.length + ' rules';
      }
      if (emptyEl) {
        if (visibleCount === 0) {
          emptyEl.removeAttribute('hidden');
        } else {
          emptyEl.setAttribute('hidden', 'hidden');
        }
      }
    }

    function setActiveFilter(nextFilter) {
      activeFilter = nextFilter || 'all';
      syncActiveChipUi();
      updateFilter();
    }

    if (searchInput) {
      searchInput.addEventListener('input', updateFilter);
    }

    filterChips.forEach(function (chip) {
      chip.addEventListener('click', function () {
        var clickedFilter = chip.getAttribute('data-filter') || 'all';
        if (clickedFilter !== 'all' && activeFilter === clickedFilter) {
          setActiveFilter('all');
        } else {
          setActiveFilter(clickedFilter);
        }
      });
    });

    cardTagBtns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var tag = (btn.getAttribute('data-tag-select') || '').trim().toLowerCase();
        if (!tag) return;
        var targetFilter = 'tag:' + tag;
        if (activeFilter === targetFilter) {
          setActiveFilter('all');
        } else {
          setActiveFilter(targetFilter);
        }
      });
    });

    try {
      var params = new URLSearchParams(window.location.search);
      var urlTag = params.get('tag');
      if (urlTag && urlTag.trim()) {
        setActiveFilter('tag:' + urlTag.trim().toLowerCase());
      }
    } catch (_) {}
  }

  function escapeHtml(str) {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function formatComment(comment) {
    var formatted = comment.replace(
      /`([^`]+)`/g,
      '<span class="tok-cmt-code">$1</span>'
    );
    return '<span class="tok-cmt">' + formatted + '</span>';
  }

  function formatYamlValue(val) {
    var trimmed = val.trim();
    if (!trimmed) return val;
    if (/^(true|false|null)$/.test(trimmed)) {
      return val.replace(/\b(true|false|null)\b/, '<span class="tok-kw">$1</span>');
    }
    if (/^-?\d+(\.\d+)?$/.test(trimmed)) {
      return val.replace(/(-?\d+(?:\.\d+)?)/, '<span class="tok-num">$1</span>');
    }
    return '<span class="tok-str">' + val + '</span>';
  }

  function highlightYaml(escaped) {
    return escaped
      .split('\n')
      .map(function (line) {
        if (/^\s*#/.test(line)) {
          return formatComment(line);
        }
        var keyMatch = line.match(
          /^(\s*(?:-\s+)?)([A-Za-z0-9_.-]+)(:)(\s*)(.*?)(?:\s+(#.*))?$/
        );
        if (keyMatch) {
          var prefix = keyMatch[1];
          var key = keyMatch[2];
          var colon = keyMatch[3];
          var space = keyMatch[4];
          var val = keyMatch[5] || '';
          var cmt = keyMatch[6] ? ' ' + formatComment(keyMatch[6]) : '';
          return (
            prefix +
            '<span class="tok-key">' +
            key +
            '</span>' +
            colon +
            space +
            (val ? formatYamlValue(val) : '') +
            cmt
          );
        }
        var listMatch = line.match(/^(\s*-\s+)(.*?)(?:\s+(#.*))?$/);
        if (listMatch) {
          var listPrefix = listMatch[1];
          var itemVal = listMatch[2] || '';
          var listCmt = listMatch[3] ? ' ' + formatComment(listMatch[3]) : '';
          return listPrefix + formatYamlValue(itemVal) + listCmt;
        }
        return line;
      })
      .join('\n');
  }

  function highlightCodeBlocks() {
    var blocks = document.querySelectorAll('pre.code-block code');
    blocks.forEach(function (block) {
      var raw = block.textContent || '';
      block.setAttribute('data-raw-code', raw);
      var escaped = escapeHtml(raw);
      if (
        block.classList.contains('language-yaml') ||
        block.classList.contains('language-yml') ||
        block.classList.contains('language-json')
      ) {
        block.innerHTML = highlightYaml(escaped);
      } else if (block.classList.contains('language-dart')) {
        var dartHighlighted = escaped.replace(
          /(\/\/.*$)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(@[A-Za-z_][A-Za-z0-9_]*)|(?<![A-Za-z0-9_$])([A-Z][A-Za-z0-9_]*)\b|\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|get|hide|if|implements|import|in|interface|is|late|library|mixin|new|null|on|operator|part|required|rethrow|return|sealed|set|show|static|super|switch|sync|this|throw|true|try|typedef|var|void|when|while|with|yield)\b/gm,
          function (match, comment, str, ann, obj, kw) {
            if (comment) return formatComment(comment);
            if (str) return '<span class="tok-str">' + str + '</span>';
            if (ann) return '<span class="tok-ann">' + ann + '</span>';
            if (obj) return '<span class="tok-obj">' + obj + '</span>';
            if (kw) return '<span class="tok-kw">' + kw + '</span>';
            return match;
          }
        );
        block.innerHTML = dartHighlighted;
      } else if (
        block.classList.contains('language-sh') ||
        block.classList.contains('language-bash') ||
        block.classList.contains('language-shell')
      ) {
        var shHighlighted = escaped.replace(
          /(#.*$)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(\s--?[A-Za-z0-9_-]+)/gm,
          function (match, comment, str, flag) {
            if (comment) return formatComment(comment);
            if (str) return '<span class="tok-str">' + str + '</span>';
            if (flag) return '<span class="tok-key">' + flag + '</span>';
            return match;
          }
        );
        block.innerHTML = shHighlighted;
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      initTheme();
      initSidebarToggle();
      highlightCodeBlocks();
      initCopyButtons();
      initRuleFilter();
    });
  } else {
    initTheme();
    initSidebarToggle();
    highlightCodeBlocks();
    initCopyButtons();
    initRuleFilter();
  }
})();
''';
