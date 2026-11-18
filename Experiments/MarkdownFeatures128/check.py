from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as work:
    root = Path(work)
    scripts = ('marked.min.js', 'mermaid.min.js', 'markdown-renderer.js')
    for name in scripts:
        shutil.copyfile(repo / 'ATeaching/MarkdownAssets' / name, root / name)
    shutil.copyfile(Path(__file__).with_name('test.js'), root / 'test.js')
    (root / 'test.html').write_text('<meta charset="utf-8"><div id="md-root"></div>' + ''.join(f'<script src="{name}"></script>' for name in scripts))
    subprocess.run(['swiftc', '-parse-as-library', str(repo / 'Experiments/MarkdownVirtualization/PreviewTests.swift'), '-o', str(root / 'check')], check=True)
    subprocess.run([str(root / 'check'), work], check=True, timeout=45)
