# Ekrano Multi-VeBus Mod

Splits the OverviewPage *Inverter / Charger* tile into one mini-tile per
`com.victronenergy.vebus.*` service, and makes the *AC Loads* tile show the sum
of `/Ac/Out/P` across every VE.Bus service. Targeted at Ekrano GX with one
internal VE.Bus + two MK3-USB, where the system-service only reports the first
VE.Bus as the main inverter and the other two are otherwise invisible on the
overview.

Setups with ≤ 1 VE.Bus services render the original Victron layout unchanged.

## What's in here

```
scripts/mod/
├── README.md
├── custom-gui-install.sh    # runs on the GX device
├── custom-gui-uninstall.sh  # runs on the GX device
└── (no qml/ directory yet — see "Packaging" below)
```

The modded QML lives in the main tree:

```
components/widgets/InverterChargerWidget.qml   # multi-vebus mini-tiles
components/widgets/AcLoadsWidget.qml           # multi-vebus power sum
```

## Two install paths

The mod targets the *local* display (the Ekrano touchscreen). The Remote Console
in a browser uses the WASM build and a separate deploy path.

### 1. Local display (native gui-v2 on the GX, primary target)

The native `gui-v2` binary on Venus OS loads its QML from
`/opt/victronenergy/gui-v2/Victron/VenusOS/`. We don't rebuild the binary —
we overlay-fs our two modded `.qml` files on top.

Steps:

```sh
# On your build machine — bundle the two QML files together with the scripts.
cd <repo-root>
rm -rf /tmp/gui-v2-mod && mkdir -p /tmp/gui-v2-mod/qml/components/widgets
cp components/widgets/InverterChargerWidget.qml /tmp/gui-v2-mod/qml/components/widgets/
cp components/widgets/AcLoadsWidget.qml         /tmp/gui-v2-mod/qml/components/widgets/
cp scripts/mod/custom-gui-install.sh /tmp/gui-v2-mod/
cp scripts/mod/custom-gui-uninstall.sh /tmp/gui-v2-mod/
tar -C /tmp -czf /tmp/gui-v2-mod.tar.gz gui-v2-mod

# Transfer to the Ekrano (assumes root SSH access is set up):
scp /tmp/gui-v2-mod.tar.gz root@ekrano:/data/

# On the Ekrano:
ssh root@ekrano
tar -C /data -xzf /data/gui-v2-mod.tar.gz
cd /data/gui-v2-mod
./custom-gui-install.sh
./custom-gui-install.sh --status
```

The install script:

- Verifies it's running as root and that `/opt/victronenergy/gui-v2/...` exists
- Copies the two `.qml` files into `/data/apps/overlay-fs/gui-v2-multi-vebus/upper/components/widgets/`
- Mounts an overlay-fs on top of `/opt/victronenergy/gui-v2/Victron/VenusOS/`
- Writes a hook into `/data/rc.local` so the mount comes back after reboot
- Restarts `/service/gui-v2` (or `/service/start-gui` as fallback)

Rollback:

```sh
./custom-gui-uninstall.sh
```

This unmounts the overlay, strips the rc.local hook, deletes the upper layer,
and restarts gui-v2. Stock files were never modified so there's nothing else to
restore. `--keep` leaves the upper layer on disk for re-enable later.

### 2. Remote Console (WASM, optional)

If you also want the modded layout when accessing the device via
`http://ekrano/` in a browser, rebuild the WASM bundle. This needs Ubuntu 22+
or WSL with the prerequisites installed (`scripts/build-wasm-install-requirements.sh`
documents these).

```sh
# On Ubuntu/WSL, in the repo root:
./scripts/build-wasm.sh -H ekrano
```

The `-H` flag enables the built-in scp to `/var/www/venus/gui-v2/`. The script
also handles `remount-rw` and `vrmlogger` restart. The WASM bundle is independent
of the native overlay — installing one does not affect the other.

## Verifying the install

After install, on the GX device:

```sh
mount | grep gui-v2
# → overlay on /opt/victronenergy/gui-v2/Victron/VenusOS type overlay (...)
ls /data/apps/overlay-fs/gui-v2-multi-vebus/upper/components/widgets/
# → AcLoadsWidget.qml  InverterChargerWidget.qml
```

In the UI, with three vebus services connected, the Overview page should show
three mini-tiles in the center where the single Inverter/Charger tile used to
be, plus an AC Loads value that matches the sum of `/Ac/Out/P` across all three
services (check via `dbus-spy`).

## Notes / caveats

- **Update resistance.** A Venus OS update that ships an incompatible
  `InverterChargerWidget.qml` or `AcLoadsWidget.qml` (different properties,
  renamed base classes, etc.) will not break the overlay mount, but our overlaid
  file may stop working. After a firmware update, re-run install if you see
  layout glitches, or uninstall to fall back to stock.
- **Sort order.** Services are shown in ascending `DeviceInstance` order. On the
  Ekrano the internal VE.Bus has the lowest instance and is the grid-connected
  one, so it ends up leftmost. If your wiring differs, the grid-vebus may not
  end up leftmost — in that case the sorting logic in
  `InverterChargerWidget.qml` needs an extra `Ac/ActiveIn/Connected` probe.
- **AC Loads drilldown.** The drilldown page (`AcLoadListPage`) still uses the
  system-service load object, because that page expects a typed
  `ObjectAcConnection`. The tile shows the multi-vebus sum, but clicking through
  shows the same individual AC load devices as before.
