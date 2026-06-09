# Publishing to the AUR

Notes to myself for getting `zenbook-duo-hyprland` onto the AUR. One-time
account setup, then a short loop for every release.

## One-time: AUR account + SSH key

1. Make an account at https://aur.archlinux.org (if you don't have one).
2. Generate a key if needed and add the **public** key under My Account -> SSH
   Public Key:
   ```bash
   ssh-keygen -t ed25519 -C "aur" -f ~/.ssh/aur
   cat ~/.ssh/aur.pub   # paste this into the AUR account page
   ```
3. Point SSH at it for the AUR host (`~/.ssh/config`):
   ```
   Host aur.archlinux.org
       IdentityFile ~/.ssh/aur
       User aur
   ```
4. Test: `ssh aur@aur.archlinux.org help` should print the AUR git help.

## First publish

The package name is free to claim by just pushing to it.

```bash
git clone ssh://aur@aur.archlinux.org/zenbook-duo-hyprland.git aur-zenbook-duo-hyprland
cd aur-zenbook-duo-hyprland
cp ../zenbook-duo-hyprland/PKGBUILD .
cp ../zenbook-duo-hyprland/.SRCINFO .
git add PKGBUILD .SRCINFO
git commit -m "Initial import: zenbook-duo-hyprland 0.1.0-1"
git push
```

`.SRCINFO` must match `PKGBUILD`. Regenerate it whenever you touch `PKGBUILD`:

```bash
makepkg --printsrcinfo > .SRCINFO
```

## Before you push, sanity check

- The GitHub release tag `v$pkgver` exists and the tarball URL resolves.
- `sha256sums` in `PKGBUILD` matches the real release tarball (not `SKIP`):
  ```bash
  curl -L -o /tmp/zd.tar.gz \
    https://github.com/laithm/zenbook-duo-hyprland/archive/refs/tags/v0.1.0.tar.gz
  sha256sum /tmp/zd.tar.gz
  ```
- A clean build works:
  ```bash
  makepkg -f          # downloads the source, builds, verifies the checksum
  ```

## Releasing a new version later

1. Bump `pkgver` (and reset `pkgrel=1`) in `PKGBUILD`.
2. Tag and release on GitHub: `git tag vX.Y.Z && git push origin vX.Y.Z`, then
   `gh release create vX.Y.Z`.
3. Update `sha256sums` for the new tarball.
4. `makepkg --printsrcinfo > .SRCINFO`.
5. In the AUR clone: copy the updated `PKGBUILD` + `.SRCINFO`, commit, push.
