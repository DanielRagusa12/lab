#!/usr/bin/python3
"""Fail-closed Docker CE patching. No registry or Docker client configuration access."""
from contextlib import contextmanager
import hashlib
import functools
import glob
import http.client
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import tempfile
import time
from pathlib import Path

from ansible.module_utils.basic import AnsibleModule

TARGET = (29, 9, 1)
MINIMUM = (29, 8, 2)
ALLOWED = {
    'docker-ce', 'docker-ce-cli', 'docker-ce-rootless-extras',
    'containerd.io', 'docker-buildx-plugin', 'docker-compose-plugin',
}


class Blocked(Exception):
    pass


def run(args, allowed=(0,), timeout=120):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                           env={**os.environ, 'LC_ALL': 'C', 'DEBIAN_FRONTEND': 'noninteractive',
                                'NEEDRESTART_MODE': 'l'})
    except (OSError, subprocess.TimeoutExpired):
        raise Blocked('Local command unavailable or timed out: ' + Path(args[0]).name)
    if p.returncode not in allowed:
        # Never echo stderr, source URLs, command arguments or package hooks.
        raise Blocked('Local command failed: ' + Path(args[0]).name)
    return p.stdout


def version(text):
    match = re.search(r'(?:^|\s|:)(\d+)\.(\d+)\.(\d+)(?=$|[-+~\s,])', text)
    if not match:
        raise Blocked('Unrecognized Docker version')
    return tuple(map(int, match.groups()))


def classify(packages, daemon, cli, alternate):
    if alternate:
        return 'unsupported'
    if 'docker-ce' in packages:
        return 'ce' if daemon else 'unsupported'
    if daemon:
        return 'unsupported'
    return 'cli_only' if cli else 'absent'


