# MIKE OS — Benchmarking and Telemetry History

## 1. Evolution Summary

| Metric | Initial Baseline | Consolidated Core (v0.2.0) | Target |
| :--- | :---: | :---: | :---: |
| **Boot Time** | 0.56 s | **0.60 s** | < 1.0 s |
| **RAM Consumption** | 39 MB | **45 – 80 MB** | < 128 MB |
| **RootFS Image Size**| 11 MB | **37 MB** (ext4 disk) | < 100 MB |
| **Systemd Presence** | 0% | **0%** | 0% |
| **Test Suite Pass Rate** | N/A | **100% (15/15 PASS)** | 100% |

---

## 2. Telemetry Details

* **Kernel + Init + Runit Boot Time**: ~0.60 seconds.
* **Idle Process Count**: ~57 processes (primarily Linux kernel worker threads and runit supervisors).
* **Supervised Services Active**: `console`, `syslog`, `network`, `dropbear`.
* **Automated Runner**: `./scripts/benchmark.sh`.
