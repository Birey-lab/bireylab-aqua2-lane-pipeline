# movies_to_avi.py -- headless Fiji: AQuA2 *_Movie.tif stacks -> AVI
# ============================================================================
# AQuA2 writes a multi-frame overlay movie per recording as <stem>_AQuA2_Movie.tif.
# ffmpeg's TIFF decoder reads only the FIRST page of a multi-page TIFF (verified:
# a 893 MB movie reports 1 frame), so it can't transcode these directly. Fiji,
# however, reads the stack natively -- this script opens each _Movie.tif and writes
# a JPEG-compressed AVI; the orchestrator then transcodes AVI -> MP4 with ffmpeg
# (which reads AVI fine). Two hops, but each is a tool doing what it's reliable at.
#
# Driven by a key=value config file whose path is in env var MOVIES_CONFIG:
#   input_root  root to scan recursively for *_Movie.tif (PreCFU)
#   output_dir  where to write the .avi files
#   fps         AVI frame rate (default 20)
#   log         run log path
# Exit is implicit; per-file failures are logged and counted, never fatal.

import os

try:
    from ij import IJ
    _FIJI = True
except ImportError:
    _FIJI = False


def load_config():
    path = os.environ.get('MOVIES_CONFIG')
    if not path or not os.path.isfile(path):
        raise RuntimeError('MOVIES_CONFIG not set or file missing: %s' % path)
    cfg = {}
    f = open(path, 'r')
    try:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            cfg[k.strip()] = v.strip()
    finally:
        f.close()
    return cfg


def main():
    cfg = load_config()
    root = cfg.get('input_root', '')
    outdir = cfg.get('output_dir', '')
    fps = cfg.get('fps', '20')
    logpath = cfg.get('log', '')

    logf = open(logpath, 'w') if logpath else None

    def w(msg):
        if logf:
            logf.write(msg + '\n'); logf.flush()
        try:
            IJ.log(msg)
        except Exception:
            try:
                print(msg)
            except Exception:
                pass

    if not os.path.isdir(root):
        w('[FATAL] input_root not found: %s' % root)
        if logf: logf.close()
        return
    if not os.path.isdir(outdir):
        os.makedirs(outdir)

    movies = []
    for dp, dn, fn in os.walk(root):
        if '_failures' in dp.lower():
            continue
        for f in fn:
            low = f.lower()
            if low.endswith('_movie.tif') or low.endswith('_movie.tiff'):
                movies.append(os.path.join(dp, f))
    movies.sort()

    w('=============================================')
    w(' MOVIES -> AVI (headless Fiji)')
    w(' input_root: %s' % root)
    w(' output_dir: %s' % outdir)
    w(' fps: %s' % fps)
    w(' found %d _Movie.tif file(s)' % len(movies))
    w('=============================================')

    ok = 0; failed = 0; skipped = 0
    for i, m in enumerate(movies):
        base = os.path.splitext(os.path.basename(m))[0]
        avi = os.path.join(outdir, base + '.avi')
        if os.path.exists(avi) and os.path.getsize(avi) > 0:
            w('  [SKIP] %s (avi already exists)' % base); skipped += 1; continue
        imp = IJ.openImage(m)
        if imp is None:
            w('  [FAIL] %s (could not open)' % base); failed += 1; continue
        try:
            n = imp.getStackSize()
            # AVI writer: JPEG compression keeps the intermediate reasonable.
            IJ.run(imp, "AVI... ", "compression=JPEG frame=%s save=[%s]" % (fps, avi))
            if os.path.exists(avi) and os.path.getsize(avi) > 0:
                w('  [OK]   %s | %d frames -> %s' % (base, n, os.path.basename(avi))); ok += 1
            else:
                w('  [FAIL] %s (no AVI written)' % base); failed += 1
        except Exception as e:
            w('  [FAIL] %s (%s)' % (base, str(e))); failed += 1
        finally:
            imp.close()

    w('=============================================')
    w(' TOTALS: %d converted, %d already present, %d failed (of %d)' % (ok, skipped, failed, len(movies)))
    w('=============================================')
    if logf:
        logf.close()


if not os.environ.get('MOVIES_NO_MAIN'):
    main()
