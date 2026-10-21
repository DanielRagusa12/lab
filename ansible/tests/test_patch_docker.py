"""Offline fixtures: no SSH, package commands, downloads or daemon calls."""
import hashlib
import tempfile
from types import SimpleNamespace
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'docker_patch', Path(__file__).parents[1] / 'library/docker_security_patch.py')
p = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(p)


def record(**changes):
    result = dict(name='docker-ce', version='5:29.9.1-1~ubuntu.24.04~noble',
                  sha256='a' * 64, trusted=True,
                  uri='https://download.docker.com/linux/ubuntu/dists/noble',
                  installed=True, remove=False, downgrade=False)
    result.update(changes)
    return result


class PolicyTests(unittest.TestCase):
    def test_absent(self):
        self.assertEqual(p.classify({}, None, None, False), 'absent')

    def test_cli_only(self):
        self.assertEqual(p.classify({}, None, '/usr/bin/docker', False), 'cli_only')

    def test_ce(self):
        self.assertEqual(p.classify({'docker-ce': '29.5.2'}, '/usr/bin/dockerd', True, False), 'ce')

    def test_static_daemon(self):
        self.assertEqual(p.classify({}, '/usr/local/bin/dockerd', True, False), 'unsupported')

    def test_alternate_variants(self):
        for variant in ('desktop', 'rootless', 'snap', 'distro'):
            with self.subTest(variant=variant):
                self.assertEqual(p.classify({}, True, True, True), 'unsupported')

    def test_epoch_and_vulnerable_version(self):
        self.assertEqual(p.version('5:29.5.2-1~debian.12~bookworm'), (29, 5, 2))
        self.assertLess(p.version('29.5.2'), p.MINIMUM)

    def test_newer(self):
        self.assertGreater(p.version('30.1.0'), p.TARGET)

    def test_reject_unparseable_version(self):
        with self.assertRaises(p.Blocked):
            p.version('unknown')

    def test_good_exact_plan(self):
        p.validate_plan([record()], set())

    def test_reject_bad_candidate(self):
        cases = [dict(version='5:29.8.1-1'), dict(version='5:29.8.2-1'),
                 dict(version='5:29.9.0-1'), dict(version='5:30.0.0-1'),
                 dict(trusted=False), dict(uri='https://evil.example/dists/noble'),
                 dict(uri='http://download.docker.com/linux/ubuntu/dists/noble'),
                 dict(sha256=''), dict(installed=False), dict(remove=True),
                 dict(downgrade=True), dict(name='unrelated-package')]
        for change in cases:
            with self.subTest(change=change), self.assertRaises(p.Blocked):
                p.validate_plan([record(**change)], set())

    def test_missing_candidate(self):
        with self.assertRaises(p.Blocked):
            p.validate_plan([], set())

    def test_held(self):
        with self.assertRaises(p.Blocked):
            p.validate_plan([record()], {'docker-ce'})

    def test_audit_requires_no_approval(self):
        self.assertFalse(p.require_approval(False, False, {}, [record()]))

    def test_apply_requires_restart_approval(self):
        with self.assertRaises(p.Blocked):
            p.require_approval(True, False, {}, [record()])

    def test_apply_requires_exact_review(self):
        for approval in ({}, {'docker-ce': {'version': 'wrong'}},
                         {'docker-ce': {'version': record()['version'], 'sha256': 'a' * 64}}):
            with self.subTest(approval=approval), self.assertRaises(p.Blocked):
                p.require_approval(True, True, approval, [record()])

    def test_reviewed_apply(self):
        approval = {'docker-ce': {k: record()[k] for k in ('version', 'sha256')}}
        approval['docker-ce']['control_sha256'] = 'b' * 64
        self.assertTrue(p.require_approval(True, True, approval, [record()]))

    def test_post_daemon_old(self):
        with self.assertRaises(p.Blocked):
            p.verify_after({'id1'}, {'id1'}, (29, 5, 2))

    def test_post_missing_workload(self):
        with self.assertRaises(p.Blocked):
            p.verify_after({'id1'}, set(), p.TARGET)

    def test_post_success(self):
        p.verify_after({'id1'}, {'id1', 'id2'}, p.TARGET)

    def test_simulation_exact_set(self):
        p.validate_transaction('Inst docker-ce [5:29.5.2-1] (' + record()['version'] + ' Docker:stable [amd64])', [record()])

    def test_simulation_rejects_extra_missing_removal(self):
        for output in ('', 'Remv docker-ce [old]', 'Inst unexpected (1.0 source [amd64])',
                       'Inst docker-ce (wrong source [amd64])', 'Inst unparsable'):
            with self.subTest(output=output), self.assertRaises(p.Blocked):
                p.validate_transaction(output, [record()])

    def test_policy_restores_original_on_exception(self):
        with tempfile.TemporaryDirectory() as tmp:
            policy = Path(tmp) / 'policy-rc.d'
            policy.write_text('# original policy\n')
            policy.chmod(0o740)
            with self.assertRaises(RuntimeError):
                with p.inhibit_restarts(policy):
                    self.assertEqual(policy.read_text(), '#!/bin/sh\nexit 101\n')
                    raise RuntimeError('simulated apt failure')
            self.assertEqual(policy.read_text(), '# original policy\n')
            self.assertEqual(policy.stat().st_mode & 0o777, 0o740)

    def test_policy_preserves_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            original = Path(tmp) / 'original'
            original.write_text('original')
            policy = Path(tmp) / 'policy-rc.d'
            policy.symlink_to(original)
            with p.inhibit_restarts(policy):
                self.assertFalse(policy.is_symlink())
            self.assertTrue(policy.is_symlink())
            self.assertEqual(original.read_text(), 'original')

    def test_policy_removes_temporary_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            policy = Path(tmp) / 'policy-rc.d'
            with p.inhibit_restarts(policy):
                self.assertTrue(policy.exists())
            self.assertFalse(policy.exists())


