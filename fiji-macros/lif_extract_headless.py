# lif_extract_headless.py  --  headless engine behind Pipeline Phase 0 (Extract)
# ============================================================================
# Jython script for Fiji/ImageJ. HEADLESS-CAPABLE port of the interactive macro
# fiji-macros/LIF_Extract_and_Trim.ijm. Produces byte-for-byte the same outputs
# as that macro, but with NO GUI: it replaces the macro's `run("Bio-Formats
# Importer", ...)` call (whose dialog code throws a JVM VerifyError under
# --headless) with the Bio-Formats API (loci.plugins.BF.openImagePlus), which we
# validated bit-exact (max pixel diff 0) on real LIF data.
#
# Contract with the macro (kept identical so GUI and pipeline outputs match):
#   - LIF -> raw (UNTRIMMED) + optional TRIMMED TIFFs; or trim/Hz-label a folder
#     of existing TIFFs (mode=tiff).
#   - Pixel data is NEVER modified; the measured acquisition rate is appended to
#     each output filename, end-anchored (e.g. "Series003_5.00Hz.tif").
#   - Same skip rules (TileScan / single-frame snapshot / already-done resume /
#     no-frame-interval), same first-seen rate policy (warn|drop), same trim math
#     (middle|last|first, seconds|frames, with short/bad-window handling), same
#     idempotent Hz labelling, same UNTRIMMED/TRIMMED layout.
#
# Invocation (from Run-Pipeline.ps1 Phase 0, or by hand):
#   ImageJ-<plat> --headless --console --run lif_extract_headless.py
# The single input is a CONFIG FILE whose path is taken from the environment
# variable LIF_EXTRACT_CONFIG (chosen over a script arg to dodge PowerShell ->
# Fiji quote mangling). Format: one `key=value` per line, `#` comments allowed.
# Keys (all lower_snake):
#   mode            lif | tiff
#   input           root input dir (recursed for LIFs; top level for tiff mode)
#   output          output dir (mirror root for lif/mirror; output for tiff mode)
#   output_mode     sibling | mirror        (lif mode only)
#   save_untrimmed  true | false
#   trim_mode       none | middle | last | first
#   trim_start_sec  number   (used by middle/first)
#   trim_amount     number
#   trim_unit       seconds | frames
#   hz_label        true | false
#   hz_decimals     integer
#   rate_policy     warn | drop             (lif mode only)
#   skip_tilescans  true | false            (lif mode only)
#   dry_run         true | false
#   log             full path to the run log file to write
#
# Exit code: 0 on success (including "nothing to do"), non-zero on fatal config
# or I/O error. Per-series problems are logged and counted, never fatal.

import os
import sys
import re

# Java/Fiji imports are wrapped so the pure-Python helpers (trim math, Hz
# labelling, discovery, config parsing) can be imported and unit-tested under
# stock CPython without a Fiji runtime. The Java classes are only referenced
# inside the functions that actually decode/save, which never run under CPython.
try:
    from ij import IJ
    from ij.plugin import Duplicator
    from loci.plugins import BF
    # 'loci.plugins.in' can't be written as a normal `from ... import` because
    # `in` is a reserved word (a *syntax* error, uncatchable by try/except);
    # __import__ takes the package name as a string, which both Jython and
    # CPython parse fine (CPython then raises ImportError here, caught below).
    ImporterOptions = __import__(
        "loci.plugins.in", globals(), locals(), ["ImporterOptions"], 0).ImporterOptions
    from loci.formats import ImageReader, MetadataTools
    _FIJI_AVAILABLE = True
except ImportError:
    _FIJI_AVAILABLE = False


# ----------------------------------------------------------------------------
# Config loading
# ----------------------------------------------------------------------------
def load_config():
    path = os.environ.get("LIF_EXTRACT_CONFIG")
    if not path:
        raise RuntimeError("LIF_EXTRACT_CONFIG env var not set (path to config file)")
    if not os.path.isfile(path):
        raise RuntimeError("Config file not found: %s" % path)
    cfg = {}
    f = open(path, "r")
    try:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip()
    finally:
        f.close()
    return cfg


