# IcyOS installer

Personal, online-first NixOS installer. **Whole-disk erasure only; test in a disposable VM first.** No dual boot, partition preservation, RAID, automatic recovery/reformatting, token resets or automatic commits. A richer TUI and fully offline ISO are deferred.

## Build and run

```sh
nix build .#installer
./result/bin/run-installer --help
nix build .#iso --out-link result-iso
```

New installer/module files must be tracked (or explicitly staged with `git add -- installer modules/nixos/identity.nix modules/home-manager/identity.nix`) before Git-backed flake evaluation. Do not use `path:` on a Git checkout containing unlocked key caches: it includes `.git` in the store input. The installer always uses Git-aware references.

Boot the ISO in UEFI mode, configure networking (`nmtui`/`nmcli`), then run `sudo run-installer`. A controlling terminal is required for private password/PIN/recovery interactions. Avoid recording the terminal during enrollment.

The installer fetches the repository's default-branch HEAD and freezes that commit, **without updating flake.lock**. The selected repository must expose installer API 1. Until these changes are committed/pushed, explicitly use the embedded/development snapshot:

```sh
sudo run-installer --no-update
# Or select a development checkout deliberately:
sudo run-installer --source /path/to/nix-files --no-update
```

Embedded snapshots do not contain unlocked bookmarks, private identities or Git history. An embedded-snapshot installation is reduced/secret-free; fetching packages still requires internet. Online clones and explicitly selected local checkouts preserve normal Git history; dirty local sources receive a content hash. An unavailable/incompatible upstream revision stops before erasure. A different installer version triggers a warning and an exact-local-revision restart command; downloaded code is never silently executed.

### Safe dry-run

```sh
nix run .#installer -- --source "$PWD" --no-update --dry-run --manifest installer/example.json
```

This copies sources into a private `/var/tmp/icy-install-*` workspace, generates a new host and evaluates it. It does **not** format, mount, enroll tokens, unlock secrets, import signing keys, set passwords or install. The example disk is deliberately fictitious. `revision` is replaced by the selected Git commit or a complete snapshot content hash. Normal interactive runs derive stateVersion from the selected pinned release; preserve that value on future upgrades.

## Architecture and generated configuration

- `main.py`: Gum wizard, isolated source preparation, private credential flows and coordinator.
- `model.py`: validated nonsecret manifest, swap guidelines, unique partition identities and host generation.
- `schema.nix`: dynamically discovers real NixOS/Home Manager `my.*` metadata. Current booleans, strings and string lists are editable; future unsupported types are explained, not evaluated as arbitrary expressions.
- `storage.py`: read-only inventory and fail-closed whole-disk guards, including loop-backed ISO media, mounted filesystems, active swap, mappers and holders. Copy-to-RAM boot with no identifiable backing medium is intentionally unsupported. Partition UUID and mapper collisions stop before formatting.
- `templates/`: normal host files importing shared repository modules and JSON option data.
- `hibernation.nix`: blocks hibernation when the physical swapfile offset differs from the booted generation.

Implementation controls moved to `icy.internal.*`, outside the feature namespace. Personal identity/secrets use `icy.*`; available features remain `my.*`. Home Manager's default preset now uses overridable defaults. The wizard derives preset values from the actual module configuration rather than duplicating its feature list. Final Nix evaluation/build is authoritative and catches conflicts/dependencies (for example Docker + Podman).

The engine generates and evaluates a complete host, builds its closure and locked Disko runner, then shows disk model/serial/capacity/partitions. It requires the exact target path and rechecks identity/use immediately before Disko. Formatting and mounting occur only there. Disk-derived hardware/resume metadata is finalized and rebuilt afterward; that last step can still fail after erasure.

`/`, `/home`, `/nix`, `/swap` are Btrfs subvolumes; EFI is approximately 1 GiB. Optional LUKS2 wraps Btrfs. Swap is a file created by Disko using `btrfs filesystem mkswapfile`; no zram or swap partition. RAM-based Red Hat sizing guidelines are editable. **Small/zero swap only warns, even with hibernation selected.** No swap means no valid resume device/offset is emitted.

