"""Ensure release shrinking preserves every metadata-loaded Xposed entry class."""
import struct
import sys
from zipfile import ZipFile


def u32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]


def classes(data):
    string_count, string_offset = struct.unpack_from('<II', data, 56)
    strings = []
    for index in range(string_count):
        offset = u32(data, string_offset + index * 4)
        while data[offset] & 128:
            offset += 1
        offset += 1  # UTF-16 length (ULEB128), followed by modified UTF-8.
        end = data.index(0, offset)
        strings.append(data[offset:end].decode('utf-8', errors='replace'))
    type_count, type_offset = struct.unpack_from('<II', data, 64)
    types = [strings[u32(data, type_offset + i * 4)] for i in range(type_count)]
    count, offset = struct.unpack_from('<II', data, 96)
    return {types[u32(data, offset + i * 32)] for i in range(count)}


with ZipFile(sys.argv[1]) as apk:
    entries = apk.read('META-INF/xposed/java_init.list').decode().splitlines()
    defined = set()
    for name in apk.namelist():
        if name.startswith('classes') and name.endswith('.dex') and '/' not in name:
            defined.update(classes(apk.read(name)))
    for entry in entries:
        entry = entry.strip()
        if entry and not entry.startswith('#'):
            if 'L' + entry.replace('.', '/') + ';' not in defined:
                raise SystemExit('Missing Xposed entry class in release DEX: ' + entry)
    print('Verified Xposed release entry classes')
