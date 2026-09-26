#!/usr/bin/env python3
"""Renders the Android reference scenes with the Swift port and compares them pixel by pixel.

    tools/compare_renders.py [--only SUBSTRING] [--jobs N]

The Android side comes from the Android project's ReferenceRenderCapture (an instrumentation
test on a Wear OS emulator): pull its reference-renders folder to renders/android/. This script
builds sundial-render (release), renders each scene in renders/android/scenes.tsv to
renders/swift/, and writes renders/compare/<scene>.png (Android | Swift | difference) and
renders/compare/summary.tsv, worst first. Needs Pillow and Google Chrome.
"""
import argparse
import concurrent.futures
import csv
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID = os.path.join(ROOT, 'renders', 'android')
SWIFT = os.path.join(ROOT, 'renders', 'swift')
COMPARE = os.path.join(ROOT, 'renders', 'compare')
TOOLCHAIN = os.path.expanduser('~/swift/swift-6.4.0-RELEASE-ubuntu26.04/usr/bin')

# The scenes ReferenceRenderCapture draws, and how they read on the command line.
INSTANT = '2026-09-26T03:30:00Z'
ZONE = 'America/Los_Angeles'
BIRTH_DATE = '1990-04-18'
HOROSCOPE = ('The Moon waxes toward full in your house of craft, and a patient hand finds the grain '
             'of the work. Let an old plan rest one more day; tomorrow it will ask for you.')
STYLES = {'VOID_BLACK': 'voidBlack', 'CRIMSON_NEBULA': 'crimsonNebula', 'DEEP_SPACE_BLUE': 'deepSpaceBlue',
          'COSMIC_VIOLET': 'cosmicViolet', 'SOLAR_BRONZE': 'solarBronze', 'BRASS_WATCH': 'brassWatch'}
LAYOUTS = {'PHONE': 'phone', 'WATCH_ROUND': 'watchRound', 'WATCH_RECT': 'watchRect'}
VIEWS = {'HELIOCENTRIC': 'helio', 'GEOCENTRIC': 'earth', 'GALACTIC': 'galactic'}


def build():
    env = dict(os.environ, PATH=TOOLCHAIN + os.pathsep + os.environ['PATH'])
    # A build directory of its own, so it never waits on another build of the package.
    scratch = ['--scratch-path', os.path.join(ROOT, '.build-compare')]
    subprocess.run(['swift', 'build', '-c', 'release', '--product', 'sundial-render', *scratch], cwd=ROOT, env=env,
                   check=True)
    path = subprocess.run(['swift', 'build', '-c', 'release', '--show-bin-path', *scratch], cwd=ROOT, env=env,
                          check=True, capture_output=True, text=True).stdout.strip()
    return os.path.join(path, 'sundial-render')


def render(binary, scene, instant):
    name = scene['name']
    args = [binary, '--view', VIEWS[scene['state']], '--style', STYLES[scene['style']],
            '--layout', LAYOUTS[scene['layout']], '--width', scene['width'], '--height', scene['height'],
            '--density', scene['density'], '--instant', instant, '--zone', ZONE,
            '--assets', os.path.join(ROOT, 'Assets'),
            '--out', os.path.join(SWIFT, name + '.svg'), '--png', os.path.join(SWIFT, name + '.png')]
    if scene['astrology'] == 'true':
        args += ['--astrology', '--birth-date', BIRTH_DATE, '--horoscope', HOROSCOPE]
    if scene['clock'] == 'true':
        args.append('--clock')
    if scene['ambient'] == 'true':
        args.append('--ambient')
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        return name, result.stderr.strip() or 'failed'
    return name, None


def compare(name):
    android = Image.open(os.path.join(ANDROID, name + '.png')).convert('RGB')
    swift = Image.open(os.path.join(SWIFT, name + '.png')).convert('RGB').resize(android.size)
    diff = ImageChops.difference(android, swift)
    grey = diff.convert('L')
    pixels = grey.width * grey.height
    histogram = grey.histogram()
    mean = sum(i * n for i, n in enumerate(histogram)) / pixels
    differing = sum(histogram[48:]) / pixels
    sheet = Image.new('RGB', (android.width * 3 + 20, android.height), 'white')
    sheet.paste(android, (0, 0))
    sheet.paste(swift, (android.width + 10, 0))
    sheet.paste(ImageOps.autocontrast(grey).convert('RGB'), (2 * android.width + 20, 0))
    sheet.save(os.path.join(COMPARE, name + '.png'))
    return mean, differing


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--only', default='')
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--ambient-instant', default=None,
                        help='the instant the Android ambient scenes were captured at (they show the live clock)')
    args = parser.parse_args()
    os.makedirs(SWIFT, exist_ok=True)
    os.makedirs(COMPARE, exist_ok=True)
    scenes = [row for row in csv.DictReader(open(os.path.join(ANDROID, 'scenes.tsv')), delimiter='\t')
              if args.only in row['name']]
    binary = build()

    def job(scene):
        instant = args.ambient_instant if scene['ambient'] == 'true' and args.ambient_instant else INSTANT
        return render(binary, scene, instant)

    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        failures = [(n, e) for n, e in pool.map(job, scenes) if e]
    for name, error in failures:
        print(f'{name}: {error}', file=sys.stderr)
    rows = []
    for scene in scenes:
        if any(scene['name'] == n for n, _ in failures):
            continue
        mean, differing = compare(scene['name'])
        rows.append((scene['name'], mean, differing))
    rows.sort(key=lambda r: -r[2])
    with open(os.path.join(COMPARE, 'summary.tsv'), 'w') as out:
        out.write('scene\tmean_difference\tshare_of_pixels_off_by_48+\n')
        for name, mean, differing in rows:
            out.write(f'{name}\t{mean:.2f}\t{differing:.4f}\n')
    for name, mean, differing in rows:
        print(f'{differing:7.2%}  {mean:6.2f}  {name}')
    if failures:
        sys.exit(f'{len(failures)} scenes failed to render')


if __name__ == '__main__':
    main()
