"""How far the engine moves each take's pitch: every take's variant 0 reference through cvoice on six lines, the
clone's median F0 against the reference's. Writes pack/drift.json {take: semitones}, which build_pack.py takes as a
per-take correction (the engine lifted some men 2-7 semitones above their designs, 2026-11-05).

  python measure_drift.py [--sex m|f|all] [--voices pack/out/voices] [--out pack/drift.json]
Needs a built pack (variant 0 of each take), build/linux/cvoice and praat-parselmouth.
"""
import argparse, glob, json, os, struct, subprocess, tempfile
import numpy as np, parselmouth

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, '..')
LINES = ["Careful, there's another patrol coming round the hill. Wait for it to pass.", "Thanks for the help back there. I owe you one.",
         "Right, that's the last of them. Shall we move on?", "I'm almost out of mana. Can we sit for a bit?",
         "Behind you! Move! There's three more coming!", "Ha! Did you see that? Three of them, one swing!"]

def f0(snd, female):
    f = snd.to_pitch(pitch_floor=100 if female else 60, pitch_ceiling=600 if female else 400).selected_array['frequency']
    f = f[f > 0]; return float(np.median(f)) if len(f) else 0.0

def main():
    a = argparse.ArgumentParser()
    a.add_argument('--sex', default='all'); a.add_argument('--voices', default=os.path.join(ROOT, 'pack', 'out', 'voices'))
    a.add_argument('--out', default=os.path.join(ROOT, 'pack', 'drift.json'))
    a.add_argument('--exe', default=os.path.join(ROOT, 'build', 'linux', 'cvoice'))
    a.add_argument('--model', default=os.path.join(ROOT, 'third_party', 'sherpa-onnx-pocket-tts-int8-2026-01-26'))
    o = a.parse_args()
    pat = {'m': '*_m_*', 'f': '*_f_*'}.get(o.sex, '*')
    refs = sorted(glob.glob(os.path.join(o.voices, f'{pat}_0_neutral.mp3')))
    p = subprocess.Popen([o.exe, '--model', o.model, '--threads', '8'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    def frame():
        h = p.stdout.read(9); t, i, n = struct.unpack('<cII', h); return t.decode(), i, p.stdout.read(n)
    assert frame()[0] == 'R'
    k = 0; jobs = {}
    for r in refs:
        for l in LINES:
            k += 1; jobs[k] = r; p.stdin.write(f'SPEAK\t{k}\t{os.path.abspath(r)}\t{l}\n'.encode())
    p.stdin.flush(); audio = {}; ended = 0
    while ended < k:
        t, i, v = frame()
        if t == 'A': audio.setdefault(i, bytearray()).extend(v)
        elif t == 'E': ended += 1
    p.stdin.close(); p.wait()
    clones = {}
    for i, r in jobs.items():
        female = '_f_' in os.path.basename(r)
        x = np.frombuffer(bytes(audio[i]), dtype='<i2').astype(np.float64) / 32768
        clones.setdefault(r, []).append(f0(parselmouth.Sound(x, sampling_frequency=24000), female))
    drift = json.load(open(o.out)) if os.path.exists(o.out) else {}
    for r, fs in clones.items():
        take = os.path.basename(r).rsplit('_', 2)[0]; female = '_f_' in take
        with tempfile.NamedTemporaryFile(suffix='.wav') as t:
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', r, t.name], check=True); rf = f0(parselmouth.Sound(t.name), female)
        st = round(float(12 * np.log2(np.median(fs) / rf)), 1); drift[take] = st
        print(f'{take:22s} reference {rf:4.0f} Hz, clone {np.median(fs):4.0f} Hz: {st:+.1f} st', flush=True)
    json.dump(drift, open(o.out, 'w'), indent=1, sort_keys=True)

if __name__ == '__main__':
    main()