def as_bool(cfg, key, default=False):
    v = cfg.get(key)
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def as_float(cfg, key, default):
    v = cfg.get(key)
    if v is None or v == "":
        return default
    return float(v)


def as_int(cfg, key, default):
    v = cfg.get(key)
    if v is None or v == "":
        return default
    return int(float(v))


# ----------------------------------------------------------------------------
# Small helpers (faithful to the macro)
# ----------------------------------------------------------------------------
def d2s(x, decimals):
    # ImageJ d2s: fixed-point with `decimals` places.
    return ("%." + str(decimals) + "f") % x


def strip_prefix(title):
    # Everything after the LAST ' - ' in a series title; sanitize path chars.
    p = title.rfind(" - ")
    out = title[p + 3:] if p >= 0 else title
    for ch in ("/", "\\", ":"):
        out = out.replace(ch, "_")
    return out


_HZ_TAIL = re.compile(r".*_[0-9]+(\.[0-9]+)?Hz$")
_HZ_FILE = re.compile(r".*_[0-9]+(\.[0-9]+)?Hz\.tiff?$", re.IGNORECASE)


def labelled(name, hz_str, hz_label):
    if not hz_label:
        return name
    if _HZ_TAIL.match(name):
        return name  # already labelled (idempotent)
    return name + "_" + hz_str + "Hz"


def already_extracted(dir_path, base):
    if not os.path.isdir(dir_path):
        return False
    for nm in os.listdir(dir_path):
        low = nm.lower()
        if not (low.endswith(".tif") or low.endswith(".tiff")):
            continue
        if nm == base + ".tif" or nm == base + ".tiff":
            return True
        if nm.startswith(base + "_") and _HZ_FILE.match(nm):
            return True
    return False


def frame_interval_seconds(imp):
    # Mirror the macro's frameIntervalSeconds(): read ImageJ calibration frame
    # interval + time unit (which Bio-Formats populates from the OME
    # TimeIncrement on import), normalizing ms/min to seconds. <=0 => unknown.
    cal = imp.getCalibration()
    fi = cal.frameInterval
    tu = (cal.getTimeUnit() or "").lower()
    if tu in ("ms", "msec", "millisec", "millisecond", "milliseconds"):
        fi = fi / 1000.0
    elif tu in ("min", "minute", "minutes"):
        fi = fi * 60.0
    return fi


def compute_trim_frames(total_frames, fi, trim_mode, trim_start_sec, trim_amount, trim_unit_seconds):
    # Returns (start, end, short, bad). Duration is FRAME-based: for seconds we keep
    # floor(amount/fi) whole frames, so it never needs the rate to divide evenly --
    # e.g. 60 s at 19.07 Hz keeps 1144 frames (~59.95 s). The three modes are
    # genuinely distinct:
    #   first  -> the FIRST n_keep frames, after an optional -TrimStartSec lead-in
    #             to skip (0 = from the very start)
    #   middle -> the CENTER n_keep frames (centered on the recording midpoint;
    #             -TrimStartSec is ignored)
    #   last   -> the FINAL n_keep frames
    n_keep = trim_amount
    if trim_unit_seconds:
        n_keep = int(trim_amount / fi)  # floor -> closest whole-frame count
    if n_keep < 1:
        n_keep = 1
    short = False
    if trim_mode == "middle":
        start = int((total_frames - n_keep) / 2) + 1   # centered window
        end = start + n_keep - 1
    elif trim_mode == "last":
        end = total_frames
        start = total_frames - n_keep + 1
        if start < 1:
            start = 1
            short = True
    else:  # "first"
        start = int(trim_start_sec / fi) + 1           # optional lead-in skip
        end = start + n_keep - 1
    if start < 1:
        start = 1
    if end > total_frames:
        end = total_frames
        short = True
    bad = (start > total_frames) or (start > end)
    return start, end, short, bad


# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
class Log:
    def __init__(self, path):
        self.f = open(path, "w") if path else None

    def __call__(self, msg):
        if self.f:
            self.f.write(msg + "\n")
            self.f.flush()
        # Echo to the console. IJ.log can behave oddly headless, so guard it and
        # fall back to plain stdout (which Fiji's --console surfaces). The file log
        # above is the source of truth the orchestrator inspects.
        try:
            IJ.log(msg)
        except Exception:
            try:
                print(msg)
            except Exception:
                pass

    def close(self):
        if self.f:
            self.f.close()


# Totals (module-level, mirrors the macro's global counters)
T = {
    "ok": 0, "snap": 0, "tile": 0, "done": 0, "nofi": 0,
    "rate": 0, "warn": 0, "alldone": 0, "failed": 0,
}


# ----------------------------------------------------------------------------
# Saving
# ----------------------------------------------------------------------------
def save_tiff(imp, fi, path):
    # Preserve the frame interval in the saved ImageJ TIFF, exactly like the
    # macro's Stack.setFrameInterval(fi); saveAs("Tiff"). Pixels unchanged.
    cal = imp.getCalibration()
    if fi > 0:
        cal.frameInterval = fi
        cal.setTimeUnit("sec")
    IJ.saveAsTiff(imp, path)


def duplicate_frames(imp, start, end):
    # Extract frames [start,end] EXPLICITLY as a time (or, for a plain stack, a
    # slice) range -- avoids the slices-vs-frames ambiguity of SubstackMaker on a
    # hyperstack. Pixels are copied unchanged (bit-exact), matching the macro's
    # Make Substack... frames=start-end.
    nC = imp.getNChannels()
    nZ = imp.getNSlices()
    nT = imp.getNFrames()
    dup = Duplicator()
    if nT > 1:
        return dup.run(imp, 1, nC, 1, nZ, start, end)   # time lives in T
    else:
        return dup.run(imp, 1, nC, start, end, 1, 1)     # plain stack: T in the Z/slice axis


def ome_time_increment_seconds(meta, series_index):
    # Fallback frame interval straight from OME metadata, used only if the ImageJ
    # calibration didn't carry one. Very defensive: any API shape difference just
    # yields <=0 (treated as "unknown"), never an exception.
    try:
        ti = meta.getPixelsTimeIncrement(series_index)
        if ti is None:
            return -1.0
        try:
            val = float(ti.value().doubleValue())        # newer OME: ome.units Time
            unit = str(ti.unit().getSymbol()).lower()
        except Exception:
            val = float(ti); unit = 's'                  # older OME: plain Double (seconds)
        if unit in ('ms', 'msec', 'millisecond', 'milliseconds'):
            val = val / 1000.0
        elif unit in ('min', 'minute', 'minutes'):
            val = val * 60.0
        return val
    except Exception:
        return -1.0


def open_series(lif_path, series_index):
    # Bio-Formats API import of ONE series (headless-safe). Returns an ImagePlus.
    opts = ImporterOptions()
    opts.setId(lif_path)
    opts.setAutoscale(False)          # display-only anyway; keep raw pixels
    opts.setColorMode(ImporterOptions.COLOR_MODE_DEFAULT)
    opts.setStackOrder(ImporterOptions.ORDER_XYCZT)
    opts.setVirtual(False)
    # A fresh ImporterOptions has no series selected; turning one on makes the
    # importer open ONLY that series. (We deliberately do NOT call clearSeries()
    # -- it isn't part of the ImporterOptions API and would raise.)
    opts.setSeriesOn(series_index, True)
    imps = BF.openImagePlus(opts)
    if not imps or len(imps) == 0:
        return None
    if len(imps) > 1:
        # Shouldn't happen (only one series requested); keep the first, free rest.
        for extra in imps[1:]:
            try:
                extra.close()
            except Exception:
                pass
    return imps[0]


