# nano-super

Device-tree overclock for the Jetson Nano 4GB (P3448-0000 B00) on L4T R32.7.x.

| | stock | OC |
|---|---|---|
| CPU max | 1479 MHz | 1555.5 MHz |
| GPU max | 921.6 MHz | 998.4 MHz |

## What it changes

Three edits to `/boot/tegra210-p3448-0000-p3449-0000-b00.dtb`, written to `/boot/dtb-oc.dtb`:

- `/clock@70110000` `nvidia,dfll-max-freq-khz`: commented out, which removes the DFLL CPU cap
- `/cpufreq/cpu-scaling-data` `freq-table`: adds a 1555500 kHz step
- `/dvfs` `nvidia,gpu-max-freq-khz`: commented out, which removes the GPU cap

The script also adds a `LABEL oc` entry to `/boot/extlinux/extlinux.conf` (`FDT /boot/dtb-oc.dtb`) and makes it `DEFAULT`. The `primary` entry is kept as a fallback.

## Usage

```sh
sudo apt install device-tree-compiler   # if dtc is missing
./nano-oc-dtb.sh --dry-run              # build ./dtb-oc.dtb only and show the diff
sudo ./nano-oc-dtb.sh                   # install and set as the default boot entry
sudo reboot
sudo ./nano-oc-dtb.sh --revert          # set DEFAULT back to primary
```

Check after reboot:

```sh
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
cat /sys/devices/gpu.0/devfreq/57000000.gpu/available_frequencies
```

## Benchmark

`bench.sh` pins CPU/GPU clocks to stock and then to OC levels on the same boot, alternating rounds. It runs stress-ng (matrixprod, 1 and 4 threads), 7-Zip and CUDA nbody, and logs temperatures and `POM_5V_IN` power from tegrastats. The OC dtb must be active.

```sh
sudo apt install stress-ng p7zip-full   # if missing
sudo ./bench.sh [rounds]                # default 2, writes bench-<timestamp>.log
```

Expected gains:

| | stock | OC | gain |
|---|---|---|---|
| stress-ng 1 thread (bogo ops/s) | 3.23 | 3.39 | +5.0% |
| stress-ng 4 threads (bogo ops/s) | 12.76 | 13.43 | +5.3% |
| 7-Zip (MIPS) | 5195 | 5401 | +4.0% |
| nbody 32768 bodies (GFLOPS) | 164.3 | 177.9 | +8.3% |
| Board power avg / peak (mW) | 4304 / 7639 | 4653 / 8683 | +8% / +14% |

Performance scales with clock speed (CPU +5.2%, GPU +8.3%), and there is no throttling at 40–48 °C.

Run `sudo jetson_clocks` / MAXN for sustained max clocks. Use a 5V/4A barrel supply and active cooling.
Overclocking is at your own risk.
