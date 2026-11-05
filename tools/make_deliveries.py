"""Delivery references for every approved take: the take's voice reading a short passage urgently, amused, and weary,
made by IndexTTS-2 with an emotion vector, through ComfyUI (tts_audio_suite) behind the VRAM arbiter. Pocket TTS copies
a reference's delivery, so each of these becomes a delivery the engine can speak in.

  python make_deliveries.py [--takes DIR] [--out DIR] [--url URL] [take ...]

Women take the full emotion vector; men take half for urgent and amused: at full strength those pushed men's pitch up
by an octave or more (dwarf 125 Hz to ~300), and the user chose full for women, half for men by ear (2026-11-05).
Weary stays full for everyone (it only lowers and slows the voice; half strength was never needed for it).
--half TAKE... makes those takes' urgent and amused at half strength too: deep women's voices jumped like the men's
at full strength (night elf woman A, 160 Hz to 375 Hz urgent), so a clip more than 7 semitones above its design is
remade at half (2026-11-05: night elf A/B/D, tauren B, draenei B urgent, orc A amused).
A clip that already exists is kept. Run host-survey first: this loads IndexTTS-2 on card 0.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request
import requests

MOODS = {
    'urgent': ({'Afraid': 0.4, 'Surprised': 0.3, 'Angry': 0.2},
               "Behind you, move! There's three more coming over the ridge, and that caster's already started. "
               "Get to the trees, now! I'll hold them at the bridge as long as I can. Go, go!"),
    'amused': ({'Happy': 0.7, 'Surprised': 0.2},
               "Oh, that was brilliant. Did you see his face when the barrel went over? I've not laughed like that in "
               "weeks. Honestly, you can't take me anywhere, can you? Come on, let's see what else is out there."),
    'weary': ({'Melancholic': 0.5, 'Sad': 0.2, 'Calm': 0.3},
              "Right. That's the last of them, I think. My arms are aching and I could sleep for a week. Let's just "
              "sit here a moment, catch our breath, and then we'll head back to town. No rush."),
}

def main():
    a = argparse.ArgumentParser()
    a.add_argument('--takes', default=os.path.expanduser('~/Projects/LivingVoices/data/companion_voices'))
    a.add_argument('--out', default=None)
    a.add_argument('--url', default='http://127.0.0.1:42400')
    a.add_argument('--half', nargs='*', default=[])
    a.add_argument('only', nargs='*')
    o = a.parse_args()
    out = o.out or os.path.join(o.takes, 'deliveries'); os.makedirs(out, exist_ok=True)
    U = o.url

    def upload(p):
        r = requests.post(U + '/upload/image', files={'image': (os.path.basename(p), open(p, 'rb'))},
                          data={'type': 'input', 'subfolder': 'companion_voice', 'overwrite': 'true'}, timeout=60)
        r.raise_for_status(); j = r.json(); return f"{j['subfolder']}/{j['name']}"

    def run(wf):
        r = urllib.request.Request(U + '/prompt', data=json.dumps({'prompt': wf, 'client_id': 'companionvoice'}).encode(),
                                   headers={'Content-Type': 'application/json'})
        pid = json.load(urllib.request.urlopen(r, timeout=120))['prompt_id']
        t0 = time.time()
        while True:
            h = json.load(urllib.request.urlopen(f'{U}/history/{pid}', timeout=30))
            if pid in h: break
            if time.time() - t0 > 900: raise RuntimeError('no result after 15 min')
            time.sleep(1)
        st = h[pid]['status']
        if st.get('status_str') != 'success': raise RuntimeError(json.dumps(st.get('messages'))[-800:])
        return [x for v in h[pid]['outputs'].values() for x in v.get('audio', [])][0]

    takes = json.load(open(os.path.join(o.takes, 'manifest.json')))['takes']
    done = failed = 0
    for t in takes:
        take = t['file'].rsplit('.', 1)[0]
        if o.only and take not in o.only: continue
        half = not t['voice'].endswith('_f') or take in o.half   # men, and the takes named in --half
        spk = None
        for mood, (vec, text) in MOODS.items():
            dst = os.path.join(out, f'{take}_{mood}.flac')
            if os.path.exists(dst): continue
            spk = spk or upload(os.path.join(o.takes, t['file']))
            wf = {'1': {'class_type': 'IndexTTSEngineNode', 'inputs': {
                      'model_path': 'IndexTTS-2', 'device': 'cuda', 'emotion_alpha': 1.0, 'use_random': False,
                      'max_text_tokens_per_segment': 120, 'interval_silence': 200, 'temperature': 0.8, 'top_p': 0.8,
                      'top_k': 30, 'do_sample': True, 'length_penalty': 0.0, 'num_beams': 1, 'repetition_penalty': 10.0,
                      'max_mel_tokens': 1500, 'use_fp16': True, 'use_deepspeed': False, 'emotion_control': ['5', 0]}},
                  '2': {'class_type': 'LoadAudio', 'inputs': {'audio': spk}},
                  '5': {'class_type': 'IndexTTSEmotionOptionsNode', 'inputs': {k: v * (0.5 if half and mood != 'weary' else 1.0) for k, v in vec.items()}},
                  '3': {'class_type': 'UnifiedTTSTextNode', 'inputs': {'TTS_engine': ['1', 0], 'text': text,
                      'narrator_voice': 'none', 'seed': 1, 'opt_narrator': ['2', 0], 'enable_chunking': True,
                      'max_chars_per_chunk': 400, 'enable_audio_cache': False}},
                  '4': {'class_type': 'SaveAudio', 'inputs': {'audio': ['3', 0], 'filename_prefix': f'companion_voice/{take}_{mood}'}}}
            t0 = time.time()
            try:
                f = run(wf)
                q = urllib.parse.urlencode({'filename': f['filename'], 'subfolder': f['subfolder'], 'type': f.get('type', 'output')})
                urllib.request.urlretrieve(f'{U}/view?{q}', dst + '.part'); os.replace(dst + '.part', dst)
                done += 1; print(f'{take}_{mood}: {time.time() - t0:.0f} s', flush=True)
            except Exception as e:
                failed += 1; print(f'{take}_{mood}: FAILED {e}', flush=True)
    print(f'done {done}, failed {failed}')
    sys.exit(1 if failed else 0)

if __name__ == '__main__':
    main()
