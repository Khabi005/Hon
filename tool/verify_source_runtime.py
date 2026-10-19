#!/usr/bin/env python3
"""Verify actual release DEX class definitions, not mere class-name strings.
Usage: python3 tool/verify_source_runtime.py path/to/release.apk
The historical release had the names in DEX strings but removed the classes.
"""
import struct
import sys
import zipfile


def dex_classes(data):
    if not data.startswith(b'dex\n'):
        raise ValueError('Unsupported DEX format')
    def word(offset):
        return struct.unpack_from('<I', data, offset)[0]
    def text(index):
        offset = word(word(60) + 4 * index)
        while data[offset] & 0x80:
            offset += 1
        offset += 1
        return data[offset:data.index(b'\0', offset)].decode('utf-8')
    types = [text(word(word(68) + 4 * index)) for index in range(word(64))]
    return {types[word(word(100) + 32 * index)] for index in range(word(96))}


def verify(path):
    with zipfile.ZipFile(path) as apk:
        classes = set().union(*(dex_classes(apk.read(name))
            for name in apk.namelist() if name.endswith('.dex')))
        # LuaJ 3.0.1 has generated reflective class lookups in its libraries.
        required = {'Lorg/luaj/vm2/lib/' + name + ';' for name in (
            'Bit32Lib$Bit32LibV', 'Bit32Lib$Bit32Lib2', 'StringLib',
            'TableLib', 'BaseLib', 'PackageLib', 'LibFunction')}
        missing = required - classes
        if missing:
            raise SystemExit('Missing Lua runtime classes: ' + ', '.join(sorted(missing)))
        for name in ('Novel', 'NovelInfo', 'NovelChapter', 'GET', 'POST', 'map', 'pageOfElem'):
            assert apk.read(f'shosetsu/{name}.lua'), f'Missing helper: {name}'
        print(f'PASS {path}: required Lua classes defined in DEX; standard helpers packaged')


if __name__ == '__main__':
    verify(sys.argv[1])
