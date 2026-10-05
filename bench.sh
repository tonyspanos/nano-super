#!/bin/bash
# Benchmark stock vs OC clocks on the same boot (requires the OC dtb to be active).
# Pins CPU/GPU min=max to each level, runs CPU + GPU benches, alternating rounds.
# Usage: sudo ./bench.sh [rounds]   (default 2)
set -u
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

ROUNDS=${1:-2}
CPUF=/sys/devices/system/cpu/cpu0/cpufreq
GPUF=/sys/devices/gpu.0/devfreq/57000000.gpu
NBODY=/usr/local/cuda/samples/5_Simulations/nbody/nbody
OUT=$(dirname "$0")/bench-$(date +%Y%m%d-%H%M%S).log

grep -qw 1555500 $CPUF/scaling_available_frequencies || { echo "OC dtb not active"; exit 1; }

save_cpu_min=$(cat $CPUF/scaling_min_freq) save_cpu_max=$(cat $CPUF/scaling_max_freq)
save_cpu_gov=$(cat $CPUF/scaling_governor)
save_gpu_min=$(cat $GPUF/min_freq) save_gpu_max=$(cat $GPUF/max_freq)
restore() {
    echo "$save_cpu_gov" > $CPUF/scaling_governor
    echo "$save_cpu_max" > $CPUF/scaling_max_freq; echo "$save_cpu_min" > $CPUF/scaling_min_freq
    echo "$save_gpu_max" > $GPUF/max_freq; echo "$save_gpu_min" > $GPUF/min_freq
    kill $TSPID 2>/dev/null
}
trap restore EXIT

pin() {  # cpu_khz gpu_hz
    echo performance > $CPUF/scaling_governor
    # max<min is rejected, so write max, min, max to handle both raising and lowering
    echo "$1" > $CPUF/scaling_max_freq 2>/dev/null; echo "$1" > $CPUF/scaling_min_freq; echo "$1" > $CPUF/scaling_max_freq
    echo "$2" > $GPUF/max_freq 2>/dev/null; echo "$2" > $GPUF/min_freq; echo "$2" > $GPUF/max_freq
    sleep 2
    [ "$(cat $CPUF/scaling_cur_freq)" = "$1" ] && [ "$(cat $GPUF/cur_freq)" = "$2" ] \
        || echo "WARN: pin to $1/$2 failed (cpu=$(cat $CPUF/scaling_cur_freq) gpu=$(cat $GPUF/cur_freq))" >&2
}

temp() { echo $(( $(cat /sys/devices/virtual/thermal/thermal_zone$1/temp) / 1000 )); }  # 1=CPU 2=GPU

TSLOG=$(mktemp)
tegrastats --interval 500 > "$TSLOG" & TSPID=$!

bench() {  # label
    local l=$1 s e
    s=$(wc -l < "$TSLOG")
    st=$(stress-ng --cpu 1 --cpu-method matrixprod -t 20 --metrics-brief 2>&1 | awk '/cpu /{print $(NF-1)}' | tail -1)
    mt=$(stress-ng --cpu 4 --cpu-method matrixprod -t 20 --metrics-brief 2>&1 | awk '/cpu /{print $(NF-1)}' | tail -1)
    z=$(7z b 1 -mmt4 2>&1 | awk '/^Tot:/{print $4}')
    ctemp=$(temp 1)
    g=$($NBODY -benchmark -numbodies=32768 -i=100 2>&1 | awk '/GFLOP/{print $2}')
    gtemp=$(temp 2)
    e=$(wc -l < "$TSLOG")
    pw=$(sed -n "$((s+1)),${e}p" "$TSLOG" | grep -o 'POM_5V_IN [0-9]*' | awk '{s+=$2;n++; if($2>m)m=$2} END{printf "%d/%d", s/n, m}')
    printf "%-6s %8s %8s %8s %8s %6s %6s %10s  cpu=%s gpu=%s\n" "$l" "$st" "$mt" "$z" "$g" "$ctemp" "$gtemp" "$pw" \
        "$(cat $CPUF/scaling_cur_freq)" "$(cat $GPUF/cur_freq)" | tee -a "$OUT"
}

echo "label  st_bogo  mt_bogo  7z_MIPS nbody_GF  cpuC   gpuC  avg/max_mW" | tee "$OUT"
for r in $(seq "$ROUNDS"); do
    pin 1479000 921600000; bench stock
    sleep 20
    pin 1555500 998400000; bench oc
    sleep 20
done
echo "log: $OUT"