def daemon_get(path):
    class LocalConnection(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(10)
            self.sock.connect('/var/run/docker.sock')
    try:
        conn = LocalConnection('localhost', timeout=10)
        conn.request('GET', path)
        response = conn.getresponse()
        if response.status != 200:
            raise Blocked('Local daemon API request failed')
        return json.loads(response.read())
    except (OSError, ValueError, http.client.HTTPException):
        raise Blocked('Cannot verify local rootful daemon through its Unix socket')
    finally:
        if 'conn' in locals():
            conn.close()


def snapshot():
    v = version(daemon_get('/version')['Version'])
    ids = {item['Id'] for item in daemon_get('/containers/json?all=0')}
    return v, ids


def verify_after(before_ids, after_ids, daemon_version):
    if daemon_version < TARGET:
        raise Blocked('Running local daemon is below the reviewed target')
    if before_ids - after_ids:
        raise Blocked('Previously running containers are missing; rollout stopped, investigate locally')


def validate_plan(records, held):
    if not records:
        raise Blocked('No exact target package plan available in existing APT metadata')
    for r in records:
        if r['name'] not in ALLOWED or not r['installed'] or r.get('remove'):
            raise Blocked('Resolver requests new, removed, or unrelated packages; manual review required')
        if r['name'] in held:
            raise Blocked('A required package is held; holds will not be overridden')
        if not r['trusted'] or not re.fullmatch(
                r'https://download\.docker\.com/linux/(ubuntu|debian)/dists/[^\s]+', r['uri']):
            raise Blocked('Package does not come from an authenticated official Docker repository')
        if not re.fullmatch(r'[a-fA-F0-9]{64}', r['sha256']):
            raise Blocked('Package metadata lacks a SHA256 digest')
        if r['name'].startswith('docker-ce') and version(r['version']) != TARGET:
            raise Blocked('Engine, CLI and installed rootless extras must match exactly 29.9.1')
        if r.get('downgrade'):
            raise Blocked('Downgrades are prohibited')


def require_approval(apply, restart, review, records):
    if not apply:
        return False
    if not restart:
        raise Blocked('Apply requires explicit restart approval; package hooks may restart workloads')
    for r in records:
        approved = review.get(r['name'], {})
        if any(approved.get(k) != r[k] for k in ('version', 'sha256')):
            raise Blocked('Exact package version and artifact digest require operator review approval')
        if not re.fullmatch(r'[a-f0-9]{64}', approved.get('control_sha256', '')):
            raise Blocked('Reviewed maintainer-script control archive digest is required')
    return True


def validate_sources(files=None):
    # python-apt also calls a trusted=yes source trusted. Reject bypasses and
    # require the known Docker signing key rather than relying on that flag.
    settings = run(['apt-config', 'dump'])
    for line in settings.splitlines():
        if re.search(r'(AllowInsecure|AllowWeak|AllowUnauthenticated|AllowDowngradeToInsecure)', line, re.I):
            if not re.search(r'"(?:false|0)";', line, re.I):
                raise Blocked('APT authentication bypass configuration requires manual review')
    if files is None:
        files = [Path('/etc/apt/sources.list')] + list(Path('/etc/apt/sources.list.d').glob('*.list'))
        files += list(Path('/etc/apt/sources.list.d').glob('*.sources'))
    keys = set()
    for path in files:
        if not path.exists():
            continue
        text = '\n'.join(line.split('#', 1)[0] for line in path.read_text().splitlines())
        for line in text.splitlines():
            if 'download.docker.com' not in line:
                continue
            m = re.fullmatch(r'\s*deb\s+\[([^]]+)\]\s+https://download\.docker\.com/linux/(?:ubuntu|debian)\s+\S+\s+stable\s*', line)
            if not m:
                raise Blocked('Docker source must be an explicitly signed stable HTTPS .list entry; review source format')
            options = dict(part.split('=', 1) for part in m[1].split() if '=' in part)
            if set(options) - {'arch', 'signed-by'} or not options.get('signed-by', '').startswith('/'):
                raise Blocked('Docker source options are not approved or lack an explicit signing key')
            keys.add(options['signed-by'])
    if not keys:
        raise Blocked('No supported explicitly signed official Docker source found')
    for key in keys:
        with tempfile.TemporaryDirectory(prefix='docker-key-audit-') as home:
            output = run(['gpg', '--no-options', '--homedir', home, '--batch', '--with-colons', '--show-keys', key])
        fingerprints = []
        primary = False
        for line in output.splitlines():
            if line.startswith('pub:'):
                primary = True
            elif line.startswith('sub:'):
                primary = False
            elif line.startswith('fpr:') and primary:
                fingerprints.append(line.split(':')[9])
                primary = False
        if fingerprints != ['9DC858229FC7DD38854AE2D88D81803C0EBFCD88']:
            raise Blocked('Docker repository signing key differs from the reviewed fingerprint')


def package_plan(packages):
    validate_sources()
    try:
        import apt
        import apt_pkg
    except ImportError:
        raise Blocked('Existing python3-apt is required; this playbook does not install it')
    cache = apt.Cache()
    for name in ('docker-ce', 'docker-ce-cli', 'docker-ce-rootless-extras'):
        if name not in packages:
            if name != 'docker-ce-rootless-extras':
                raise Blocked('Supported CE installation requires an existing CLI package')
            continue
        matches = [v for v in cache[name].versions if version(v.version) == TARGET]
        if not matches:
            raise Blocked('Exact 29.9.1 build missing from cached APT metadata; refresh separately after source review')
        selected = max(matches, key=functools.cmp_to_key(lambda a, b: apt_pkg.version_compare(a.version, b.version)))
        cache[name].candidate = selected
        cache[name].mark_install(auto_fix=True, auto_inst=False, from_user=True)
    records = []
    for pkg in sorted(cache.get_changes(), key=lambda p: p.name):
        candidate = pkg.candidate
        # Restrict all listed origins, not just the preferred one. APT index files
        # must already be authenticated; this does not add or refresh repositories.
        origins = candidate.origins
        uri = 'https://download.docker.com/linux/' + platform_distro() + '/dists/' + origins[0].archive if origins else ''
        official = bool(origins) and all(o.trusted and o.site == 'download.docker.com' and
                                        o.origin == 'Docker' and o.component == 'stable' for o in origins)
        sha = candidate.record.get('SHA256', '')
        # Also verify actual archive URI, never return it to logs.
        official = official and bool(candidate.uris) and all(
            u.startswith('https://download.docker.com/linux/' + platform_distro() + '/') for u in candidate.uris)
        records.append(dict(name=pkg.name, version=candidate.version, sha256=sha,
                            trusted=official, uri=uri, installed=pkg.is_installed,
                            remove=pkg.marked_delete,
                            downgrade=bool(pkg.is_installed and apt_pkg.version_compare(candidate.version, pkg.installed.version) < 0)))
    held = set(run(['apt-mark', 'showhold']).split())
    validate_plan(records, held)
    return records


def platform_distro():
    data = {}
    for line in Path('/etc/os-release').read_text().splitlines():
        if '=' in line:
            key, val = line.split('=', 1)
            data[key] = val.strip('"')
    if data.get('ID') not in ('ubuntu', 'debian'):
        raise Blocked('Only existing official Docker CE Debian/Ubuntu APT installations are supported')
    return data['ID']


def inspect_host():
    packages = {}
    if shutil.which('dpkg-query'):
        out = run(['dpkg-query', '-W', '-f=${binary:Package}\t${Version}\t${db:Status-Status}\n'])
        for line in out.splitlines():
            parts = line.split('\t')
            if len(parts) == 3 and parts[2] == 'installed':
                name = parts[0].split(':')[0]
                if name in ALLOWED or name in ('docker.io', 'moby-engine', 'docker-desktop', 'podman-docker'):
                    packages[name] = parts[1]
    daemon = shutil.which('dockerd')
    cli = shutil.which('docker')
    alternate = any(p in packages for p in ('docker.io', 'moby-engine', 'docker-desktop', 'podman-docker'))
    alternate |= Path('/Applications/Docker.app').exists() or Path('/snap/docker').exists()
    # Look only at process owners/names, never command lines or environments.
    processes = run(['ps', '-eo', 'uid=,comm='])
    rootless = any(len(p := line.split()) == 2 and p[0] != '0' and
                   Path(p[1]).name in ('dockerd', 'rootlesskit') for line in processes.splitlines())
    alternate |= rootless
    # Detect common inactive user installations without reading client configs.
    for pattern in ('/run/user/*/docker.sock', '/home/*/.config/systemd/user/docker.service',
                    '/root/.config/systemd/user/docker.service', '/home/*/bin/dockerd'):
        alternate |= bool(glob.glob(pattern))
    engine_present = daemon or Path('/var/run/docker.sock').exists() or any(
        line.split() and Path(line.split()[-1]).name == 'dockerd' for line in processes.splitlines())
    kind = classify(packages, engine_present, cli, alternate)
    result = dict(os=platform.system(), method=kind, packages=packages, status='not_patched')
    if kind in ('absent', 'cli_only'):
        result['status'] = 'no_local_engine'
        return result
    if kind != 'ce' or platform.system() != 'Linux':
        raise Blocked('Unsupported Docker installation detected; no migration or patch attempted')
    if not daemon or os.path.realpath(daemon) != '/usr/bin/dockerd':
        raise Blocked('Docker daemon binary is not the supported package-owned path')
    owner = run(['dpkg-query', '-S', '/usr/bin/dockerd']).strip()
    if owner != 'docker-ce: /usr/bin/dockerd':
        raise Blocked('Docker daemon binary ownership is unexpected')
    result['binary_version'] = '.'.join(map(str, version(run([daemon, '--version']))))
    active = run(['systemctl', 'is-active', 'docker.service'], allowed=(0, 3, 4)).strip() == 'active'
    result['active'] = active
    if active:
        daemon_version, _ = snapshot()
        result['daemon_version'] = '.'.join(map(str, daemon_version))
    return result


@contextmanager
def inhibit_restarts(path=Path('/usr/sbin/policy-rc.d')):
    # Same policy_rc_d=101 convention used by ansible.builtin.apt. Preserve
    # existing bytes, permissions and symlinks by renaming, not rewriting them.
    with tempfile.TemporaryDirectory(prefix='.docker-policy-', dir=path.parent) as tmp:
        backup = Path(tmp) / 'original'
        existed = os.path.lexists(path)
        if existed:
            os.replace(path, backup)
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o755)
            with os.fdopen(fd, 'w') as stream:
                stream.write('#!/bin/sh\nexit 101\n')
            yield
        finally:
            path.unlink(missing_ok=True)
            if existed:
                os.replace(backup, path)


