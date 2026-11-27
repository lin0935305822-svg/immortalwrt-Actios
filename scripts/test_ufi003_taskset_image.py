#!/usr/bin/env python3
"""Regression of the actual debugfs gate against small, unmounted ext4 images."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
cases = [
    ('relative-busybox', '../../bin/busybox', 0o755, True),
    ('absolute-busybox', '/bin/busybox', 0o755, True),
    ('nonexecutable-target', '../../bin/busybox', 0o644, False),
    ('writable-target', '../../bin/busybox', 0o777, False),
    ('broken-target', '../../bin/busybox', None, False),
    ('unexpected-target', '../../bin/other', 0o755, False),
    ('loop', 'taskset', 0o755, False),
    ('regular', None, 0o755, True),
    ('regular-nonexecutable', None, 0o644, False),
    ('missing-applet', None, None, False),
    ('directory-target', '../../bin/busybox', 'directory', False),
    ('symlink-target', '../../bin/busybox', 'symlink', False),
]
with tempfile.TemporaryDirectory(prefix='ufi003-taskset-image-') as directory:
    work = Path(directory)
    for label, link, mode, expected in cases:
        source = work / label
        (source / 'bin').mkdir(parents=True)
        (source / 'usr/bin').mkdir(parents=True)
        target = source / 'bin/busybox'
        if mode == 'directory':
            target.mkdir(mode=0o755)
        elif mode == 'symlink':
            target.symlink_to('other')
        elif mode is not None:
            target.write_text('fixture binary; never executed\n')
            target.chmod(mode)
        applet = source / 'usr/bin/taskset'
        if link is not None:
            applet.symlink_to(link)
        elif mode is not None:
            applet.write_text('fixture executable; never executed\n')
            applet.chmod(mode)
        image = work / (label + '.ext4')
        with image.open('wb') as stream:
            stream.truncate(8 * 1024 * 1024)
        subprocess.run(['mkfs.ext4', '-q', '-F', '-d', str(source), str(image)], check=True, capture_output=True)
        checked = subprocess.run(['/bin/sh', str(root / 'scripts/verify_ufi003_taskset_image.sh'), str(image)], capture_output=True, text=True)
        assert (checked.returncode == 0) == expected, (label, checked.stdout, checked.stderr)
    # debugfs can return zero for lookup errors: ensure the gate fails closed.
    bad = work / 'not-ext4'
    bad.write_text('not an image\n')
    checked = subprocess.run(['/bin/sh', str(root / 'scripts/verify_ufi003_taskset_image.sh'), str(bad)], capture_output=True)
    assert checked.returncode != 0
workflow = (root / '.github/workflows/Build_高通410 imm.yml').read_text()
assert '/bin/sh "$GITHUB_WORKSPACE/scripts/verify_ufi003_taskset_image.sh" "$image_raw"' in workflow
assert 'require_rootfs_exec /usr/bin/taskset' not in workflow
assert 'require_rootfs_exec /bin/busybox' in workflow
print(f'UFI003 taskset ext4 gate passed: {len(cases) + 1} positive/negative image cases')
