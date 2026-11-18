const sources = [
  '#无空格',
  '# 有空格',
  '###',
  '`**literal**`',
  '| A | B |\n| :--- | ---: |\n| **粗体** | `code` |',
  '3. third\n4. fourth',
  '- [x] done\n- [ ] pending',
  '~~删除~~',
  '```mermaid\nflowchart TD\nA --> B\n```',
  '```mermaid\nerDiagram\nSTUDENT ||--o{ RECORD : has\n```',
  '```mermaid\ninvalid diagram\n```'
];
const renderer = window.markdownRenderer;
renderer.setVirtualized(false);
renderer.apply(sources.length, sources.map((markdown, index) => ({ markdown, index, hash: index, startLine: index * 5 })));
await renderer.whenDiagramsReady();
const assert = (ok, label) => { if (!ok) throw new Error(label); };
assert(document.querySelector('section p').textContent === '#无空格', 'unspaced heading');
assert(document.querySelectorAll('h1,h2,h3').length === 1, 'valid heading and bare marker');
assert(Array.from(document.querySelectorAll('code')).some(code => code.textContent === '**literal**'), 'literal code');
assert(document.querySelector('.md-table-scroll th[align=right]'), 'table alignment');
assert(document.querySelector('td strong') && document.querySelector('td code'), 'table inline formatting');
assert(document.querySelector('ol[start="3"] li'), 'ordered list numbering');
assert(document.querySelectorAll('input[type=checkbox]').length === 2, 'task list');
assert(document.querySelector('del'), 'strikethrough');
assert(document.querySelectorAll('.md-mermaid svg').length === 2, 'flowchart and ER');
assert(document.querySelector('[data-mermaid-error] code').textContent.includes('invalid diagram'), 'bad diagram source fallback');
return { passed: sources.length };
