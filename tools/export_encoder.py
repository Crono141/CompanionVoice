"""Export Pocket TTS's voice encoder (Mimi encode_to_latent + the speaker projection) to ONNX with a variable audio
length, as a drop-in replacement for the encoder.onnx in sherpa-onnx's Pocket package.

Why (2026-11-05): the encoder.onnx in sherpa-onnx-pocket-tts-*-2026-01-26 returns a fixed 13 latent frames (about
1.04 s) whatever the input length -- the export froze its tracing input's length. Every voice was cloned from only
the first second of its reference: weak likeness, and a prompt cut mid-word, which makes the model start each
sentence by finishing that word ("airful" for "Careful"). Kyutai's own runtime encodes the whole (end_on_pause'd)
reference.

  python export_encoder.py [--out third_party/encoder-dynamic.onnx] [--check third_party/.../encoder.onnx]

Uses only the official pocket-tts package (its weights: the same ones sherpa's model files were exported from, which
--check verifies on a 1 s input) plus torch's ONNX exporter (onnx, onnxscript). Input "audio" [1, 1, T] float at
24 kHz; output "latents" [1, frames, 1024], the shapes sherpa expects.
"""
import argparse, os
import numpy as np, torch, torch.nn.functional as F

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, '..')


class VoiceEncoder(torch.nn.Module):
    def __init__(self, tts):
        super().__init__()
        self.mimi = tts.mimi
        self.proj = torch.nn.Parameter(tts.flow_lm.speaker_proj_weight.detach().clone(), requires_grad=False)

    def forward(self, audio):                       # the same as TTSModel._encode_audio
        latents = self.mimi.encode_to_latent(audio).to(torch.float32)
        return F.linear(latents, self.proj)


def main():
    a = argparse.ArgumentParser()
    a.add_argument('--out', default=os.path.join(ROOT, 'third_party', 'encoder-dynamic.onnx'))
    a.add_argument('--check', default=os.path.join(ROOT, 'third_party', 'sherpa-onnx-pocket-tts-int8-2026-01-26', 'encoder.onnx'))
    a.add_argument('--language', default='english')
    o = a.parse_args()
    from pocket_tts import TTSModel
    tts = TTSModel.load_model(language=o.language)
    enc = VoiceEncoder(tts).eval()
    # the package's own outputs for the checks, taken before exporting (the export leaves the module symbolic)
    rng = np.random.default_rng(1)
    speechy = (rng.standard_normal(24000 * 12) * 0.1).astype(np.float32)
    LENGTHS = (1.0, 2.0, 6.0, 11.0)
    expected = {}
    with torch.no_grad():
        for sec in LENGTHS:
            a_ = speechy[: int(sec * 24000)][None, None, :]
            expected[sec] = np.array(enc(torch.from_numpy(a_)).tolist(), dtype=np.float32)
    x = torch.randn(1, 1, 24000 * 4) * 0.1
    T = torch.export.Dim('T', min=24000 // 2, max=24000 * 30)
    with torch.no_grad():
        prog = torch.onnx.export(enc, (x,), dynamo=True, input_names=['audio'], output_names=['latents'],
                                 dynamic_shapes={'audio': {2: T}}, opset_version=17)
    prog.save(o.out)
    print('wrote', o.out, os.path.getsize(o.out) // 1_000_000, 'MB')

    import onnxruntime as ort
    new = ort.InferenceSession(o.out, providers=['CPUExecutionProvider'])
    old = ort.InferenceSession(o.check, providers=['CPUExecutionProvider']) if os.path.exists(o.check) else None
    for sec in LENGTHS:
        a_ = speechy[: int(sec * 24000)][None, None, :]
        y = new.run(None, {'audio': a_})[0]
        ref = expected[sec]
        line = f'{sec:4.1f} s: {y.shape[1]:3d} frames; matches pocket-tts {np.abs(y - ref).max():.2e}'
        if old is not None:
            yo = old.run(None, {old.get_inputs()[0].name: a_})[0]
            k = min(yo.shape[1], y.shape[1])
            line += f'; sherpa\'s encoder gives {yo.shape[1]} frames, first {k} differ by {np.abs(yo[:, :k] - y[:, :k]).max():.2e}'
        print(line)


if __name__ == '__main__':
    main()