def validate_transaction(simulated, records):
    installs = {}
    for line in simulated.splitlines():
        if line.startswith('Remv '):
            raise Blocked('APT simulation would remove a package')
        if line.startswith('Inst '):
            m = re.match(r'Inst (\S+)(?: \[[^]]+\])? \((\S+)', line)
            if not m:
                raise Blocked('Unrecognized APT simulation')
            installs[m[1].split(':')[0]] = m[2]
    if installs != {r['name']: r['version'] for r in records}:
        raise Blocked('APT transaction differs from the reviewed exact package plan')


def apply_packages(records, review):
    # Download only AFTER explicit approval, inspect archives as data before
    # allowing any maintainer script or new binary to execute.
    with tempfile.TemporaryDirectory(prefix='docker-security-review-') as tmp:
        for r in records:
            subprocess_result = subprocess.run(
                ['apt-get', 'download', r['name'] + '=' + r['version']], cwd=tmp,
                capture_output=True, timeout=120)
            if subprocess_result.returncode:
                raise Blocked('Approved package download failed; no install attempted')
        for r in records:
            files = list(Path(tmp).glob(r['name'] + '_*.deb'))
            if len(files) != 1:
                raise Blocked('Downloaded artifact set does not match approved plan')
            path = files[0]
            if hashlib.sha256(path.read_bytes()).hexdigest() != r['sha256']:
                raise Blocked('Downloaded package SHA256 does not match approved metadata')
            control = subprocess.run(['dpkg-deb', '--ctrl-tarfile', str(path)], capture_output=True, timeout=30)
            if control.returncode or hashlib.sha256(control.stdout).hexdigest() != review[r['name']]['control_sha256']:
                raise Blocked('Package control archive differs from reviewed maintainer scripts')
        # Simulate immediately before installation and reject all unapproved changes.
        simulated = run(['apt-get', '-s', '--no-install-recommends', '--only-upgrade', '--no-remove',
                         'install'] + [r['name'] + '=' + r['version'] for r in records])
        validate_transaction(simulated, records)
        # Install only verified local archives. No watchdog kills apt/dpkg while
        # maintainer scripts may still run; a disconnected controller is an
        # unknown transaction requiring local inspection, never an automatic retry.
        with inhibit_restarts():
            run(['apt-get', '-y', '--no-download', '--no-remove', '--no-install-recommends',
                 '-o', 'Dpkg::Options::=--force-confold', 'install'] +
                [str(next(Path(tmp).glob(r['name'] + '_*.deb'))) for r in records], timeout=None)


