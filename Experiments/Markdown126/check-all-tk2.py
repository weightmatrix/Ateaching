"""Guard the production routing; the archived implementation must stay uncompiled."""
from pathlib import Path
import re, subprocess
source = Path('ATeaching/MarkdownEditorView.swift').read_text()
assert not re.search(r'\blayoutManager\b|\bNSLayoutManager\b|\bMarkdownNativeTextEditor\s*\(|\bMarkdownTextView\s*\(', '\n'.join(l for l in source.splitlines() if not l.lstrip().startswith('//')))
assert 'UITextView(usingTextLayoutManager: true)' in source
for name in ['MarkdownSourceEditorContainer', 'MarkdownInstantEditorContainer']:
    start = source.index('struct '+name+': View {')
    body = source[start:source.index('\n}\n',start)]
    assert 'MarkdownTextKit2PlainModeView(' in body
    assert 'commitBridge: commitBridge' in body
old = subprocess.check_output(['git','show','codex/pre-126-all-textkit2-20261117:ATeaching/MarkdownEditorView.swift']).decode()
start = old.index('struct MarkdownNativeTextEditor: NSViewRepresentable {')
end = old.index('\n#endif\n\n// MARK: - NSAttributedString',start)
assert Path('Archives/MarkdownTextKit1/MarkdownNativeTextEditor.swift.txt').read_text() == old[start:end]
print('PASS: every normal Markdown editor route uses TK2; no compiled TK1 layout calls; archive matches rollback tag')
