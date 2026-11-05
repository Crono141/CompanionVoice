// cvoice: the Companion Voice speech helper. Pocket TTS (sherpa-onnx C API) in a 64-bit process of its own, so
// the 32-bit game never carries the model or its CPU time. Protocol (DESIGN.md):
//   stdin, one request per line, tab-separated:  SPEAK <id> <reference clip> <text> [<speed>] | CANCEL <id> | QUIT
//   stdout, frames: uint8 type, uint32 id, uint32 len, payload  (R ready, A int16 24 kHz mono audio, E end, X error)
// One utterance at a time, below-normal priority. It exits when stdin closes, so it never outlives the game.
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstring>
#include <deque>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DEVICE_IO
#define MA_NO_ENGINE
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_GENERATION
#include "vendor/miniaudio.h"
#include "sherpa-onnx/c-api/c-api.h"

static const char *VERSION = "cvoice 0.1";
static const int RATE = 24000;

// ---------------------------------------------------------------- output frames
static std::mutex g_out;
static void frame(char type, uint32_t id, const void *payload, uint32_t len)
{
    std::lock_guard<std::mutex> lock(g_out);
    unsigned char h[9] = {(unsigned char)type};
    memcpy(h + 1, &id, 4); memcpy(h + 5, &len, 4);  // little-endian on every target we build
    fwrite(h, 1, 9, stdout);
    if (len) fwrite(payload, 1, len, stdout);
    fflush(stdout);
}
static void error(uint32_t id, const std::string &msg) { frame('X', id, msg.data(), (uint32_t)msg.size()); }

// ---------------------------------------------------------------- the job queue
struct Job { uint32_t id; std::string ref, text; float speed; };
static float g_speed = 1.0f;   // --speed, for a SPEAK without one
static std::mutex g_q;
static std::condition_variable g_qc;
static std::deque<Job> g_jobs;
static std::set<uint32_t> g_cancelled;   // ids cancelled while speaking; checked by the audio callback
static bool g_quit = false;

static void split(const std::string &s, std::vector<std::string> &out, size_t max)
{
    size_t a = 0;
    while (out.size() + 1 < max) {
        size_t b = s.find('\t', a);
        if (b == std::string::npos) break;
        out.push_back(s.substr(a, b - a)); a = b + 1;
    }
    out.push_back(s.substr(a));
}

static void reader()
{
    std::string line; int c;
    for (;;) {
        line.clear();
        while ((c = fgetc(stdin)) != EOF && c != '\n') if (c != '\r') line.push_back((char)c);
        if (c == EOF && line.empty()) break;
        std::vector<std::string> f; split(line, f, 5);
        std::lock_guard<std::mutex> lock(g_q);
        if (f[0] == "SPEAK" && f.size() >= 4) {
            float sp = f.size() == 5 ? (float)atof(f[4].c_str()) : 0.0f;
            if (!(sp >= 0.5f && sp <= 2.0f)) sp = g_speed;                // 0.5-2.0, else the default
            g_jobs.push_back({(uint32_t)strtoul(f[1].c_str(), nullptr, 10), f[2], f[3], sp});
        } else if (f[0] == "CANCEL" && f.size() >= 2) {
            uint32_t id = (uint32_t)strtoul(f[1].c_str(), nullptr, 10);
            bool queued = false;
            for (auto it = g_jobs.begin(); it != g_jobs.end(); ++it)
                if (it->id == id) { g_jobs.erase(it); queued = true; break; }
            if (!queued) g_cancelled.insert(id);
        } else if (f[0] == "QUIT") {
            break;
        } else if (!line.empty()) {
            fprintf(stderr, "cvoice: unknown request: %.80s\n", line.c_str());
        }
        g_qc.notify_one();
    }
    std::lock_guard<std::mutex> lock(g_q);
    g_quit = true; g_qc.notify_one();   // stdin closed (the game exited) or QUIT
}

