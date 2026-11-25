"""Runs openjpeg_fuzz over CASES cases of a seed, restarting after each crash.
   openjpeg_fuzz.py FUZZ SEEDFILE CASES KEY WORKDIR KEEPDIR [forge]
Prints counts and one line per crash, keeps each crashing input and its log in
KEEPDIR, and exits 1 if a case failed an assertion (assert, or a libjxl
JXL_ENSURE, JXL_DASSERT or JXL_UNREACHABLE), raised an AddressSanitizer report,
ran out of time or crashed otherwise. See openjpeg_fuzz.sh and jpegxl_fuzz.sh."""
import os, re, shutil, subprocess, sys, time

fuzz, seed, cases, key, work, keep = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]
extra = sys.argv[7:]
name = os.path.basename(seed).rsplit(".", 1)[0] + ("-forged" if len(sys.argv) > 7 else "")
counts = {"decoded": 0, "refused": 0, "assert": 0, "jxl-abort": 0, "asan": 0, "timeout": 0, "other": 0}
crashes = []
start = time.time()
case = 0
env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0:abort_on_error=0")
while case < cases:
    try:
        p = subprocess.run([fuzz, seed, str(case), str(cases - case), key, work] + extra, capture_output=True, text=True,
                           timeout=300, env=env, errors="replace")
        out, err, code = p.stdout, p.stderr, p.returncode
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        err, code = "batch timeout", -999
    last = None
    for line in out.splitlines():
        m = re.match(r"(begin|end) (\d+)(?: (\w+))?", line)
        if not m:
            continue
        if m.group(1) == "begin":
            last = int(m.group(2))
        else:
            counts[m.group(3)] += 1
            last = None
    if code == 0 and last is None:
        break
    if last is None:
        print(f"{name}: unexpected exit {code}: {err[-500:]}")
        break
    if "AddressSanitizer" in err:
        kind = "asan"
        what = re.search(r"AddressSanitizer: ([\w-]+)", err).group(1)
        frames = re.findall(r"#\d+ 0x[0-9a-f]+ in (\S+) (\S+)", err)[:4]
        detail = what + " " + " < ".join(f"{f} {l}" for f, l in frames)
    elif re.search(r"JXL_(ENSURE|DASSERT|UNREACHABLE|DEBUG_ABORT)", err):
        kind = "jxl-abort"
        detail = re.search(r"\S*JXL_(ENSURE|DASSERT|UNREACHABLE|DEBUG_ABORT).*", err).group(0)
    elif "Assertion failed" in err:
        kind = "assert"
        detail = re.search(r"Assertion failed: .*", err).group(0)
    elif code in (-14, 142):
        kind, detail = "timeout", "case took more than 20 s"
    else:
        kind, detail = "other", f"exit {code}: {err[-300:]}"
    counts[kind] += 1
    subprocess.run([fuzz, seed, str(last), "0", key, work] + extra, check=True)
    kept = os.path.join(keep, f"{name}-{last}-{kind}" + os.path.splitext(seed)[1])
    shutil.move(os.path.join(work, "current.j2c"), kept)
    with open(kept + ".log", "w") as log:
        log.write(err)
    crashes.append((last, kind, detail))
    print(f"{name}: case {last}: {kind}: {detail}", flush=True)
    case = last + 1
total = sum(counts.values())
print(f"{name}: {total} cases in {time.time() - start:.0f} s: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
sys.exit(1 if crashes else 0)
