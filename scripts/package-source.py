"""Create a native-app source archive without private website files."""
from pathlib import Path
import zipfile
root = Path(__file__).resolve().parents[1]
releases = root / 'releases'
releases.mkdir(exist_ok=True)
entries = ['Package.swift', 'README.md', 'LICENSE', 'CHANGELOG.md', 'CONTRIBUTING.md', 'AGENTS.md',
           'build.sh', 'ScrollTest.html', 'Resources', 'design', 'THIRD_PARTY_NOTICES.md',
           'Sources', 'Tests', 'scripts', 'docs', '.github', '.gitignore']
with zipfile.ZipFile(releases / 'SmoothWheel-source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for entry in entries:
        base = root / entry
        for path in sorted(base.rglob('*')) if base.is_dir() else [base]:
            if not path.is_file() or path.name == '.DS_Store' or 'downloads' in path.relative_to(root).parts or 'qa' in path.relative_to(root).parts:
                continue
            archive.write(path, Path('SmoothWheel') / path.relative_to(root))
print('Packaged native app source only.')