// ---------------------------------------------------------------- tempo
// Speech rate: Pocket TTS speaks at its reference's pace (sherpa's own speed setting moved it 2-4%), so a speed other
// than 1 stretches the REFERENCE in time, pitch kept (WSOLA), before the voice is taken from it. The output itself is
// never processed: shifting output was rejected by ear in Living Voices ("audible autotune").
static std::vector<float> stretch(const std::vector<float> &in, float tempo)
{
    const int N = 960, Hs = N / 2, SEARCH = 240;                // 40 ms frames, 20 ms output hop, +-10 ms search
    const float Ha = Hs * tempo;
    if (in.size() < (size_t)(N * 4)) return in;
    std::vector<float> win(N), out((size_t)(in.size() / tempo) + N, 0.0f), norm(out.size(), 0.0f);
    for (int i = 0; i < N; i++) win[i] = 0.5f - 0.5f * cosf(6.2831853f * i / N);
    long prev = 0;                                               // where the last frame was taken from
    size_t o = 0;
    for (int k = 0;; k++, o += Hs) {
        long ideal = (long)(k * Ha);
        if (ideal + N + SEARCH >= (long)in.size() || o + N > out.size()) break;
        long best = ideal;
        if (k) {                                                 // the frame most like the natural continuation
            float bestc = -1e30f;
            const float *nat = &in[prev + Hs];
            for (long d = -SEARCH; d <= SEARCH; d += 2) {
                long c = ideal + d;
                if (c < 0) continue;
                float acc = 0;
                for (int i = 0; i < N; i += 4) acc += nat[i] * in[c + i];
                if (acc > bestc) { bestc = acc; best = c; }
            }
        }
        for (int i = 0; i < N; i++) { out[o + i] += in[best + i] * win[i]; norm[o + i] += win[i]; }
        prev = best;
    }
    out.resize(o + Hs);
    for (size_t i = 0; i < out.size(); i++) if (norm[i] > 1e-3f) out[i] /= norm[i];
    return out;
}

// ---------------------------------------------------------------- reference clips
// Decoded once to 24 kHz mono float and kept; sherpa caches the voice embedding it computes from them.
static std::unordered_map<std::string, std::vector<float>> g_refs;
static const std::vector<float> *reference(const std::string &path, float tempo, std::string &why)
{
    if (tempo < 0.97f || tempo > 1.03f) {                        // the stretched clip, made once per voice and speed
        char key[32]; snprintf(key, sizeof key, "@%.2f", tempo);
        auto st = g_refs.find(path + key);
        if (st != g_refs.end()) return &st->second;
        const std::vector<float> *plain = reference(path, 1.0f, why);
        if (!plain) return nullptr;
        std::vector<float> s = stretch(*plain, tempo);
        return &(g_refs[path + key] = std::move(s));
    }
    auto it = g_refs.find(path);
    if (it != g_refs.end()) return &it->second;
    if (g_refs.size() >= 64) g_refs.clear();   // a party has a handful of voices; this only bounds memory
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 1, RATE);
    ma_decoder dec;
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
    std::wstring w(n, L'\0'); MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, &w[0], n);
    ma_result r = ma_decoder_init_file_w(w.c_str(), &cfg, &dec);
#else
    ma_result r = ma_decoder_init_file(path.c_str(), &cfg, &dec);
#endif
    if (r != MA_SUCCESS) { why = "cannot open reference " + path; return nullptr; }
    std::vector<float> pcm; float buf[4096]; ma_uint64 got = 0;
    while (ma_decoder_read_pcm_frames(&dec, buf, 4096, &got) == MA_SUCCESS && got) pcm.insert(pcm.end(), buf, buf + got);
    ma_decoder_uninit(&dec);
    if (pcm.size() < RATE) { why = "reference shorter than 1 s: " + path; return nullptr; }
    return &(g_refs[path] = std::move(pcm));
}

// ---------------------------------------------------------------- generation
struct Ctx { uint32_t id; std::vector<int16_t> buf; };
static int32_t on_audio(const float *s, int32_t n, float progress, void *arg)
{
    Ctx *c = (Ctx *)arg; (void)progress;
    {
        std::lock_guard<std::mutex> lock(g_q);
        if (g_quit || g_cancelled.count(c->id)) return 0;   // stop generating
    }
    c->buf.resize(n);
    for (int32_t i = 0; i < n; i++) {
        float v = s[i] * 32767.0f;
        c->buf[i] = (int16_t)(v > 32767.0f ? 32767 : v < -32768.0f ? -32768 : v);
    }
    frame('A', c->id, c->buf.data(), (uint32_t)(n * 2));
    return 1;
}

static std::string arg(int argc, char **argv, const char *name, const char *def)
{
    for (int i = 1; i + 1 < argc; i++) if (!strcmp(argv[i], name)) return argv[i + 1];
    return def;
}

