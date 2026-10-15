# PowerClue

A local, native macOS 14+ menu bar app for understanding battery use and performance. The interface is in English. It runs on Intel and Apple Silicon without administrator access, an account, or telemetry.

## Build and run

```sh
./scripts/build-app.sh
open dist/PowerClue.app
```

The script creates a signed local app bundle at `dist/PowerClue.app`. Click its lightning bolt in the menu bar, then **Open dashboard**. The project is a Swift Package and can also be opened in Xcode.

## What it shows

- Battery charge, power source, time estimate, instantaneous battery output where available, 1/5/15-minute drain averages, and a personal drain baseline built from local history.
- System CPU, memory, swap, memory-pressure notifications, load average, disk and network throughput, thermal state, and Low Power Mode.
- Process CPU, CPU time, physical memory footprint, wakeups, disk I/O, network traffic, and current power assertions where macOS exposes them. Search, sorting, app grouping, and process details are available.
- A relative **Activity** rating with the contributing signals. This is a heuristic for investigation, **not** a measured share of battery drain.
- On supported Apple Silicon Macs, **CPU W** estimates a process's CPU-only power from macOS CPU energy accounting over a sample interval. GPU, display, networking, disk, shared system work, and other power are excluded. Unsupported or restricted values show `—`.
- Sleep reports recorded while the app is running, with before/after charge, duration, DarkWake and Wake counts, wake reasons, and assertions seen just before sleep. The report describes possible contributors and does not claim causation.
- SQLite history with detailed samples retained for 48 hours and one-minute aggregates retained for 30 days. Charts cover battery, CPU, memory, swap, network, disk, and thermal state over 5 minutes through 24 hours. Select a point to see its top processes.

Sampling runs every second while the menu or dashboard is visible, every five seconds in the background, and every twelve seconds in Low Power Mode. Network and power assertions refresh about every ten seconds. Polling stops during system sleep.

The app uses public macOS APIs and the system `nettop` and `pmset` utilities. Some processes restrict their data; unavailable values are left blank. A full system sleep/wake cycle is required before a sleep report can be verified on a given Mac. To preserve history from earlier builds, the local database remains in the user's Application Support directory under `EasyActivityMonitor/history.sqlite`.