# ----------------------------------------------------------------------------
# Process one LIF
# ----------------------------------------------------------------------------
def process_lif(lif_path, dst_parent, cfg_state, log):
    fname = os.path.basename(lif_path)
    lif_base = fname[:-4] if fname.lower().endswith(".lif") else fname

    lif_out_dir = os.path.join(dst_parent, lif_base)
    untrimmed_dir = os.path.join(lif_out_dir, "UNTRIMMED")
    trimmed_dir = os.path.join(lif_out_dir, "TRIMMED")

    if os.path.getsize(lif_path) <= 0:
        log("[FAIL] %s   (zero-byte file)" % lif_path)
        T["failed"] += 1
        return

    save_untrimmed = cfg_state["save_untrimmed"]
    do_trim = cfg_state["do_trim"]
    dry = cfg_state["dry_run"]
    skip_tiles = cfg_state["skip_tilescans"]
    hz_label = cfg_state["hz_label"]
    hz_dec = cfg_state["hz_decimals"]

    reader = ImageReader()
    meta = MetadataTools.createOMEXMLMetadata()
    reader.setMetadataStore(meta)
    reader.setId(lif_path)
    try:
        series_count = reader.getSeriesCount()
        max_series = cfg_state.get("max_series", 0)
        if max_series and max_series > 0 and series_count > max_series:
            log(" (debug: capping to first %d of %d series)" % (max_series, series_count))
            series_count = max_series
        log("---------------------------------------------")
        log(" FILE: %s   (series: %d)" % (lif_path, series_count))

        if not dry:
            _mkdir(lif_out_dir)
            if save_untrimmed:
                _mkdir(untrimmed_dir)
            if do_trim:
                _mkdir(trimmed_dir)

        for s in range(series_count):
            peek_name = meta.getImageName(s)
            if peek_name is None:
                peek_name = "series_%d" % (s + 1)
            size_t = meta.getPixelsSizeT(s)
            peek_t = int(size_t.getValue()) if size_t is not None else 0
            clean_peek = strip_prefix(peek_name)

            if skip_tiles and ("TileScan_" in peek_name) and ("Merging" not in peek_name):
                log("  [SKIP-TILE] %s" % clean_peek)
                T["tile"] += 1
                continue
            if peek_t <= 1:
                log("  [SKIP-SNAP] %s | %d frame" % (clean_peek, peek_t))
                T["snap"] += 1
                continue

            done_u = (not save_untrimmed) or already_extracted(untrimmed_dir, clean_peek)
            done_t = (not do_trim) or already_extracted(trimmed_dir, clean_peek)
            if done_u and done_t:
                log("  [SKIP-DONE] %s" % clean_peek)
                T["done"] += 1
                continue

            imp = open_series(lif_path, s)
            if imp is None:
                log("  [FAIL] %s | could not import series" % clean_peek)
                T["failed"] += 1
                continue
            try:
                total_frames = imp.getStackSize()
                series_name = strip_prefix(imp.getTitle()) if imp.getTitle() else clean_peek

                fi = frame_interval_seconds(imp)
                if fi <= 0:
                    fi = ome_time_increment_seconds(meta, s)   # fallback: OME metadata
                if fi <= 0:
                    log("  [SKIP-NOFI] %s | %d frames | no frame interval -> cannot compute Hz"
                        % (series_name, total_frames))
                    T["nofi"] += 1
                    continue
                hz_str = d2s(1.0 / fi, hz_dec)
                fps_str = "%s Hz (%s s/frame)" % (hz_str, d2s(fi, 4))

                # First-seen rate policy
                if cfg_state["global_fi"][0] < 0:
                    cfg_state["global_fi"][0] = fi
                elif abs(fi - cfg_state["global_fi"][0]) > 0.001:
                    ref_hz = d2s(1.0 / cfg_state["global_fi"][0], 2)
                    if cfg_state["rate_drop"]:
                        log("  [DROP-RATE] %s | %s | differs from ref %s Hz - DROPPED"
                            % (series_name, fps_str, ref_hz))
                        T["rate"] += 1
                        T["warn"] += 1
                        continue
                    else:
                        log("  [WARN-RATE] %s | %s | differs from ref %s Hz - saved"
                            % (series_name, fps_str, ref_hz))
                        T["warn"] += 1

                out_name = labelled(series_name, hz_str, hz_label)

                # UNTRIMMED
                if save_untrimmed and not already_extracted(untrimmed_dir, clean_peek):
                    if dry:
                        log("  [DRY-U]     %s.tif | %s" % (out_name, fps_str))
                    else:
                        save_tiff(imp, fi, os.path.join(untrimmed_dir, out_name + ".tif"))

                # TRIMMED
                if do_trim and not already_extracted(trimmed_dir, clean_peek):
                    start, end, short, bad = compute_trim_frames(
                        total_frames, fi, cfg_state["trim_mode"],
                        cfg_state["trim_start_sec"], cfg_state["trim_amount"],
                        cfg_state["trim_unit_seconds"])
                    if bad:
                        log("  [WARN-LEN]  %s | %s | recording shorter than trim start (%ss) - no trimmed copy written"
                            % (series_name, fps_str, cfg_state["trim_start_sec"]))
                        T["warn"] += 1
                    else:
                        n_keep = end - start + 1
                        kept_sec = d2s(n_keep * fi, 1)
                        if dry:
                            log("  [DRY-T]     %s.tif | frames %d-%d (%ss)"
                                % (out_name, start, end, kept_sec))
                        else:
                            sub = duplicate_frames(imp, start, end)
                            save_tiff(sub, fi, os.path.join(trimmed_dir, out_name + ".tif"))
                            sub.close()
                        if short:
                            log("  [WARN-LEN]  %s | %s | kept %d-%d (%ss) - SHORTER THAN REQUESTED"
                                % (series_name, fps_str, start, end, kept_sec))
                            T["warn"] += 1
                        else:
                            log("  [OK]        %s | %s | kept %d-%d (%ss)"
                                % (series_name, fps_str, start, end, kept_sec))
                elif not do_trim:
                    log("  [OK-UNTRIM] %s | %s | UNTRIMMED only" % (series_name, fps_str))

                T["ok"] += 1
            finally:
                imp.close()
    finally:
        reader.close()
    log("")


