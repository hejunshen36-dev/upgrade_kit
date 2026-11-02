"""ADB UI helper; physical devices require an explicit opt-in flag.

Taps/swipes derive from fresh UI XML bounds. Use only on the user-authorized
test device and target application.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--adb', required=True)
parser.add_argument('--serial', required=True)
parser.add_argument('--allow-physical-device', action='store_true')
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--name', required=True)
parser.add_argument('action', choices=['snapshot', 'tap', 'fill', 'swipe', 'key'])
parser.add_argument('--text')
parser.add_argument('--hint')
parser.add_argument('--value')
parser.add_argument('--set-checked', choices=['true', 'false'])
parser.add_argument('--direction', choices=['up', 'down'], default='up')
args = parser.parse_args()
if not args.serial.startswith('emulator-') and not args.allow_physical_device:
    raise SystemExit('Physical-device use requires --allow-physical-device.')
args.out.mkdir(parents=True, exist_ok=True)

def adb(*parts):
    return subprocess.check_output([args.adb, '-s', args.serial, *parts])

def tree(suffix):
    for attempt in range(3):
        raw = adb('exec-out', 'uiautomator', 'dump', '/dev/tty').decode()
        if '<hierarchy' in raw and '</hierarchy>' in raw:
            xml = raw[raw.index('<hierarchy'):raw.index('</hierarchy>') + len('</hierarchy>')]
            (args.out / f'{args.name}{suffix}.xml').write_text(xml)
            return ET.fromstring(xml)
        (args.out / f'{args.name}{suffix}-dump-error-{attempt}.txt').write_text(raw)
        time.sleep(0.5)
    raise SystemExit('UI hierarchy unavailable after 3 snapshots; action is not repeated.')

def bounds(node):
    return [int(value) for value in re.findall(r'\d+', node.attrib['bounds'])]

if args.action == 'key':
    adb('shell', 'input', 'keyevent', args.value)
elif args.action != 'snapshot':
    root = tree('-before')
    nodes = list(root.iter('node'))
    if args.action == 'swipe':
        node = next(node for node in nodes if node.attrib.get('scrollable') == 'true')
        x1, y1, x2, y2 = bounds(node)
        x = (x1 + x2) // 2
        top, bottom = y1 + (y2-y1)*25//100, y1 + (y2-y1)*75//100
        start, end = (bottom, top) if args.direction == 'up' else (top, bottom)
        adb('shell', 'input', 'swipe', str(x), str(start), str(x), str(end), '400')
    else:
        node = next(node for node in nodes if
            (args.hint is not None and node.attrib.get('hint') == args.hint) or
            (args.text is not None and args.text in [node.attrib.get('text'), node.attrib.get('content-desc')]))
        if node.attrib.get('enabled') == 'false':
            raise SystemExit('Target is disabled: ' + str(node.attrib))
        x1, y1, x2, y2 = bounds(node)
        should_tap = True
        if args.set_checked is not None:
            if node.attrib.get('checkable') != 'true':
                raise SystemExit('Target is not checkable.')
            should_tap = node.attrib.get('checked') != args.set_checked
        if should_tap:
            adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        if args.action == 'fill':
            adb('shell', 'input', 'keycombination', '113', '29')
            adb('shell', 'input', 'keyevent', '67')
            adb('shell', 'input', 'text', args.value)
            adb('shell', 'input', 'keyevent', '4')

root = tree('')
(args.out / f'{args.name}.png').write_bytes(adb('exec-out', 'screencap', '-p'))
for node in root.iter('node'):
    values = node.attrib
    if any(values.get(key) for key in ['text', 'content-desc', 'hint']):
        print(json.dumps({key:values.get(key) for key in ['class','text','content-desc','hint','enabled','checked','bounds']}, ensure_ascii=False))