Physical partition UUIDs and the mapper name are captured once in `storage.json`; later hostname/source preference edits do not recompute those disk identities. The prebuilt closure, source checkout, swap and EFI must fit the selected disk with conservative overhead before erasure is allowed.

## Secrets and YubiKeys

- Personal setup requires encryption and explicitly selected git-crypt/age identities. Decryption is checked before formatting. The age identity is copied only with separate consent and private permissions. Reduced setup disables personal bookmarks, age credentials, personal SSH identity and the secret-dependent pay-respects integration.
- git-crypt unlock temporarily caches its symmetric key in the workspace Git metadata. Git-aware Nix references exclude that metadata from store inputs. The cache is **excluded from the installed checkout** and removed from the retained workspace on exit; the original key file is never copied. Installed bookmarks are restored to ciphertext and local unlock filters removed, so ordinary Git operations remain usable without retaining a key. Unlock manually with the external key before rebuilding a personal host or editing encrypted files after installation.
- Private runtime files live in root-private `/run/icy-installer`, are never Nix inputs, and are removed on normal cancellation/failure/completion. An existing runtime directory is never deleted by a new run: inspect stale state manually. Abrupt power loss/SIGKILL can leave runtime state until reboot.
- OpenPGP signing requires primary fingerprint `B8A3D43103569F0F76BAF11AE57AD43DEE514B7B` and signing subkey `433D8E22007D3A9762D54780ED06A3B7C8B9C6B0`. Online retrieval is from keys.openpgp.org; both fingerprints are checked. A fresh private GPG home must find that signing subkey on the token and perform a signature test. No private keys are exported/copied and no owner trust is assigned.
- The public certificate was published separately during development. Email identity verification is performed by the owner; some GPG versions cannot import the server's certificate until an identity is published. The installer **never uploads keys or requests verification emails**. A future offline ISO needs an embedded certificate.
- Optional FIDO2 enrollment is separate from OpenPGP. It requires `hmac-secret`, a configured client PIN and physical touch. Select one token explicitly. No token PINs or credentials are reset/replaced. Absent/incompatible tokens offer retry, abort or explicit passphrase-only continuation before formatting; enrollment failure offers the same after formatting, clearly stating data has already been erased.
- Encrypted installs always retain the initial confirmed passphrase and enroll a recovery key. Recovery output goes directly to `/dev/tty`, bypassing stdout/stderr logs. Save it off the encrypted disk and acknowledge before continuing. No slot is wiped. The requested code TODO describes a possible opt-in first-boot passphrase-removal prompt; it is not implemented.

## Shared checkout

Installed source lives at `/etc/nixos/nix-files`, owned by `root:configurators` with inherited group access and no access for unrelated users. The installing user joins configurators and wheel. This is an administrative trust boundary: members can alter root-activated configuration and read unlocked bookmarks. Use Git as your own user, never `sudo git`. Safe-directory trust is scoped to this one directory; credentials and GPG agents/keyrings remain per-user.

New host files are staged on `hosts/<hostname>`, not committed. Review and make a signed commit yourself, then push that branch explicitly. Git LFS and git-crypt are installed; no login credentials or signing material are shared. The target root password stays locked. The installing user's initial UID is explicitly 1000, matching its private age runtime paths.

## Checks

With the packaged Python interpreter or an existing Python 3:

```sh
python3 -B -m unittest discover -s installer/tests -p 'test_*.py' -v
python3 -B installer/tests/evaluate.py
nix build .#checks.x86_64-linux.installer
nix eval --raw .#nixosConfigurations.sparrow.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.eagle.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.iso.config.system.build.isoImage.drvPath
```

The evaluation matrix uses isolated sources with no unlocked bookmark files. It checks plain/encrypted/FIDO layouts, zero-swap hibernation, configured resume guards, another username, and overrides of the personal preset. It performs **no disk/token operations**. Building/evaluating a derivation is not proof of a bootable installation.

### Disposable VirtualBox test

Never attach a real host disk. These commands create one new VM and a new virtual disk only. Choose another VM name/base directory if they already exist.

