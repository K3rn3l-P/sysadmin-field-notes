# Temperature and hardware sensors – Linux

## Purpose
How to install and use `lm-sensors` to monitor temperatures, fans and hardware readings on Linux.

## Prerequisites

- A Linux system with `sudo` access

## Installation

```bash
sudo apt update
sudo apt install lm-sensors -y
```

## Detecting sensors

```bash
sudo sensors-detect
```

Answer `yes` to every question so it picks up all the compatible modules.

## Reading sensor values

```bash
sensors -u    # numeric format
sensors       # human-readable output
```

## Live monitoring

```bash
watch -n 2 "sensors | grep -E 'Tctl|Tdie|temp1_input|temp3_input'"
```

> Note: this filter is mostly useful on AMD/Ryzen. On many Intel CPUs (Xeon, for instance)
> `sensors` reports `Package` and `Core N` instead.
>
> For Intel, use:
>
```bash
watch -n 2 "sensors | grep -E 'Core|Package'"
```

---

## If the CPU sensors don't show up

- Load the CPU module by hand:
  ```bash
  sudo modprobe coretemp   # Intel
  sudo modprobe k10temp    # AMD
  ```
- If they're still missing after a reboot, check that a `coretemp` or `k10temp` line is present in
  `/etc/modules`.
- You can force a hot reload without rebooting:
  ```bash
  sudo systemctl restart kmod
  sudo sensors
  ```
- On a custom kernel or more exotic hardware, also install `i2c-tools` and look for the chips with:
  ```bash
  sudo apt install i2c-tools -y
  sudo i2cdetect -l
  ```

## Just the CPU temperatures, cleanly

```bash
sensors | grep -E 'Core|Package'
```

---

## Live CPU temperature monitoring script

For continuous monitoring with colour alarms, use `monitor-cpu-temp.sh`.

### Usage

1. Save the script as `linux/sensors-hw/monitor-cpu-temp.sh`
2. Make it executable:
   ```bash
   chmod +x monitor-cpu-temp.sh
   ```
3. Start monitoring:
   ```bash
   ./monitor-cpu-temp.sh
   ```
   You can pass an interval in seconds, e.g. `./monitor-cpu-temp.sh 5`.

### What it does

- shows the `Core N` and `Package` rows from the sensors
- uses `OK`, `WARNING` and `DANGER` in the `STATUS` column
- highlights temperatures above 75°C in yellow
- highlights temperatures above 85°C in red
- also lists the top memory-consuming processes (`ps`) so you can spot what's driving the load
- refreshes the screen continuously until you press Ctrl+C

## Boot history and hardware hangs

```bash
journalctl --list-boots              # list of boots with start/end times
journalctl -b -N -n 60 --no-pager    # tail of a past boot's log (N negative, e.g. -1 = previous boot)
journalctl -b -N -p err --no-pager   # errors only, for a specific boot
```

> If the end of a boot doesn't show a clean shutdown in the following log, that's a sign of a crash
> or a hang. See [`e1000e-nic-hang-fix`](../proxmox/e1000e-nic-hang-fix) for a concrete case
> (counting NIC hangs per boot).

## Thermal and hardware errors in the kernel log

```bash
journalctl -k | grep -iE 'thermal|throttl|mce|Machine Check'
cat /sys/devices/system/edac/mc/mc*/ce_count   # correctable ECC RAM errors
cat /sys/devices/system/edac/mc/mc*/ue_count   # uncorrectable ECC RAM errors
```

---

## Tips

- Compare readings before and after a load to spot anomalies.
- Use `sensors -u` if you want to feed the output into monitoring scripts.

---

**Last updated:** August 2026
