"""Drive cvoice over its pipes as the DLL will: timing to first audio, a cancel mid-line, a bad reference, and a
clean exit when stdin closes. usage: test_cvoice.py CVOICE MODELDIR REF1 REF2 OUTDIR"""
import struct, subprocess, sys, time, wave, os
exe, model, ref1, ref2, out = sys.argv[1:6]; os.makedirs(out, exist_ok=True)
p = subprocess.Popen([exe, '--model', model, '--threads', '2'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
def frame():
    h = p.stdout.read(9)
    if len(h) < 9: return None
    t, i, n = struct.unpack('<cII', h); return t.decode(), i, p.stdout.read(n)
t0 = time.time(); t, _, v = frame(); assert t == 'R', t; print(f'ready in {time.time() - t0:.2f} s: {v.decode()}')
LINES = [(1, ref1, "Careful, there's another patrol coming round the hill. Wait for it to pass."),
         (2, ref2, "Ha! Did you see that? Three of them, one swing."),
         (3, ref1, "I'm almost out of mana. Can we sit for a bit before the next pack? My feet are killing me, and the healer needs a drink too."),
         (4, '/nonexistent.mp3', "This should fail."),
         (5, ref2, "On my way.")]
sent = {}
for i, r, text in LINES:
    p.stdin.write(f'SPEAK\t{i}\t{r}\t{text}\n'.encode()); sent[i] = time.time()
p.stdin.flush()
audio = {}; first = {}; ended = set(); errs = {}
while len(ended) < len(LINES):
    t, i, v = frame()
    if t == 'A':
        if i not in first:
            first[i] = time.time()
            if i == 3: p.stdin.write(b'CANCEL\t3\n'); p.stdin.flush()   # cancel line 3 once it starts speaking
        audio.setdefault(i, bytearray()).extend(v)
    elif t == 'E': ended.add(i); print(f'line {i}: end at {time.time() - t0:.2f} s, {len(audio.get(i, b"")) / 48000:.2f} s audio')
    elif t == 'X': errs[i] = v.decode(); print(f'line {i}: error: {errs[i]}')
for i, a in audio.items():
    with wave.open(f'{out}/line{i}.wav', 'wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(bytes(a))
print('first audio after the line was queued behind the ones before it:', {i: round(first[i] - sent[i], 2) for i in first})
p.stdin.close(); t = time.time(); rc = p.wait(timeout=10); print(f'exit {rc} {time.time() - t:.2f} s after stdin closed')
