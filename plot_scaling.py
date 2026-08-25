#!/usr/bin/env python3
"""Plot actual vs ideal strong-scaling from a *_scaling.dat file."""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

dat = sys.argv[1] if len(sys.argv) > 1 else "scaling.dat"
png = sys.argv[2] if len(sys.argv) > 2 else "scaling.png"
title = sys.argv[3] if len(sys.argv) > 3 else "scaling"

th, tot, ideal = [], [], []
with open(dat) as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        p = line.split()
        def num(x): return float(x.replace(',', '.'))
        th.append(int(p[0])); tot.append(num(p[1])); ideal.append(num(p[3]))

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.2))
ax1.plot(th, tot, "o-", color="#3b78e7", label="Actual")
ax1.plot(th, ideal, "s--", color="#e8483b", label="Ideal (T1/p)")
ax1.set_xlabel("Threads"); ax1.set_ylabel("Time (s)")
ax1.set_title(f"Time vs. threads — {title}"); ax1.legend(); ax1.grid(True, alpha=0.3)

speedup = [tot[0] / t for t in tot]
ax2.plot(th, speedup, "o-", color="#3b78e7", label="Actual speedup")
ax2.plot(th, th, "s--", color="#e8483b", label="Ideal (linear)")
ax2.set_xlabel("Threads"); ax2.set_ylabel("Speedup")
ax2.set_title("Speedup vs. threads"); ax2.legend(); ax2.grid(True, alpha=0.3)

fig.tight_layout(); fig.savefig(png, dpi=130)
print(f"wrote {png}")
