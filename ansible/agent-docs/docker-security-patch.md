# Docker Engine security patch

Reviewed 2026-10-19. `patch_docker.yml` audits **all inventory hosts**, including infrastructure and macOS, but patches only existing rootful Docker CE installations from the official signed Debian/Ubuntu stable APT repository. It never installs Docker on Docker-free or CLI-only hosts, adds keys/repositories, refreshes metadata, overrides holds, downgrades, prunes data, or reboots.

## Advisory and target

- [CVE-2026-92543](https://github.com/moby/moby/security/advisories/GHSA-7cfq-22r6-qp73): malicious DNS can disable registry TLS verification or permit HTTP fallback, leaking credentials or substituting images. Engine versions below **29.8.2** are affected.
- [CVE-2026-92542](https://github.com/moby/moby/security/advisories/GHSA-6m9p-4h64-m6vh): a local unprivileged user on a Linux Swarm node can inject frames into encrypted overlay networks. The advisory identifies **29.8.2** as patched.
- [Docker release notes](https://docs.docker.com/engine/release-notes/29/): 29.8.2 released September 30; the selected stable target **29.9.1** released October 14 and includes later fixes. The target is fixed, not `latest`.

This playbook targets those two **Engine** advisories. It does not claim to fix Docker Hub, Desktop, kernel, or independently packaged containerd/BuildKit vulnerabilities. In particular, the release notes' static-binary containerd update does not prove the fleet's separate `containerd.io` package is patched.

## Audit first

From `/home/daniel/lab`:

```bash
export ANSIBLE_CONFIG=/home/daniel/lab/ansible/ansible.cfg
ansible-playbook -i ansible/inventory.yml ansible/patch_docker.yml --list-hosts
ansible-playbook -i ansible/inventory.yml ansible/patch_docker.yml
ansible-playbook -i ansible/inventory.yml ansible/patch_docker.yml --check
```

Default and check mode only inspect installed packages/processes, cached authenticated metadata, signing keys, and the local rootful daemon socket. They do not download artifacts, contact registries, run images, refresh APT, install packages or restart services. Reports say `audit_only_not_patched`, not patched. Check mode remains read-only even if apply flags are supplied.

The October 19 audit reached all eight hosts. `microservice_host` and `game_server` have active CE **29.5.2** daemons; both are below the fix. The other six have no detected local Docker engine. Exact 29.9.1 CE, CLI and installed rootless-extras builds were available in both affected hosts' existing authenticated cached metadata. No rootless daemon was detected; upgrading the extras package is not verification of rootless daemons.

Unsupported Desktop, snap, distro, static or detected rootless installations fail for separate operator handling. A stopped CE daemon is left stopped and blocks apply; schedule its maintenance separately. Already newer installed **and running** engines are not downgraded. Version mismatches between binary and process require separate reconciliation.

## Review packages before approving maintenance

The six current artifacts have already been downloaded to a private controller directory, verified against each host's authenticated audit metadata, and reviewed as inert control archives on October 19. The checked-in receipt is `ansible/vars/docker_patch_review.yml`, with actual per-host versions and both artifact/control hashes. Total reviewed download size was 104,639,084 bytes. CE's scripts use standard service/init/AppArmor helpers and honor policy-rc.d; CLI and rootless-extras contain no maintainer scripts. No unexpected downloads or credential reads were found. Existing containerd 2.2.4 satisfies the new CE minimum 2.1.5; the cached resolver changes only CE, CLI and extras.

The following preparation is for reproducing that review or handling changed packages. It is **not performed by the playbook or by the fleet audit**. Run it only after approving the downloads and, if necessary, metadata refresh. No package installation is needed for preparation.

1. On each affected host, review the existing Docker `.list` entry and its signing key locally. The module requires a stable HTTPS source with explicit `signed-by`, Docker's primary fingerprint `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`, authenticated APT origins, and no insecure/trusted overrides. Review local APT hooks privately too; do not publish raw APT config, proxy settings or credentials. Deb822 sources or changed signing keys stop for review rather than being rewritten.
2. If the exact build is missing, explicitly refresh only the reviewed Docker index. In this lab the existing source is `/etc/apt/sources.list.d/docker.list`:

   ```bash
   sudo apt-get update -o Dir::Etc::sourcelist=sources.list.d/docker.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
   ```

   Then rerun the audit. Refreshing metadata is a separate opt-in operation, never an automatic fallback.
3. On the matching host, download the exact audit-plan packages to a private temporary directory as the normal user. Current builds are `5:29.9.1-1~ubuntu.24.04~noble` on `microservice_host` and `5:29.9.1-1~debian.12~bookworm` on `game_server`. For example, on the Ubuntu host:

   ```bash
   umask 077
   review_dir=$(mktemp -d)
   cd "$review_dir"
   build='5:29.9.1-1~ubuntu.24.04~noble'
   apt-get download "docker-ce=$build" "docker-ce-cli=$build" "docker-ce-rootless-extras=$build"
   sha256sum ./*.deb
   for deb in ./*.deb; do
     dpkg-deb -f "$deb" Package Version Depends Pre-Depends Conflicts
     dpkg-deb --ctrl-tarfile "$deb" > "$deb.control.tar"
     sha256sum "$deb.control.tar"
     tar -tvf "$deb.control.tar"
   done
   ```

   Use the Debian build on `game_server`. Compare each `.deb` digest with the authenticated audit plan. Inspect maintainer scripts as **text**, for example `tar -xOf package.deb.control.tar ./postinst`, and inspect any other executable control members present. Never source or execute them during review. Review dependency changes and the upstream/published artifacts for unexpected network downloads, credential reads, persistence, or unrelated behavior. The module rejects removals, new/unrelated dependencies, held packages and downgrades. If a future audit plan includes runtime/plugin upgrades, review those artifacts too, not just these three packages. Verify scripts respect `policy-rc.d`; custom hooks that bypass it require separate handling.
4. If builds or artifacts change, update the per-host receipt only after repeating review. Each package needs its exact `version`, authenticated `.deb` `sha256`, and decompressed control-tar `control_sha256`; include every package in that host's audit plan. The checked-in receipt contains the complete current entries, not placeholders. Missing or mismatched digests are rejected.

## Apply only in an approved maintenance window

**The following command upgrades packages and restarts Docker. It was not executed during implementation.** Both flags and the completed per-host receipt are required:

```bash
ansible-playbook -i ansible/inventory.yml ansible/patch_docker.yml \
  -e @ansible/vars/docker_patch_review.yml \
  -e docker_patch_apply=true -e docker_patch_restart_approved=true
```

Hosts run one at a time; any failure stops rollout. Downloads are verified against reviewed artifact/control hashes before scripts execute. An exact APT simulation must match the approved package set. Installation uses only verified local archives, no further downloads/removals/recommends, and preserves existing conffiles. A temporary `policy-rc.d=101` inhibits normal package-service restarts and is restored, including any pre-existing file or symlink; `NEEDRESTART_MODE=l` prevents needrestart's automatic restarts. Then Docker receives one explicit controlled restart. Reviewed scripts/hooks must honor these mechanisms. There is no zero-downtime or live-restore guarantee.

To verify the actual receipt and both flags without changing anything, add `--check` to that command. It still reports `audit_only_not_patched`.

APT/dpkg installation has no subprocess kill timeout. Do not wrap apply in a kill watchdog or auto-retry it after a lost SSH/controller connection. A disconnect is **unknown**, not success: inspect local apt/dpkg activity and temporary policy state before taking further action. Abnormal process termination can require restoring a saved `.docker-policy-*/original` file under `/usr/sbin`; do not remove it blindly. No automatic rollback is attempted.

The module verifies newly installed exact package versions, the on-disk daemon binary, and the running **local** daemon through `/var/run/docker.sock`, independent of `DOCKER_HOST`, contexts or client configuration. Pre-existing running container IDs must return within one minute or rollout stops. IDs stay inside the module and are not logged. This verifies workload presence, not application health; perform service-specific checks separately. Config, Docker data, networks and restart policies are not deliberately modified.

## Offline validation

```bash
python -m unittest discover -s ansible/tests -p 'test_patch_docker.py' -v
ansible-playbook -i ansible/inventory.yml ansible/patch_docker.yml --syntax-check
```

No new Python or Ansible dependencies are installed. Supported hosts need their existing `python3-apt`, GPG, APT, systemd and Docker packages.