class SourceTests(unittest.TestCase):
    source = 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable\n'
    fingerprint = '9DC858229FC7DD38854AE2D88D81803C0EBFCD88'

    def invoke(self, source=None, config='', key=None):
        with tempfile.TemporaryDirectory() as tmp:
            entry = Path(tmp) / 'docker.list'
            entry.write_text(self.source if source is None else source)
            key_output = 'pub::::::::::\nfpr:::::::::' + (key or self.fingerprint) + ':\n'
            with patch.object(p, 'run', side_effect=[config, key_output]):
                p.validate_sources([entry])

    def test_signed_official_source(self):
        self.invoke()

    def test_trusted_yes_bypass(self):
        with self.assertRaises(p.Blocked):
            self.invoke(self.source.replace('arch=amd64', 'arch=amd64 trusted=yes'))

    def test_missing_signed_by(self):
        with self.assertRaises(p.Blocked):
            self.invoke(self.source.replace(' signed-by=/etc/apt/keyrings/docker.asc', ''))

    def test_global_insecure_override(self):
        with self.assertRaises(p.Blocked):
            self.invoke(config='Acquire::AllowInsecureRepositories "true";')

    def test_wrong_signing_key(self):
        with self.assertRaises(p.Blocked):
            self.invoke(key='A' * 40)


