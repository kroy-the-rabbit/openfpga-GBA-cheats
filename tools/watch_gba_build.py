#!/usr/bin/env python3
"""Watch one sisko GBA job, verify its package, and notify this desktop.

Never writes the card. Results and fetched artifacts stay under build/watch/.
The process can outlive the chat turn; result.json is its durable handoff.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HOST = 'root@10.50.1.246'
SSH = ['ssh', '-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', HOST]
SCP = ['scp', '-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10']
CORNERS = ('8_slow_1100mv_85c', '8_slow_1100mv_0c', 'MIN_fast_1100mv_85c', 'MIN_fast_1100mv_0c')


def run(argv, timeout=60):
    return subprocess.run(argv, cwd=ROOT, check=True, capture_output=True, text=True, timeout=timeout).stdout


def source(commit, path):
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def validate(folder, commit, *, baseline=False):
    report = (folder / 'report.txt').read_text()
    if not re.search(r'^commit:\s+' + re.escape(commit[:7]) + r'\s*$', report, re.M):
        raise ValueError('Timing report commit does not match the requested source')
    timing = {}
    for kind in ('Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width'):
        match = re.search(r'^' + kind + r'\s+(-?\d+\.\d+) ns', report, re.M)
        if not match:
            raise ValueError(f'Missing {kind} timing result')
        timing[kind] = float(match[1])
    failures = {k: v for k, v in timing.items() if v < 0}
    if failures:
        raise ValueError('Timing failed: ' + ', '.join(f'{k} {v:+.3f} ns' for k, v in failures.items()))
    fit = re.search(r'Logic utilization \(in ALMs\)\s*:\s*([\d,]+) / ([\d,]+)', report)
    if not fit or int(fit[1].replace(',', '')) > int(fit[2].replace(',', '')):
        raise ValueError('Missing or over-capacity ALM fit')
    snapshot = {}
    for corner in (() if baseline else CORNERS):
        text = (folder / 'timing-paths' / f'snapshot-{corner}.txt').read_text()
        match = re.search(r'Report Path: Found 1 paths\. Longest delay is (\d+\.\d+)', text)
        if not match:
            raise ValueError(f'Missing snapshot data path at {corner}')
        snapshot[corner] = float(match[1])
        # Two 74.25 MHz host clocks provide ~26.94 ns. Reserve >6 ns
        # for launch/capture overhead, skew and uncertainty rather than
        # qualifying the bundle against the entire nominal interval.
        if snapshot[corner] >= 20.0:
            raise ValueError(f'Snapshot routing exceeds 20 ns budget at {corner}')
    files = run(['git', 'ls-tree', '-r', '--name-only', commit, 'pkg'], timeout=30).splitlines()
    core_path = 'pkg/Cores/kroy.GBA/core.json'
    core = json.loads(source(commit, core_path))
    bitname = core['core']['cores'][0]['filename']
    bitrel = 'Cores/kroy.GBA/' + bitname
    expected = {name.removeprefix('pkg/') for name in files} | {bitrel}
    archives = list(folder.glob('*.zip'))
    if len(archives) != 1:
        raise ValueError('Expected exactly one package')
    with zipfile.ZipFile(archives[0]) as package:
        names = [i.filename for i in package.infolist() if not i.is_dir()]
        if len(names) != len(set(names)) or set(names) != expected or package.testzip():
            raise ValueError('Package contents or CRC validation failed')
        for path in files:
            relative = path.removeprefix('pkg/')
            actual = package.read(relative)
            original = source(commit, path)
            if path == core_path:
                parsed = json.loads(actual)
                metadata = parsed['core']['metadata']
                if metadata['version'] != core['core']['metadata']['version'] + '.' + commit[:7]:
                    raise ValueError('Package version does not match source')
                metadata['version'] = core['core']['metadata']['version']
                metadata['date_release'] = core['core']['metadata']['date_release']
                if parsed != core:
                    raise ValueError('Packaged core.json has unexpected changes')
            elif actual != original:
                raise ValueError(f'Package source mismatch: {relative}')
        bitstream = (folder / bitname).read_bytes()
        if len(bitstream) < 1000000 or package.read(bitrel) != bitstream:
            raise ValueError('Packaged bitstream does not match fetched artifact')
        stage = folder / 'sd'
        staged_files = 0
        for name in names:
            if not name.startswith(('Assets/', 'Cores/', 'Platforms/')):
                continue
            # Paths came from the exact git tree plus its declared bitstream.
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(package.read(name))
            staged_files += 1
    return dict(timing_ns=timing, snapshot_delay_ns=snapshot, package_files=len(expected),
                staged_files=staged_files,
                bitstream_sha256=hashlib.sha256(bitstream).hexdigest(), staged=str(stage))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('job')
    parser.add_argument('commit')
    parser.add_argument('--baseline', action='store_true',
                        help='Verify a control build without snapshot RTL; report baseline-passed, never ready-to-write')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,39}', args.job):
        parser.error('Invalid job name')
    if not re.fullmatch(r'[0-9a-f]{40}', args.commit):
        parser.error('Use the full commit hash')
    key = f'pocket-gba-gba-{args.job}-{args.commit[:12]}'
    remote = f'/root/pocket-builds/checkouts/{key}/build/gba'
    done = f'/root/pocket-builds/jobs/{key}.done'
    folder = ROOT / 'build/watch' / key
    folder.mkdir(parents=True, exist_ok=True)
    result_path = folder / 'result.json'
    state = dict(state='watching', job=key, commit=args.commit, pid=os.getpid(),
                 started=datetime.now(timezone.utc).isoformat(), card_written=False,
                 baseline=args.baseline)

    def save():
        state['updated'] = datetime.now(timezone.utc).isoformat()
        temp = folder / 'result.tmp'
        temp.write_text(json.dumps(state, indent=2) + '\n')
        temp.replace(result_path)
        print(json.dumps(state), flush=True)

    def notify(title, message):
        try:
            result = subprocess.run(['notify-send', '--app-name=Pocket GBA', '--expire-time=0', title, message],
                                    capture_output=True, text=True, timeout=15)
            state['notification_delivered'] = result.returncode == 0
            if result.returncode:
                state['notification_error'] = result.stderr.strip()
        except (OSError, subprocess.SubprocessError) as exc:
            state['notification_delivered'] = False
            state['notification_error'] = str(exc)
        save()

    save()
    deadline = time.monotonic() + 10800
    errors = 0
    try:
        notify('Pocket GBA watcher started', f'Watching {args.commit[:7]} on sisko. Completion will be reported here; the card will stay untouched.')
        while time.monotonic() < deadline:
            try:
                response = run(SSH + [f'if test -f {done}; then cat {done}; else echo state=running; fi'], timeout=30)
                errors = 0
            except (subprocess.SubprocessError, OSError) as exc:
                errors += 1
                state['last_poll_error'] = str(exc)
                save()
                if errors >= 5:
                    raise RuntimeError('Cannot reach sisko after five attempts; build status is unknown') from exc
                time.sleep(45)
                continue
            (folder / 'job-status.txt').write_text(response)
            if 'rc=' not in response:
                time.sleep(45)
                continue
            fields = dict(line.split('=', 1) for line in response.splitlines() if '=' in line)
            if fields.get('commit') != args.commit:
                raise ValueError('Completed job has the wrong commit')
            state.update(state='checking', build_rc=int(fields['rc']))
            save()
            # Save the job log even if compilation failed before making a report.
            run(SCP + [f'{HOST}:/root/pocket-builds/jobs/{key}.log', str(folder / 'build.log')], timeout=120)
            report_exists = run(SSH + [f'if test -f {remote}/report.txt; then echo yes; fi']).strip() == 'yes'
            if report_exists:
                run(SCP + [f'{HOST}:{remote}/report.txt', str(folder / 'report.txt')])
            paths_exist = run(SSH + [f'if test -d {remote}/work/timing-paths; then echo yes; fi']).strip() == 'yes'
            if paths_exist:
                run(SCP + ['-r', f'{HOST}:{remote}/work/timing-paths', str(folder)], timeout=120)
            analysis_exists = run(SSH + [f'if test -f {remote}/path-analysis.log; then echo yes; fi']).strip() == 'yes'
            if analysis_exists:
                run(SCP + [f'{HOST}:{remote}/path-analysis.log', str(folder / 'path-analysis.log')])
            if state['build_rc'] != 0:
                if report_exists:
                    text = (folder / 'report.txt').read_text()
                    failures = re.findall(r'^(Setup|Hold|Recovery|Removal|Minimum Pulse Width)\s+(-\d+\.\d+) ns', text, re.M)
                    if failures:
                        raise ValueError('Timing failed: ' + ', '.join(f'{k} {v} ns' for k, v in failures))
                if analysis_exists:
                    errors = [line.strip() for line in (folder / 'path-analysis.log').read_text().splitlines()
                              if line.startswith('Error') or line.startswith(('Pattern experiment requires', 'Header diagnostic requires'))]
                    if errors:
                        raise RuntimeError('Post-fit analysis failed: ' + errors[0])
                raise RuntimeError(f'Build exited {state["build_rc"]}; see {folder / "build.log"}')
            core = json.loads(source(args.commit, 'pkg/Cores/kroy.GBA/core.json'))
            version = core['core']['metadata']['version'] + '.' + args.commit[:7]
            bitname = core['core']['cores'][0]['filename']
            artifacts = [bitname, f'kroy.GBA_{version}.zip']
            if not args.baseline and not analysis_exists:
                raise ValueError('Missing post-fit path analysis log')
            for name in artifacts:
                run(SCP + [f'{HOST}:{remote}/{name}', str(folder / name)], timeout=120)
            state.update(validate(folder, args.commit, baseline=args.baseline),
                         state='baseline-passed' if args.baseline else 'ready-to-write')
            save()
            if args.baseline:
                notify('Pocket GBA control build passed',
                       f'{args.commit[:7]} passed timing and package checks. This is the existing baseline, not a new diagnostic build. Card untouched. Result: {result_path}')
                return
            notify('Pocket GBA ready for card',
                   f'{args.commit[:7]} passed timing, snapshot routing and package checks. {state["staged_files"]} files staged. Card untouched. Result: {result_path}')
            return
        raise TimeoutError('Watcher reached three hours; build status needs inspection')
    except Exception as exc:
        state.update(state='not-ready', reason=str(exc))
        save()
        notify('Pocket GBA needs attention', f'{args.commit[:7]}: {exc}. Card untouched. Result: {result_path}')


if __name__ == '__main__':
    main()