```sh
nix build .#iso --out-link result-iso
ISO=$(realpath result-iso/iso/*.iso)
BASE=/tmp/opencode/icy-vbox-test
mkdir -m 700 "$BASE"
VBoxManage createvm --name icy-installer-test --ostype Linux_64 --basefolder "$BASE" --register
VBoxManage modifyvm icy-installer-test --firmware efi --memory 8192 --cpus 4 --nic1 nat --graphicscontroller vmsvga
VBoxManage createmedium disk --filename "$BASE/target.vdi" --size 131072 --format VDI
VBoxManage storagectl icy-installer-test --name SATA --add sata --controller IntelAhci
VBoxManage storageattach icy-installer-test --storagectl SATA --port 0 --device 0 --type hdd --medium "$BASE/target.vdi"
VBoxManage storageattach icy-installer-test --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$ISO"
VBoxManage startvm icy-installer-test --type gui
```

In the guest run `sudo run-installer --no-update` until the implementation is published upstream. Use reduced setup and disable signing/FIDO2 unless deliberately passing through the physical token. Test a plain install, then a fresh encrypted install with distinct hostnames/new VM disks. Shut down, eject the ISO, boot the installed disk and log in:

```sh
VBoxManage storageattach icy-installer-test --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive
VBoxManage startvm icy-installer-test --type gui
```

Verify in the installed guest:

```sh
findmnt -t btrfs,vfat
swapon --show
id
git -C /etc/nixos/nix-files status
git -C /etc/nixos/nix-files lfs env
sudo -v
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
cat /proc/cmdline
```

Also test cancellation, wrong disk confirmation, an in-use target and rejection of the ISO's backing medium. For encryption, test boot with the passphrase and separately with the saved recovery key. Only test physical FIDO2/OpenPGP with intentional USB passthrough; a normal VM cannot prove token support. Check PIN + touch, unplugged-token fallback, user `gpg --card-status`, and a user-owned signed test commit. Never record recovery output.

For hibernation, compare `resume_offset` to `map-swapfile -r`, save work, then run `systemctl hibernate`. Verify restoration after powering on. Zero-swap selection should install but fail hibernation gracefully. Inspect `/sys/kernel/security/lockdown` where available; never disable lockdown automatically to make a test pass.

## Failure recovery and swap maintenance

The workspace path is printed at startup. `stages.log` contains allowlisted stage names, not subprocess transcripts. On success it is also copied to `/var/log/icy-installer`. Workspaces may contain decrypted configuration: keep them private and export them only onto trusted encrypted storage. They are deliberately retained, not auto-deleted. Do not place private recovery data in Git.

After a failure, inspect stages and mounts before doing anything. **Do not rerun Disko's destructive script.** If mounted target filesystems are intact, use the retained source and build/reinstall only:

```sh
# Substitute the printed workspace and generated hostname after inspecting it.
REPO=/var/tmp/icy-install-EXAMPLE/repository
HOST=your-hostname
nix build "$REPO#nixosConfigurations.$HOST.config.system.build.mountScript" --out-link /var/tmp/icy-mount
# Only run the mount-only script if filesystems are unmounted and verified:
sudo /var/tmp/icy-mount
sudo nixos-install --root /mnt --flake "$REPO#$HOST" --no-root-passwd
```

Encrypted mount-only recovery needs the retained passphrase supplied interactively or via a deliberately recreated root-private `/run/icy-installer/luks-password`; never store it in the checkout. Installation credentials/group permissions/age provisioning may not have finished: inspect and complete them before reboot, and set the user password with `nixos-enter --root /mnt -c 'passwd michael'` (substitute your username). A failed finalization may require regenerating hardware/resume metadata before installation.

To resize/recreate swap later: do not hibernate with an existing image, disable hibernation while maintaining it, `swapoff` the file, recreate using `btrfs filesystem mkswapfile`, update its Disko size and `resume.json` offset, rebuild the boot configuration, then reboot before hibernating. Changing Disko's declared size alone does not resize an existing file. Never add NixOS `swapDevices.*.size` beside Disko's entry: automatic recreation could invalidate the offset. Keep `/swap` excluded from snapshots. Old boot generations with stale offsets are rejected by the pre-hibernation guard.

Additional FIDO tokens can be enrolled later with the installed system's `systemd-cryptenroll`, retaining passphrase/recovery slots. Never use `--wipe-slot=all` as routine maintenance.