class ArtifactApplyTests(unittest.TestCase):
    def attempt(self, bad_artifact=False, bad_control=False, bad_plan=False, install_error=False):
        artifact, control = b'inert artifact fixture', b'inert control fixture'
        r = record(sha256=hashlib.sha256(artifact).hexdigest())
        if bad_artifact:
            r['sha256'] = '0' * 64
        approval = {'docker-ce': {'control_sha256': hashlib.sha256(control).hexdigest()}}
        if bad_control:
            approval['docker-ce']['control_sha256'] = '0' * 64
        installed = []
        original_policy = p.inhibit_restarts
        with tempfile.TemporaryDirectory() as tmp:
            policy = Path(tmp) / 'policy-rc.d'
            policy.write_text('original policy')

            def subprocess_run(args, **kw):
                if args[:2] == ['apt-get', 'download']:
                    (Path(kw['cwd']) / 'docker-ce_fixture.deb').write_bytes(artifact)
                    return SimpleNamespace(returncode=0)
                self.assertEqual(args[:2], ['dpkg-deb', '--ctrl-tarfile'])
                return SimpleNamespace(returncode=0, stdout=control)

            def command(args, **kw):
                if '-s' in args:
                    return '' if bad_plan else 'Inst docker-ce [old] (' + r['version'] + ' Docker [amd64])'
                self.assertEqual(policy.read_text(), '#!/bin/sh\nexit 101\n')
                self.assertIsNone(kw['timeout'])
                self.assertIn('--no-download', args)
                installed.append(args)
                if install_error:
                    raise p.Blocked('simulated install failure')
                return ''

            with patch.object(p.subprocess, 'run', side_effect=subprocess_run), \
                 patch.object(p, 'run', side_effect=command), \
                 patch.object(p, 'inhibit_restarts', side_effect=lambda: original_policy(policy)):
                try:
                    p.apply_packages([r], approval)
                finally:
                    self.assertEqual(policy.read_text(), 'original policy')
                    if bad_artifact or bad_control or bad_plan:
                        self.assertEqual(installed, [])
        self.assertEqual(len(installed), 1)

    def test_verified_artifacts_install_once(self):
        self.attempt()

    def test_artifact_hash_blocks_install(self):
        with self.assertRaises(p.Blocked):
            self.attempt(bad_artifact=True)

    def test_control_hash_blocks_install(self):
        with self.assertRaises(p.Blocked):
            self.attempt(bad_control=True)

    def test_changed_resolver_plan_blocks_install(self):
        with self.assertRaises(p.Blocked):
            self.attempt(bad_plan=True)

    def test_install_failure_restores_policy(self):
        with self.assertRaises(p.Blocked):
            self.attempt(install_error=True)


class Finished(BaseException):
    def __init__(self, failed, result):
        self.failed, self.result = failed, result


class FakeModule:
    check_mode = False
    params = dict(apply=False, restart_approved=False, reviewed_packages={})

    def exit_json(self, **kw):
        raise Finished(False, kw)

    def fail_json(self, **kw):
        raise Finished(True, kw)


def ce_host(binary='29.5.2', running='29.5.2', active=True):
    return dict(os='Linux', method='ce', packages={'docker-ce': '5:' + binary + '-1'},
                binary_version=binary, daemon_version=running, active=active, status='not_patched')


