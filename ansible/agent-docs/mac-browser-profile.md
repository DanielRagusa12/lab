# Mac browser-worker profile

`deploy_mac_browser_profile.yml` stages `files/mac-browser-worker.mobileconfig` in the SSH user's Downloads folder. It does not install it, open a GUI app, download a utility, or require sudo. It is separate from `cleanup_mac_mini.yml`, so profile staging does not apply power or sharing changes.

## Deploy

From `ansible/`:

```bash
ansible-playbook -i inventory.yml deploy_mac_browser_profile.yml --check --diff
ansible-playbook -i inventory.yml deploy_mac_browser_profile.yml
```

Through the existing VNC-over-SSH connection:

1. Open `~/Downloads/Homelab-browser-worker.mobileconfig` in Finder.
2. Open System Settings > General > Device Management.
3. Inspect and install **Homelab browser worker**. It is an unsigned local profile, not an MDM enrollment, certificate, proxy, or VPN.
4. Verify the installed profile's restrictions and the affected features in System Settings. Successful Ansible staging does not mean restrictions are installed or effective.

Subsequent runs update only the staged file. Changed profile contents require another manual approval. Stable identifiers and UUIDs are used for updates.

## Scope

One `com.apple.applicationaccess` payload restricts Siri, Writing Tools, Genmoji, Image Playground, external intelligence integrations through Siri, manual Mail summaries, Mail smart replies, Notes transcription summaries, Safari summaries, automatic diagnostic submission, and personalized Apple advertising.

This is not a complete Apple Intelligence off switch. Automatic Mail summaries, notification summaries, inline predictions, Photos features, and other unlisted features may remain enabled. For complete user-facing disablement, turn off Apple Intelligence through System Settings as well. Optional analytics toggles beyond automatic diagnostic submission remain manual.

No model deletion, MobileAsset download overrides, private Apple APIs, daemon installation, launchctl changes, cache cleanup, snapshot deletion, security weakening, or network changes. No restrictions target MLX, Metal, third-party model downloads, or browser automation. Apple Foundation Models-based functionality is distinct from independently downloaded MLX models.

## Compatibility

Reviewed against Apple's restrictions schema at commit `09f249a06e7e3289930bf6d05f38fb562f748ebf`:

https://github.com/apple/device-management/blob/09f249a06e7e3289930bf6d05f38fb562f748ebf/mdm/profiles/com.apple.applicationaccess.yaml

The payload permits manual macOS installation. The selected keys have macOS support and do not override that with a manual-install prohibition. Siri and AI keys are deprecated since macOS 26.4 in favor of declarative MDM configurations, but this schema does not mark them removed. This lab has no MDM. Confirm their behavior on the actual Mac after installation; do not treat schema validation as a runtime test. The playbook refuses macOS outside the reviewed 27.x family.

## Undo

Remove **Homelab browser worker** in System Settings > General > Device Management. Removal lifts this profile's restrictions; existing user preferences and other profiles still apply. No previous preferences are overwritten or journaled by this profile.

Deleting the file from Downloads or reverting the Git change does not remove an installed profile. Any manual Apple Intelligence toggle change is separate and must be undone separately.