int main(int argc, char **argv)
{
#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stdin), _O_BINARY);
    SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
#else
    if (nice(5) == -1) { /* best effort */ }
#endif
    std::string dir = arg(argc, argv, "--model", "model");
    int threads = atoi(arg(argc, argv, "--threads", "2").c_str());
    int steps = atoi(arg(argc, argv, "--steps", "1").c_str());
    // sentences generated together. 1 starts audio soonest, but each sentence then begins afresh from the reference:
    // prosody resets at every full stop and more first words come out wrong. A whole chat line (10) was as quick to
    // first audio and matched the Python trials' pace (2.79 vs 2.77 words/s); first words heard right 34/50 vs 29/50
    // (ASR, 2026-11-05). The pause between sentences at the engine's own scale (1.0; 0.2 sounded rushed).
    int sentences = atoi(arg(argc, argv, "--sentences", "10").c_str());
    float silence = (float)atof(arg(argc, argv, "--silence", "1.0").c_str());
    g_speed = (float)atof(arg(argc, argv, "--speed", "1.0").c_str());
    if (!(g_speed >= 0.5f && g_speed <= 2.0f)) g_speed = 1.0f;
    std::string p[7]; const char *names[7] = {"lm_flow.int8.onnx", "lm_main.int8.onnx", "encoder.onnx", "decoder.int8.onnx",
                                              "text_conditioner.onnx", "vocab.json", "token_scores.json"};
    for (int i = 0; i < 7; i++) {
        p[i] = dir + "/" + names[i];
        std::string full = p[i];                                   // the full-precision model if no int8 one
        size_t k = full.find(".int8.onnx");
        if (k != std::string::npos) {
            FILE *f = fopen(p[i].c_str(), "rb");
            if (f) fclose(f); else p[i] = full.replace(k, 10, ".onnx");
        }
    }
    SherpaOnnxOfflineTtsConfig c; memset(&c, 0, sizeof c);
    c.model.pocket.lm_flow = p[0].c_str(); c.model.pocket.lm_main = p[1].c_str(); c.model.pocket.encoder = p[2].c_str();
    c.model.pocket.decoder = p[3].c_str(); c.model.pocket.text_conditioner = p[4].c_str();
    c.model.pocket.vocab_json = p[5].c_str(); c.model.pocket.token_scores_json = p[6].c_str();
    c.model.pocket.voice_embedding_cache_capacity = 32;
    c.model.num_threads = threads > 0 ? threads : 2; c.model.provider = "cpu"; c.max_num_sentences = sentences > 0 ? sentences : 1;
    const SherpaOnnxOfflineTts *tts = SherpaOnnxCreateOfflineTts(&c);
    if (!tts) { error(0, "cannot load the speech model from " + dir); return 1; }
    frame('R', 0, VERSION, (uint32_t)strlen(VERSION));

    std::thread(reader).detach();
    for (;;) {
        Job job;
        {
            std::unique_lock<std::mutex> lock(g_q);
            g_qc.wait(lock, [] { return g_quit || !g_jobs.empty(); });
            if (g_quit) break;
            job = g_jobs.front(); g_jobs.pop_front();
            g_cancelled.clear();   // only the utterance about to start can be cancelled mid-way
        }
        std::string why;
        const std::vector<float> *ref = reference(job.ref, job.speed, why);
        if (!ref) { error(job.id, why); frame('E', job.id, nullptr, 0); continue; }   // every SPEAK ends with one E
        SherpaOnnxGenerationConfig g; memset(&g, 0, sizeof g);
        g.reference_audio = ref->data(); g.reference_audio_len = (int32_t)ref->size(); g.reference_sample_rate = RATE;
        g.num_steps = steps; g.speed = 1.0f; g.silence_scale = silence;
        g.extra = "{\"max_reference_audio_len\": 15.0, \"seed\": -1}";
        Ctx ctx{job.id, {}};
        const SherpaOnnxGeneratedAudio *a = SherpaOnnxOfflineTtsGenerateWithConfig(tts, job.text.c_str(), &g, on_audio, &ctx);
        if (a) SherpaOnnxDestroyOfflineTtsGeneratedAudio(a);
        else error(job.id, "generation failed");
        frame('E', job.id, nullptr, 0);
    }
    SherpaOnnxDestroyOfflineTts(tts);
    return 0;
}