# ----------------------------------------------------------------------------
# Process one existing TIFF (mode=tiff)
# ----------------------------------------------------------------------------
def process_tiff(tif_path, out_root, cfg_state, log):
    fname = os.path.basename(tif_path)
    if os.path.getsize(tif_path) <= 0:
        log("[FAIL] %s   (zero-byte file)" % tif_path)
        T["failed"] += 1
        return
    base = fname
    dot = base.rfind(".")
    if dot > 0:
        base = base[:dot]

    save_untrimmed = cfg_state["save_untrimmed"]
    do_trim = cfg_state["do_trim"]
    dry = cfg_state["dry_run"]
    hz_label = cfg_state["hz_label"]
    hz_dec = cfg_state["hz_decimals"]

    untrimmed_dir = os.path.join(out_root, "UNTRIMMED")
    trimmed_dir = os.path.join(out_root, "TRIMMED")

    done_u = (not save_untrimmed) or already_extracted(untrimmed_dir, base)
    done_t = (not do_trim) or already_extracted(trimmed_dir, base)
    if done_u and done_t:
        log("  [SKIP-DONE] %s" % base)
        T["done"] += 1
        return

    imp = IJ.openImage(tif_path)
    if imp is None:
        log("  [FAIL] %s | could not open" % base)
        T["failed"] += 1
        return
    try:
        total_frames = imp.getStackSize()
        if total_frames <= 1:
            log("  [SKIP-SNAP] %s | %d frame" % (base, total_frames))
            T["snap"] += 1
            return
        fi = frame_interval_seconds(imp)
        hz_str = "NA"
        if fi > 0:
            hz_str = d2s(1.0 / fi, hz_dec)
        elif hz_label:
            log("  [WARN-NOFI] %s | no frame interval -> Hz label omitted" % base)

        out_name = base
        if hz_label and fi > 0:
            out_name = labelled(base, hz_str, hz_label)

        if not dry:
            if save_untrimmed:
                _mkdir(untrimmed_dir)
            if do_trim:
                _mkdir(trimmed_dir)

        if save_untrimmed and not already_extracted(untrimmed_dir, base):
            if dry:
                log("  [DRY-U]     %s.tif" % out_name)
            else:
                save_tiff(imp, fi, os.path.join(untrimmed_dir, out_name + ".tif"))

        if do_trim and not already_extracted(trimmed_dir, base):
            use_fi = fi if fi > 0 else 1.0  # frames-based trim works without FI
            start, end, short, bad = compute_trim_frames(
                total_frames, use_fi, cfg_state["trim_mode"],
                cfg_state["trim_start_sec"], cfg_state["trim_amount"],
                cfg_state["trim_unit_seconds"])
            if bad:
                log("  [WARN-LEN]  %s | recording shorter than trim start - no trimmed copy written" % base)
                T["warn"] += 1
            else:
                if dry:
                    log("  [DRY-T]     %s.tif | frames %d-%d" % (out_name, start, end))
                else:
                    sub = duplicate_frames(imp, start, end)
                    save_tiff(sub, fi, os.path.join(trimmed_dir, out_name + ".tif"))
                    sub.close()
                tag = "  [OK]        "
                if short:
                    tag = "  [WARN-LEN]  "
                    T["warn"] += 1
                log("%s%s | frames %d-%d" % (tag, base, start, end))
        T["ok"] += 1
    finally:
        imp.close()


