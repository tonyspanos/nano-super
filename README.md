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

Run `sudo jetson_clocks` / MAXN for sustained max clocks. Use a 5V/4A barrel supply and active cooling.
Overclocking is at your own risk.
