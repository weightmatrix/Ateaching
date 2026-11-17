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

    var blocks = [];
    var heights = [];
    var tree = [0];
    var mounted = new Map();
    var virtualized = true;
    var framePending = false;
    var topSpacer, bottomSpacer;
    var renderedFirst = -1, renderedLast = -1;
    var resizeObserver = typeof ResizeObserver === 'function' ? new ResizeObserver(function () { scheduleViewport(); }) : null;
    var renderedCount = 0;

    function rebuildHeights() {
        tree = new Array(heights.length + 1).fill(0);
        for (var i = 1; i < tree.length; i++) {
            tree[i] += heights[i - 1];
            var parent = i + (i & -i);
            if (parent < tree.length) tree[parent] += tree[i];
        }
    }
    function sum(end) {
        var result = 0;
        for (var i = Math.min(end, heights.length); i > 0; i -= i & -i) result += tree[i];
        return result;
    }
    function setHeight(index, value) {
        value = Math.max(1, value);
        var delta = value - heights[index];
        if (Math.abs(delta) < 0.5) return false;
        heights[index] = value;
        for (var i = index + 1; i < tree.length; i += i & -i) tree[i] += delta;
        return true;
    }
    function indexAt(y) {
        if (!blocks.length) return 0;
        var index = 0, offset = 0, bit = 1;
        while (bit * 2 < tree.length) bit *= 2;
        for (; bit; bit >>= 1) {
            var next = index + bit;
            if (next < tree.length && offset + tree[next] <= y) { index = next; offset += tree[next]; }
        }
        return Math.min(index, blocks.length - 1);
    }
    function contentTop() {
        var root = ensureRoot();
        return root.getBoundingClientRect().top + window.scrollY + (parseFloat(getComputedStyle(root).paddingTop) || 0);
    }
    function estimationMetrics() {
        var style = getComputedStyle(ensureRoot());
        return { lineHeight: parseFloat(style.lineHeight) || 26, columns: Math.max(20, Math.floor((ensureRoot().clientWidth - 36) / ((parseFloat(style.fontSize) || 15) * 0.65))) };
    }
    function estimate(markdown, metrics) {
        var lineHeight = metrics.lineHeight;
        var columns = metrics.columns;
        var lines = String(markdown || '').split('\n');
        var count = 0;
        for (var i = 0; i < lines.length; i++) count += Math.max(1, Math.ceil(lines[i].length / columns));
        return Math.max(32, count * lineHeight + 16);
    }
    function setupSpacers() {
        var root = ensureRoot();
        if (topSpacer && topSpacer.parentNode === root) return;
        root.style.overflowAnchor = 'none';
        topSpacer = document.createElement('div'); bottomSpacer = document.createElement('div');
        topSpacer.setAttribute('aria-hidden', 'true'); bottomSpacer.setAttribute('aria-hidden', 'true');
        topSpacer.dataset.virtualSpacer = 'top'; bottomSpacer.dataset.virtualSpacer = 'bottom';
        root.replaceChildren(topSpacer, bottomSpacer);
    }
    function fullIndexAtClientY(y) {
        var low = 0, high = blocks.length;
        while (low < high) {
            var mid = (low + high) >> 1, node = mounted.get(mid);
            if (node && node.getBoundingClientRect().bottom <= y) low = mid + 1; else high = mid;
        }
        return Math.min(low, Math.max(0, blocks.length - 1));
    }
    function anchor() {
        if (!virtualized && blocks.length) {
            var index = fullIndexAtClientY(0), node = mounted.get(index);
            if (node) return { index: index, offset: -node.getBoundingClientRect().top };
        }
        var y = window.scrollY - contentTop();
        var index = indexAt(Math.max(0, y));
        return { index: index, offset: y - sum(index) };
    }
    function scheduleViewport() {
        if (framePending) return;
        framePending = true;
        window.requestAnimationFrame(function () { framePending = false; renderViewport(); });
    }
    function renderViewport(savedAnchor) {
        setupSpacers();
        var root = ensureRoot();
        if (!blocks.length) {
            mounted.forEach(function (node) { if (resizeObserver) resizeObserver.unobserve(node); node.remove(); });
            mounted.clear(); topSpacer.style.height = bottomSpacer.style.height = '0px';
            renderedFirst = renderedLast = -1;
            return;
        }
        var saved = savedAnchor || anchor();
        var y = Math.max(0, window.scrollY - contentTop());
        var buffer = Math.max(800, window.innerHeight);
        var first = virtualized ? indexAt(Math.max(0, y - buffer)) : 0;
        var last = virtualized ? indexAt(y + window.innerHeight + buffer) : blocks.length - 1;
        mounted.forEach(function (node, index) {
            if (index < first || index > last) {
                if (resizeObserver) resizeObserver.unobserve(node);
                node.remove(); mounted.delete(index);
            }
        });
        for (var i = first; i <= last; i++) {
            var node = mounted.get(i);
            if (!node) {
                node = document.createElement('section');
                node.dataset.blockIndex = String(i);
                mounted.set(i, node);
                // Insert in source order without replacing unchanged visible content or selection.
                var successor = bottomSpacer;
                for (var j = i + 1; j <= last; j++) { if (mounted.has(j)) { successor = mounted.get(j); break; } }
                root.insertBefore(node, successor);
                if (resizeObserver) resizeObserver.observe(node);
            }
            node.style.display = virtualized ? 'flow-root' : 'block';
            var block = blocks[i];
            node.dataset.sourceLineStart = String(block.startLine || 0);
            if (node.dataset.hash !== block.hash) {
                node.dataset.hash = block.hash;
                node.innerHTML = renderMarkdown(block.markdown);
                renderMath(node);
                renderedCount++;
                node.querySelectorAll('img').forEach(function (img) {
                    img.addEventListener('load', scheduleViewport, { once: true });
                    img.addEventListener('error', scheduleViewport, { once: true });
                });
            }
        }
        var changed = false;
        mounted.forEach(function (node, index) { changed = setHeight(index, node.getBoundingClientRect().height) || changed; });
        topSpacer.style.height = sum(first) + 'px';
        bottomSpacer.style.height = Math.max(0, sum(blocks.length) - sum(last + 1)) + 'px';
        renderedFirst = first; renderedLast = last;
        if (changed) {
            var corrected = contentTop() + sum(saved.index) + saved.offset;
            if (!virtualized && mounted.has(saved.index)) corrected = window.scrollY + mounted.get(saved.index).getBoundingClientRect().top + saved.offset;
            // Preserve the current source-block anchor while estimated heights become exact.
            if (Math.abs(corrected - window.scrollY) > 0.5) window.scrollTo(window.scrollX, corrected);
            scheduleViewport();
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

    function changeVirtualization(enabled) {
        var saved = blocks.length ? anchor() : null;
        virtualized = !!enabled;
        renderViewport(saved);
    }
    function currentCenterSourceLine() {
        if (!blocks.length) return 0;
        if (!virtualized) return blocks[fullIndexAtClientY(window.innerHeight * 0.5)].startLine || 0;
        var index = indexAt(Math.max(0, window.scrollY + window.innerHeight * 0.5 - contentTop()));
        return blocks[index].startLine || 0;
    }

    function scrollToSourceLine(sourceLine) {
        if (!blocks.length) return;
        var targetLine = Math.max(0, parseInt(sourceLine || 0, 10) || 0);
        var low = 0, high = blocks.length;
        while (low < high) {
            var middle = (low + high) >> 1;
            if ((blocks[middle].startLine || 0) <= targetLine) low = middle + 1; else high = middle;
        }
        var index = Math.max(0, low - 1);
        window.markdownRenderer.isApplyingExternalScroll = true;
        window.scrollTo(0, Math.max(0, contentTop() + sum(index) - window.innerHeight * 0.5));
        renderViewport();
        var node = mounted.get(index);
        if (node) {
            var rect = node.getBoundingClientRect();
            window.scrollTo(0, Math.max(0, window.scrollY + rect.top + rect.height * 0.5 - window.innerHeight * 0.5));
            renderViewport();
        }
        window.requestAnimationFrame(function () {
            window.requestAnimationFrame(function () { window.markdownRenderer.isApplyingExternalScroll = false; });
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
            if (line.indexOf('#') === 0) return line;
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
            setupSpacers();
            var saved = blocks.length ? anchor() : null;
            total = Math.max(0, Math.floor(total));
            var oldTotal = blocks.length, countChanged = oldTotal !== total;
            blocks.length = total; heights.length = total;
            for (var i = oldTotal; i < total; i++) {
                blocks[i] = { hash: '', markdown: '', startLine: 0 };
                heights[i] = 32;
            }
            var metrics = estimationMetrics();
            for (var p = 0; p < patches.length; p++) {
                var patch = patches[p], index = patch.index;
                if (index < 0 || index >= total) continue;
                var hash = String(patch.hash);
                if (blocks[index].hash !== hash) {
                    var height = estimate(patch.markdown, metrics);
                    if (countChanged) heights[index] = height; else setHeight(index, height);
                }
                blocks[index] = { hash: hash, markdown: patch.markdown || '', startLine: patch.startLine || 0 };
            }
            if (countChanged) rebuildHeights();
            if (saved && total && renderedFirst >= 0) {
                var last = Math.min(renderedLast, total - 1);
                topSpacer.style.height = sum(Math.min(renderedFirst, total)) + 'px';
                bottomSpacer.style.height = Math.max(0, sum(total) - sum(last + 1)) + 'px';
                window.scrollTo(0, Math.max(0, contentTop() + sum(Math.min(saved.index, total - 1)) + saved.offset));
            }
            renderViewport();
        },
        setVirtualized: function (enabled) {
            changeVirtualization(enabled);
        },
        diagnostics: function () {
            return { total: blocks.length, mounted: mounted.size, first: renderedFirst, last: renderedLast, rendered: renderedCount, estimatedHeight: sum(blocks.length), virtualized: virtualized };
        },
        currentCenterSourceLine: currentCenterSourceLine,
        scrollToSourceLine: scrollToSourceLine
    };

    var restoreAfterPrint = false;
    var selectionExpanded = false;
    window.addEventListener('beforeprint', function () {
        restoreAfterPrint = virtualized;
        changeVirtualization(false);
    });
    window.addEventListener('afterprint', function () {
        if (restoreAfterPrint) changeVirtualization(true);
        restoreAfterPrint = false;
    });
    // Explicit whole-document selection may intentionally incur whole-document work.
    window.addEventListener('keydown', function (event) {
        if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'a' && virtualized) {
            selectionExpanded = true; changeVirtualization(false);
        }
    });
    document.addEventListener('selectionchange', function () {
        var selection = window.getSelection();
        if (selectionExpanded && (!selection || selection.isCollapsed)) {
            selectionExpanded = false; changeVirtualization(true);
        }
    });

    var markdownScrollSyncTimer = null;
    window.addEventListener('scroll', function () {
        scheduleViewport();
        if (window.markdownRenderer.isApplyingExternalScroll) return;
        if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.markdownScrollSync) return;
        window.clearTimeout(markdownScrollSyncTimer);
        markdownScrollSyncTimer = window.setTimeout(function () {
            window.webkit.messageHandlers.markdownScrollSync.postMessage(currentCenterSourceLine());
        }, 180);
    }, { passive: true });
    window.addEventListener('resize', function () {
        var saved = anchor();
        var metrics = estimationMetrics();
        heights = blocks.map(function (block) { return estimate(block.markdown, metrics); });
        rebuildHeights();
        if (blocks.length) {
            if (renderedFirst >= 0) {
                topSpacer.style.height = sum(renderedFirst) + 'px';
                bottomSpacer.style.height = Math.max(0, sum(blocks.length) - sum(renderedLast + 1)) + 'px';
            }
            window.scrollTo(0, Math.max(0, contentTop() + sum(saved.index) + saved.offset));
        }
        renderViewport(saved);
    }, { passive: true });
})();