# ----------------------------------------------------------------------------
# Discovery
# ----------------------------------------------------------------------------
def discover_lifs(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        # don't descend into our own output folders
        dirnames[:] = [d for d in dirnames if d not in ("UNTRIMMED", "TRIMMED")]
        for fn in filenames:
            if fn.lower().endswith(".lif"):
                found.append(os.path.join(dirpath, fn))
    found.sort()
    return found


def list_tifs(d):
    out = []
    for fn in sorted(os.listdir(d)):
        low = fn.lower()
        if (low.endswith(".tif") or low.endswith(".tiff")) and not fn.startswith("._"):
            out.append(os.path.join(d, fn))
    return out


def _mkdir(p):
    if not os.path.isdir(p):
        os.makedirs(p)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def main():
    cfg = load_config()

    mode = cfg.get("mode", "lif").strip().lower()
    input_dir = cfg.get("input", "").strip()
    output_dir = cfg.get("output", "").strip()
    output_mode = cfg.get("output_mode", "sibling").strip().lower()
    save_untrimmed = as_bool(cfg, "save_untrimmed", True)
    trim_mode = cfg.get("trim_mode", "none").strip().lower()
    trim_start_sec = as_float(cfg, "trim_start_sec", 15.0)
    trim_amount = as_float(cfg, "trim_amount", 60.0)
    trim_unit_seconds = (cfg.get("trim_unit", "seconds").strip().lower() == "seconds")
    hz_label = as_bool(cfg, "hz_label", True)
    hz_decimals = as_int(cfg, "hz_decimals", 2)
    rate_drop = (cfg.get("rate_policy", "warn").strip().lower() == "drop")
    skip_tilescans = as_bool(cfg, "skip_tilescans", True)
    dry_run = as_bool(cfg, "dry_run", False)
    log_path = cfg.get("log", "").strip()

    do_trim = (trim_mode != "none")
    if not save_untrimmed and not do_trim:
        raise RuntimeError("Nothing to do: save_untrimmed is off AND trim_mode is 'none'.")
    if not input_dir or not os.path.isdir(input_dir):
        raise RuntimeError("input dir missing or not a directory: %s" % input_dir)

    log = Log(log_path)
    cfg_state = {
        "save_untrimmed": save_untrimmed, "do_trim": do_trim, "dry_run": dry_run,
        "skip_tilescans": skip_tilescans, "hz_label": hz_label, "hz_decimals": hz_decimals,
        "trim_mode": trim_mode, "trim_start_sec": trim_start_sec, "trim_amount": trim_amount,
        "trim_unit_seconds": trim_unit_seconds, "rate_drop": rate_drop,
        "global_fi": [-1.0],  # boxed so nested funcs can mutate
        "max_series": as_int(cfg, "max_series", 0),  # debug: 0 = all series
    }

    trim_desc = "DISABLED"
    if do_trim:
        unit = "s" if trim_unit_seconds else " frames"
        if trim_mode == "middle":
            trim_desc = "centered %s%s" % (trim_amount, unit)
        elif trim_mode == "last":
            trim_desc = "keep FINAL %s%s" % (trim_amount, unit)
        else:
            trim_desc = "keep FIRST %s%s (from %ss in)" % (trim_amount, unit, trim_start_sec)

    log("=============================================")
    log(" LIF EXTRACT & TRIM (headless engine)")
    log("=============================================")
    log(" Input mode:      %s" % mode)
    log(" ROOT INPUT:      %s" % input_dir)
    if mode == "lif" and output_mode == "mirror":
        log(" OUTPUT (mirror): %s" % output_dir)
    if mode == "tiff":
        log(" OUTPUT:          %s" % output_dir)
    log(" Save untrimmed:  %s" % save_untrimmed)
    log(" Trim:            %s" % trim_desc)
    log(" Hz filename tag: %s (%d dp)" % (hz_label, hz_decimals))
    if mode == "lif":
        log(" Rate policy:     %s" % ("drop" if rate_drop else "warn"))
        log(" TileScan filter: %s" % skip_tilescans)
    log(" DRY RUN:         %s" % dry_run)
    log("")

    if mode == "lif":
        inputs = discover_lifs(input_dir)
    else:
        inputs = list_tifs(input_dir)
    log(" Discovered inputs: %d" % len(inputs))
    log("")
    if len(inputs) == 0:
        log(" (nothing to do)")
        log.close()
        return

    if not input_dir.endswith(os.sep):
        input_dir_norm = input_dir + os.sep
    else:
        input_dir_norm = input_dir

    for i, full in enumerate(inputs):
        log("[%d/%d] %s" % (i + 1, len(inputs), os.path.basename(full)))
        if mode == "lif":
            if output_mode == "mirror":
                parent = os.path.dirname(full)
                if not parent.endswith(os.sep):
                    parent = parent + os.sep
                rel = parent[len(input_dir_norm):]
                out_parent = os.path.join(output_dir, rel)
                if not dry_run:
                    _mkdir(out_parent)
            else:
                out_parent = os.path.dirname(full)
            process_lif(full, out_parent, cfg_state, log)
        else:
            process_tiff(full, output_dir, cfg_state, log)

    log("=============================================")
    log(" TOTALS")
    log(" Input files seen:              %d" % len(inputs))
    log("   ...failed (corrupt/error):   %d" % T["failed"])
    log(" Series/files saved (OK):       %d" % T["ok"])
    log(" Skipped - already done:        %d" % T["done"])
    log(" Skipped - single frame:        %d" % T["snap"])
    log(" Skipped - TileScan:            %d" % T["tile"])
    log(" Skipped - no frame interval:   %d" % T["nofi"])
    log(" Skipped - rate drop:           %d" % T["rate"])
    log(" Warnings (rate/length):        %d" % T["warn"])
    if cfg_state["global_fi"][0] > 0:
        log(" Reference rate:                %s Hz (%s s/frame)"
            % (d2s(1.0 / cfg_state["global_fi"][0], 2), d2s(cfg_state["global_fi"][0], 4)))
    if dry_run:
        log(" (DRY RUN - no files were written)")
    log("=============================================")
    log.close()


# Guard so the module can be imported for unit testing under CPython without
# executing the run. Fiji invokes the script normally (env var unset) -> runs.
if not os.environ.get("LIF_EXTRACT_NO_MAIN"):
    main()
