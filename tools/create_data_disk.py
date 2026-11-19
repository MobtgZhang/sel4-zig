#!/usr/bin/env python3
"""Create a dedicated bounded data volume. Existing files are never overwritten."""
import argparse
import os
from pathlib import Path
import struct
import zlib

SECTORS = 513


def create(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    header = bytearray(512)
    header[:8] = b'ZIGVOL01'
    struct.pack_into('<I', header, 8, SECTORS)
    struct.pack_into('<I', header, 508, zlib.crc32(header[:508]))
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(header)
        stream.truncate(SECTORS * 512)
        stream.flush()
        os.fsync(stream.fileno())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path')
    args = parser.parse_args()
    create(args.path)