def main():
    module = AnsibleModule(argument_spec=dict(
        apply=dict(type='bool', default=False),
        restart_approved=dict(type='bool', default=False),
        reviewed_packages=dict(type='dict', default={}),
    ), supports_check_mode=True)
    result = {}
    mutation_started = False
    try:
        result = inspect_host()
        if result['method'] in ('absent', 'cli_only'):
            module.exit_json(changed=False, **result)
        binary = version(result['binary_version'])
        if not result['active']:
            # Do not connect to a socket that might activate a stopped service.
            raise Blocked('Installed engine is stopped; left stopped, not runtime-verified or patched')
        running = version(result['daemon_version'])
        if binary >= TARGET and running >= TARGET:
            result['status'] = 'already_at_or_above_target'
            module.exit_json(changed=False, **result)
        if binary >= TARGET or running >= TARGET:
            raise Blocked('Package/runtime version mismatch; separate reviewed reconciliation needed, no downgrade')
        records = package_plan(result['packages'])
        result['plan'] = [{k: r[k] for k in ('name', 'version', 'sha256')} for r in records]
        result['status'] = 'audit_only_not_patched'
        # Check mode never downloads, installs or restarts, even with approvals.
        if module.check_mode or not module.params['apply']:
            module.exit_json(changed=False, **result)
        require_approval(True, module.params['restart_approved'], module.params['reviewed_packages'], records)
        _, before = snapshot()
        mutation_started = True
        apply_packages(records, module.params['reviewed_packages'])
        run(['systemctl', 'restart', 'docker.service'])
        for attempt in range(12):
            try:
                after_version, after = snapshot()
                verify_after(before, after, after_version)
                break
            except Blocked:
                if attempt == 11:
                    raise
                time.sleep(5)
        post = inspect_host()
        if not post.get('active') or version(post['binary_version']) < TARGET:
            raise Blocked('Post-install package binary or active state verification failed')
        if any(post['packages'].get(r['name']) != r['version'] for r in records):
            raise Blocked('Post-install package versions differ from the approved plan')
        result.update(post)
        result.update(status='patched_runtime_verified', daemon_version='.'.join(map(str, after_version)))
        module.exit_json(changed=True, **result)
    except Blocked as exc:
        module.fail_json(msg=str(exc), changed=mutation_started, **result)
    except Exception:
        module.fail_json(msg='Inspection or patch failed; inspect locally without exposing credentials',
                         changed=mutation_started, **result)


if __name__ == '__main__':
    main()
