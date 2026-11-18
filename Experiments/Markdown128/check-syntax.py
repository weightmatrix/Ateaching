from pathlib import Path
import shutil, subprocess, tempfile
repo=Path.cwd()
with tempfile.TemporaryDirectory(prefix='markdown127-') as tmp:
 root=Path(tmp);(root/'Sources/Probe').mkdir(parents=True)
 (root/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"Probe", dependencies:[.package(url:"https://github.com/swiftlang/swift-markdown.git",exact:"0.9.0")], targets:[.executableTarget(name:"Probe",dependencies:[.product(name:"Markdown",package:"swift-markdown")])])
''')
 shutil.copy2(repo/'ATeaching/NormalMarkdownSyntax.swift',root/'Sources/Probe/NormalMarkdownSyntax.swift')
 (root/'Sources/Probe/main.swift').write_text((repo/'Experiments/Markdown128/SyntaxTests.swift').read_text())

 subprocess.run(['swift','run','-c','release','--package-path',str(root),'--scratch-path','/tmp/markdown128-test-build','-j','2','Probe',str(repo/'Experiments/Markdown128/syntax-results.json')],check=True)
