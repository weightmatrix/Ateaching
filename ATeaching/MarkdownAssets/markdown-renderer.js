(function () {
    function ensureRoot() {
        var root = document.getElementById('md-root');
        if (!root) {
            root = document.createElement('div');
            root.id = 'md-root';
            document.body.appendChild(root);
        }
        return root;
    }

    function ensureCount(total) {
        var root = ensureRoot();
        while (root.children.length < total) {
            root.appendChild(document.createElement('section'));
        }
        while (root.children.length > total) {
            root.removeChild(root.lastChild);
        }
    }

    function renderMath(root) {
        if (typeof window.renderMathInElement !== 'function') return;
        window.renderMathInElement(root, {
            delimiters: [
                { left: '$$', right: '$$', display: true },
                { left: '\\[', right: '\\]', display: true },
                { left: '$', right: '$', display: false },
                { left: '\\(', right: '\\)', display: false }
            ],
            throwOnError: false
        });
    }

    function sectionStartLine(section) {
        var raw = section && section.dataset ? section.dataset.sourceLineStart : '';
        var value = parseInt(raw || '0', 10);
        return isNaN(value) ? 0 : value;
    }

    function currentCenterSourceLine() {
        var root = ensureRoot();
        var centerY = window.innerHeight * 0.5;
        var best = null;
        var bestDistance = Number.MAX_VALUE;
        for (var i = 0; i < root.children.length; i += 1) {
            var section = root.children[i];
            var rect = section.getBoundingClientRect();
            if (rect.bottom < 0 || rect.top > window.innerHeight) continue;
            if (rect.top <= centerY && rect.bottom >= centerY) {
                return sectionStartLine(section);
            }
            var distance = Math.min(Math.abs(rect.top - centerY), Math.abs(rect.bottom - centerY));
            if (distance < bestDistance) {
                bestDistance = distance;
                best = section;
            }
        }
        return best ? sectionStartLine(best) : 0;
    }

    function scrollToSourceLine(sourceLine) {
        var root = ensureRoot();
        var targetLine = Math.max(0, parseInt(sourceLine || 0, 10) || 0);
        var target = null;
        for (var i = 0; i < root.children.length; i += 1) {
            var section = root.children[i];
            if (sectionStartLine(section) <= targetLine) {
                target = section;
            } else {
                break;
            }
        }
        if (!target) target = root.children[0];
        if (!target) return;
        var rect = target.getBoundingClientRect();
        var nextY = window.scrollY + rect.top + rect.height * 0.5 - window.innerHeight * 0.5;
        window.markdownRenderer.isApplyingExternalScroll = true;
        window.scrollTo({ top: Math.max(0, nextY), behavior: 'auto' });
        window.requestAnimationFrame(function () {
            window.requestAnimationFrame(function () {
                window.markdownRenderer.isApplyingExternalScroll = false;
            });
        });
    }

    function renderMarkdown(markdown) {
        markdown = normalizeMarkdownSource(markdown);
        markdown = preserveExplicitNumberedLines(markdown);
        if (window.marked && typeof window.marked.parse === 'function') {
            return normalizeRenderedHTML(window.marked.parse(markdown, {
                gfm: true,
                breaks: true,
                pedantic: false,
                smartypants: false
            }));
        }
        return renderBasicMarkdown(markdown);
    }

    function escapeHTML(value) {
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function renderInlineMarkdown(value) {
        value = normalizeMarkdownSource(value);
        if (window.marked && typeof window.marked.parseInline === 'function') {
            return normalizeRenderedHTML(window.marked.parseInline(value, {
                gfm: true,
                breaks: true,
                pedantic: false,
                smartypants: false
            }));
        }
        return renderBasicMarkdown(value);
    }

    function normalizeRenderedHTML(value) {
        return String(value)
            .replace(/(?:&lt;|<)(?:strong|stong|b)(?:&gt;|>)([\s\S]*?)(?:&lt;|<)\/(?:strong|stong|b)(?:&gt;|>)/gi, '<strong>$1</strong>')
            .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
            .replace(/__([^_\n]+)__/g, '<strong>$1</strong>')
            .replace(/&lt;br\s*\/?&gt;/gi, '<br>');
    }

    function normalizeMarkdownSource(value) {
        return String(value)
            .replace(/<(?:strong|stong|b)>([\s\S]*?)<\/(?:strong|stong|b)>/gi, '**$1**')
            .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
            .replace(/__([^_\n]+)__/g, '<strong>$1</strong>')
            .replace(/<br\s*\/?>/gi, '<br>');
    }

    function renderBasicMarkdown(value) {
        return escapeHTML(value)
            .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
            .replace(/__([^_\n]+)__/g, '<strong>$1</strong>')
            .replace(/`([^`\n]+)`/g, '<code>$1</code>')
            .replace(/\n/g, '<br/>');
    }

    function preserveExplicitNumberedLines(markdown) {
        var lines = String(markdown || '').split('\n');
        var inFence = false;
        return lines.map(function (line) {
            var trimmed = line.trim();
            if (trimmed.indexOf('```') === 0 || trimmed.indexOf('~~~') === 0) {
                inFence = !inFence;
                return line;
            }
            if (inFence) return line;
            var match = /^( *)(.*?\d+)\. +(.*)$/.exec(line);
            if (!match) return line;
            var indent = match[1].length;
            var marker = match[2] + '. ';
            var body = match[3] || '';
            var pad = Math.max(0, indent) * 0.72;
            return '<div class="md-preserved-numbered" style="padding-left:' + pad + 'em"><span class="md-preserved-marker">' + escapeHTML(marker) + '</span>' + renderInlineMarkdown(body) + '</div>';
        }).join('\n');
    }

    window.markdownRenderer = {
        isApplyingExternalScroll: false,
        apply: function (total, patches) {
            var root = ensureRoot();
            ensureCount(total);

            for (var i = 0; i < patches.length; i += 1) {
                var patch = patches[i];
                var node = root.children[patch.index];
                if (!node) continue;
                node.dataset.hash = patch.hash;
                node.dataset.sourceLineStart = String(patch.startLine || 0);
                node.innerHTML = renderMarkdown(patch.markdown || '');
            }

            renderMath(root);
        },
        currentCenterSourceLine: currentCenterSourceLine,
        scrollToSourceLine: scrollToSourceLine
    };

    var markdownScrollSyncTimer = null;
    window.addEventListener('scroll', function () {
        if (window.markdownRenderer.isApplyingExternalScroll) return;
        if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.markdownScrollSync) return;
        window.clearTimeout(markdownScrollSyncTimer);
        markdownScrollSyncTimer = window.setTimeout(function () {
            window.webkit.messageHandlers.markdownScrollSync.postMessage(currentCenterSourceLine());
        }, 180);
    }, { passive: true });
})();