class FlowTests(unittest.TestCase):
    def invoke(self, host, apply=False, check=False, restart=False):
        fake = FakeModule()
        fake.params = dict(apply=apply, restart_approved=restart, reviewed_packages={})
        fake.check_mode = check
        with patch.object(p, 'AnsibleModule', return_value=fake), \
             patch.object(p, 'inspect_host', return_value=host), \
             patch.object(p, 'package_plan', return_value=[record()]) as plan, \
             patch.object(p, 'apply_packages') as install, \
             patch.object(p, 'snapshot') as snapshot, \
             patch.object(p, 'run') as command:
            with self.assertRaises(Finished) as done:
                p.main()
            install.assert_not_called()
            command.assert_not_called()
            snapshot.assert_not_called()
            return done.exception, plan

    def test_default_audit_does_not_mutate(self):
        done, _ = self.invoke(ce_host())
        self.assertFalse(done.failed)
        self.assertFalse(done.result['changed'])
        self.assertEqual(done.result['status'], 'audit_only_not_patched')

    def test_check_mode_even_with_apply_does_not_mutate(self):
        done, _ = self.invoke(ce_host(), apply=True, restart=True, check=True)
        self.assertFalse(done.failed)
        self.assertEqual(done.result['status'], 'audit_only_not_patched')

    def test_stopped_daemon_never_starts(self):
        done, plan = self.invoke(ce_host(active=False), apply=True)
        self.assertTrue(done.failed)
        plan.assert_not_called()

    def test_missing_approval_never_mutates(self):
        done, _ = self.invoke(ce_host(), apply=True)
        self.assertTrue(done.failed)
        self.assertFalse(done.result['changed'])

    def test_newer_no_downgrade(self):
        done, plan = self.invoke(ce_host('30.0.0', '30.0.0'), apply=True)
        self.assertFalse(done.failed)
        plan.assert_not_called()
        self.assertEqual(done.result['status'], 'already_at_or_above_target')

    def test_new_binary_old_process_not_claimed_patched(self):
        done, plan = self.invoke(ce_host('29.9.1', '29.5.2'), apply=True)
        self.assertTrue(done.failed)
        plan.assert_not_called()

    def test_old_binary_new_process_not_downgraded(self):
        done, plan = self.invoke(ce_host('29.5.2', '30.0.0'), apply=True)
        self.assertTrue(done.failed)
        plan.assert_not_called()

    def test_absent_no_install(self):
        done, plan = self.invoke(dict(method='absent', status='no_local_engine'), apply=True)
        self.assertFalse(done.failed)
        plan.assert_not_called()

    def test_approved_apply_rechecks_binary_and_packages(self):
        fake = FakeModule()
        approval = {k: record()[k] for k in ('version', 'sha256')}
        approval['control_sha256'] = 'b' * 64
        fake.params = dict(apply=True, restart_approved=True, reviewed_packages={'docker-ce': approval})
        post = ce_host('29.9.1', '29.9.1')
        post['packages']['docker-ce'] = record()['version']
        with patch.object(p, 'AnsibleModule', return_value=fake), \
             patch.object(p, 'inspect_host', side_effect=[ce_host(), post]) as inspection, \
             patch.object(p, 'package_plan', return_value=[record()]), \
             patch.object(p, 'apply_packages') as install, \
             patch.object(p, 'snapshot', side_effect=[((29, 5, 2), {'id1'}), (p.TARGET, {'id1'})]), \
             patch.object(p, 'run') as command:
            with self.assertRaises(Finished) as done:
                p.main()
            self.assertFalse(done.exception.failed)
            self.assertEqual(done.exception.result['binary_version'], '29.9.1')
            self.assertEqual(done.exception.result['status'], 'patched_runtime_verified')
            self.assertEqual(inspection.call_count, 2)
            install.assert_called_once()
            command.assert_called_once_with(['systemctl', 'restart', 'docker.service'])

    def test_apply_failure_never_restarts_or_claims_patched(self):
        fake = FakeModule()
        approval = {k: record()[k] for k in ('version', 'sha256')}
        approval['control_sha256'] = 'b' * 64
        fake.params = dict(apply=True, restart_approved=True, reviewed_packages={'docker-ce': approval})
        with patch.object(p, 'AnsibleModule', return_value=fake), \
             patch.object(p, 'inspect_host', return_value=ce_host()), \
             patch.object(p, 'package_plan', return_value=[record()]), \
             patch.object(p, 'apply_packages', side_effect=p.Blocked('simulated install failure')), \
             patch.object(p, 'snapshot', return_value=((29, 5, 2), {'id1'})), \
             patch.object(p, 'run') as command:
            with self.assertRaises(Finished) as done:
                p.main()
            self.assertTrue(done.exception.failed)
            self.assertNotEqual(done.exception.result['status'], 'patched_runtime_verified')
            command.assert_not_called()

    def test_post_failure_is_fatal_and_serial_rollout_is_configured(self):
        import yaml
        play = yaml.safe_load((Path(__file__).parents[1] / 'patch_docker.yml').read_text())[0]
        self.assertEqual(play['serial'], 1)
        self.assertTrue(play['any_errors_fatal'])
        self.assertEqual(play['hosts'], 'all')
        self.assertEqual(play['tasks'][-1]['when'], 'docker_patch_result is failed')
        fake = FakeModule()
        approval = {k: record()[k] for k in ('version', 'sha256')}
        approval['control_sha256'] = 'b' * 64
        fake.params = dict(apply=True, restart_approved=True, reviewed_packages={'docker-ce': approval})
        for after in (((29, 5, 2), {'id1'}), (p.TARGET, set())):
            with self.subTest(after=after), \
                 patch.object(p, 'AnsibleModule', return_value=fake), \
                 patch.object(p, 'inspect_host', return_value=ce_host()), \
                 patch.object(p, 'package_plan', return_value=[record()]), \
                 patch.object(p, 'apply_packages'), \
                 patch.object(p, 'snapshot', side_effect=[((29, 5, 2), {'id1'})] + [after] * 12), \
                 patch.object(p, 'run'), patch.object(p.time, 'sleep'):
                with self.assertRaises(Finished) as done:
                    p.main()
                self.assertTrue(done.exception.failed)
                self.assertNotEqual(done.exception.result['status'], 'patched_runtime_verified')


if __name__ == '__main__':
    unittest.main()
