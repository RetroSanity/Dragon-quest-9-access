#!/usr/bin/env python3
"""Writes mod/manifest.txt: the mod's version (from dq9-access.lua), the version of its
changes to the game's code (GAME_PATCH below; raise it when mod/installer/game-patch changes,
and ACCESS_PATCH in game-patch/files/runtime/access.c with it), and every file in mod/ with
its size. The game's auto update reads it from GitHub when it starts."""
import os, re
GAME_PATCH = 3
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mod')
lua = open(os.path.join(root, 'dq9-access.lua'), encoding='latin-1').read()
version = re.search(r'^MOD_VERSION = "([^"]+)"', lua, re.M).group(1)
lines = [f'version {version}', f'patch {GAME_PATCH}']
for dirpath, dirs, files in os.walk(root):
    dirs.sort()
    for f in sorted(files):
        p = os.path.join(dirpath, f)
        rel = os.path.relpath(p, root).replace(os.sep, '/')
        # (the NVDA library is in use while the game runs, so it is not updated; the installer puts it in)
        if rel in ('manifest.txt', 'nvdaControllerClient64.dll'):
            continue
        lines.append(f'file {os.path.getsize(p)} {rel}')
open(os.path.join(root, 'manifest.txt'), 'w', newline='\n').write('\n'.join(lines) + '\n')
print('\n'.join(lines[:3]), f'... {len(lines) - 2} files')
