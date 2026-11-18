#!/usr/bin/env python3
"""Fail closed on stale/missing native components, ABI, dependencies and 16KB layout."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

p=argparse.ArgumentParser()
p.add_argument('apk',type=Path)
p.add_argument('--readelf',default='readelf')
p.add_argument('--zipalign',required=True)
a=p.parse_args()
errors=[]
system={'libandroid.so','libc.so','libdl.so','liblog.so','libm.so','libz.so','libmediandk.so',
        'libEGL.so','libGLESv2.so','libGLESv3.so','libOpenSLES.so','libvulkan.so','libaaudio.so','libjnigraphics.so','libnativewindow.so'}
with zipfile.ZipFile(a.apk) as apk, tempfile.TemporaryDirectory(prefix='zero-apk-check-') as tmp:
    native=[n for n in apk.namelist() if n.startswith('lib/') and n.endswith('.so')]
    libs={Path(n).name for n in native}
    for required in ['libzero.so','libzeroremux.so','libflutter.so']:
        if required not in libs: errors.append(f'missing {required}')
    for name in native:
        if not name.startswith('lib/arm64-v8a/'): errors.append(f'unexpected ABI: {name}')
        path=Path(tmp)/Path(name).name
        path.write_bytes(apk.read(name))
        header=subprocess.check_output([a.readelf,'-hW',str(path)],text=True)
        if 'ELF64' not in header or 'AArch64' not in header: errors.append(f'wrong ELF ABI: {name}')
        segments=subprocess.check_output([a.readelf,'-lW',str(path)],text=True)
        loads=[line.split() for line in segments.splitlines() if line.strip().startswith('LOAD ')]
        if not loads: errors.append(f'no LOAD segments: {name}')
        for load in loads:
            alignment=int(load[-1],16)
            offset,address=int(load[1],16),int(load[2],16)
            if alignment<16384 or offset%16384!=address%16384: errors.append(f'not 16KB aligned: {name}')
        dynamic=subprocess.check_output([a.readelf,'-dW',str(path)],text=True)
        for dependency in re.findall(r'\(NEEDED\).*\[(.*?)\]',dynamic):
            if dependency not in libs|system: errors.append(f'{name}: missing {dependency}')
        if Path(name).name=='libzeroremux.so':
            symbols=subprocess.check_output([a.readelf,'--dyn-syms','-W',str(path)],text=True)
            if not re.search(r'\bGLOBAL\s+DEFAULT\s+\d+\s+zero_remux\b',symbols): errors.append('missing zero_remux export')
        print(f'checked {name}')
result=subprocess.run([a.zipalign,'-c','-P','16','-v','4',str(a.apk)],capture_output=True,text=True)
if result.returncode: errors.append('APK zip alignment failed: '+result.stdout+result.stderr)
if errors: raise SystemExit('\n'.join(errors))
print(f'Validated {len(native)} arm64 libraries and APK 16KB alignment')
