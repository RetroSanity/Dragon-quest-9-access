/* Sound for the access mod: short sounds placed all round you on headphones (OpenAL Soft with
 * HRTF), for the walking beacon and the auto walk beep. Included by access.c (a .h so the build does not compile it on its own).
 *
 * OpenAL Soft is loaded from the mod's own folder (openal_soft.dll, LGPL: see
 * openal-licence/COPYING.txt) when the script first asks for a sound. Without it there is no
 * sound and sound.ready() says so.
 *
 * Lua:  sound.ready()                       -> true/false, true when HRTF is on
 *       sound.play(name, x, y, z, gain, pitch)  name: "knock", "lock", "chime", "beep", "bump"
 *                                           x right, y up, -z ahead of you, in metres
 */
#include <math.h>

#define AL_FORMAT_MONO16 0x1101
#define AL_BUFFER 0x1009
#define AL_POSITION 0x1004
#define AL_GAIN 0x100A
#define AL_PITCH 0x1003
#define AL_SOURCE_RELATIVE 0x202
#define AL_REFERENCE_DISTANCE 0x1020
#define AL_ROLLOFF_FACTOR 0x1021
#define ALC_HRTF_SOFT 0x1992
#define ALC_HRTF_STATUS_SOFT 0x1993
#define SND_RATE 44100
#define SND_SOURCES 8

typedef void* (*p_alcOpenDevice)(const char*);
typedef void* (*p_alcCreateContext)(void*, const int*);
typedef char (*p_alcMakeContextCurrent)(void*);
typedef void (*p_alcGetIntegerv)(void*, int, int, int*);
typedef void (*p_alGenBuffers)(int, unsigned*);
typedef void (*p_alBufferData)(unsigned, int, const void*, int, int);
typedef void (*p_alGenSources)(int, unsigned*);
typedef void (*p_alSourcei)(unsigned, int, int);
typedef void (*p_alSourcef)(unsigned, int, float);
typedef void (*p_alSource3f)(unsigned, int, float, float, float);
typedef void (*p_alSourcePlay)(unsigned);
typedef void (*p_alSourceStop)(unsigned);

static struct {
    int tried, ok, hrtf;
    p_alGenBuffers GenBuffers; p_alBufferData BufferData; p_alGenSources GenSources;
    p_alSourcei Sourcei; p_alSourcef Sourcef; p_alSource3f Source3f;
    p_alSourcePlay SourcePlay; p_alSourceStop SourceStop;
    unsigned buf[5];
    unsigned src[SND_SOURCES];
    int next;
} S;
static const char* SND_NAMES[5] = { "knock", "lock", "chime", "beep", "bump" };

/* the sounds, made here: mono 16-bit */
static unsigned snd_buffer(const short* d, int n) {
    unsigned b = 0;
    S.GenBuffers(1, &b);
    S.BufferData(b, AL_FORMAT_MONO16, d, n * 2, SND_RATE);
    return b;
}
static short snd_clip(double v) { if (v > 1) v = 1; if (v < -1) v = -1; return (short)(v * 32767); }
/* a short bright knock: a few tones and a touch of noise, struck and dying away (a pure tone is
 * hard to place) */
static unsigned snd_knock(double length, double base, double bright, double volume) {
    int n = (int)(SND_RATE * length);
    short* d = (short*)malloc(sizeof(short) * n);
    unsigned seed = 7; double noise = 0;
    for (int i = 0; i < n; i++) {
        double t = (double)i / SND_RATE;
        double env = (i < 60 ? i / 60.0 : 1.0) * exp(-t * 38);
        double v = sin(2 * M_PI * base * t) + 0.6 * sin(2 * M_PI * base * 2.01 * t)
                 + 0.35 * bright * sin(2 * M_PI * base * 3.03 * t) + 0.2 * bright * sin(2 * M_PI * base * 5.1 * t);
        seed = seed * 1103515245u + 12345u;
        noise = 0.6 * noise + 0.4 * (((seed >> 16) & 0x7FFF) / 16383.5 - 1.0);
        v = (v / 2.15 + 0.35 * bright * noise * exp(-t * 90)) * env;
        d[i] = snd_clip(v * volume);
    }
    unsigned b = snd_buffer(d, n);
    free(d);
    return b;
}
/* two quick rising notes: arrived (or a turn of the way reached) */
static unsigned snd_chime(double volume) {
    double f[2] = { 1175.0, 1568.0 }, ln[2] = { 0.07, 0.11 };
    int n = (int)(SND_RATE * (ln[0] + ln[1]));
    short* d = (short*)malloc(sizeof(short) * n);
    int k = 0;
    for (int j = 0; j < 2; j++) {
        int m = (int)(SND_RATE * ln[j]);
        for (int i = 0; i < m && k < n; i++, k++) {
            double t = (double)i / SND_RATE;
            double env = (i < 80 ? i / 80.0 : 1.0) * ((m - i) < 300 ? (m - i) / 300.0 : 1.0);
            d[k] = snd_clip((sin(2 * M_PI * f[j] * t) + 0.3 * sin(4 * M_PI * f[j] * t)) / 1.3 * env * volume);
        }
    }
    unsigned b = snd_buffer(d, k);
    free(d);
    return b;
}
/* a plain short beep */
static unsigned snd_beep(double freq, double length, double volume) {
    int n = (int)(SND_RATE * length);
    short* d = (short*)malloc(sizeof(short) * n);
    for (int i = 0; i < n; i++) {
        double env = i < 200 ? i / 200.0 : 1.0;
        if (n - i < 200) env = (n - i) / 200.0;
        d[i] = snd_clip(sin(2 * M_PI * freq * i / SND_RATE) * env * volume);
    }
    unsigned b = snd_buffer(d, n);
    free(d);
    return b;
}

static void* snd_sym(void* lib, const char* name) {
#ifdef _WIN32
    return (void*)GetProcAddress((HMODULE)lib, name);
#else
    (void)lib; (void)name; return NULL;
#endif
}
static void snd_init(void) {
    if (S.tried) return;
    S.tried = 1;
#ifdef _WIN32
    char p[700];
    snprintf(p, sizeof p, "%sopenal_soft.dll", g_dir);
    HMODULE lib = LoadLibraryA(p);
    if (!lib) { fprintf(stderr, "access: no 3D sound (%s not loaded)\n", p); return; }
    p_alcOpenDevice OpenDevice = (p_alcOpenDevice)snd_sym(lib, "alcOpenDevice");
    p_alcCreateContext CreateContext = (p_alcCreateContext)snd_sym(lib, "alcCreateContext");
    p_alcMakeContextCurrent MakeCurrent = (p_alcMakeContextCurrent)snd_sym(lib, "alcMakeContextCurrent");
    p_alcGetIntegerv GetIntegerv = (p_alcGetIntegerv)snd_sym(lib, "alcGetIntegerv");
    S.GenBuffers = (p_alGenBuffers)snd_sym(lib, "alGenBuffers");
    S.BufferData = (p_alBufferData)snd_sym(lib, "alBufferData");
    S.GenSources = (p_alGenSources)snd_sym(lib, "alGenSources");
    S.Sourcei = (p_alSourcei)snd_sym(lib, "alSourcei");
    S.Sourcef = (p_alSourcef)snd_sym(lib, "alSourcef");
    S.Source3f = (p_alSource3f)snd_sym(lib, "alSource3f");
    S.SourcePlay = (p_alSourcePlay)snd_sym(lib, "alSourcePlay");
    S.SourceStop = (p_alSourceStop)snd_sym(lib, "alSourceStop");
    if (!OpenDevice || !CreateContext || !MakeCurrent || !S.GenBuffers || !S.BufferData || !S.GenSources ||
        !S.Sourcei || !S.Sourcef || !S.Source3f || !S.SourcePlay || !S.SourceStop) return;
    void* dev = OpenDevice(NULL);
    if (!dev) { fprintf(stderr, "access: no 3D sound (no sound device)\n"); return; }
    int attrs[3] = { ALC_HRTF_SOFT, 1, 0 };
    void* ctx = CreateContext(dev, attrs);
    if (!ctx || !MakeCurrent(ctx)) return;
    int st = 0;
    if (GetIntegerv) GetIntegerv(dev, ALC_HRTF_STATUS_SOFT, 1, &st);
    S.hrtf = (st == 1 || st == 3 || st == 4);
    S.buf[0] = snd_knock(0.09, 520.0, 1.0, 0.8);
    S.buf[1] = snd_knock(0.07, 880.0, 1.4, 0.6);
    S.buf[2] = snd_chime(0.6);
    S.buf[3] = snd_beep(880.0, 0.05, 0.45);
    S.buf[4] = snd_knock(0.12, 160.0, 0.6, 0.9);
    S.GenSources(SND_SOURCES, S.src);
    for (int i = 0; i < SND_SOURCES; i++) {
        S.Sourcei(S.src[i], AL_SOURCE_RELATIVE, 1);           /* placed round the listener, who never moves */
        S.Sourcef(S.src[i], AL_REFERENCE_DISTANCE, 1.5f);
        S.Sourcef(S.src[i], AL_ROLLOFF_FACTOR, 0.6f);
    }
    S.ok = 1;
    fprintf(stderr, "access: 3D sound ready, HRTF %s\n", S.hrtf ? "on" : "off");
#endif
}
static int snd_ready(lua_State* l) {
    snd_init();
    lua_pushboolean(l, S.ok);
    lua_pushboolean(l, S.hrtf);
    return 2;
}
static int snd_play(lua_State* l) {
    snd_init();
    if (!S.ok) { lua_pushboolean(l, 0); return 1; }
    const char* name = luaL_checkstring(l, 1);
    int k = -1;
    for (int i = 0; i < 5; i++) if (!strcmp(name, SND_NAMES[i])) k = i;
    if (k < 0) { lua_pushboolean(l, 0); return 1; }
    float x = (float)luaL_optnumber(l, 2, 0), y = (float)luaL_optnumber(l, 3, 0), z = (float)luaL_optnumber(l, 4, -1);
    float gain = (float)luaL_optnumber(l, 5, 1), pitch = (float)luaL_optnumber(l, 6, 1);
    unsigned s = S.src[S.next];
    S.next = (S.next + 1) % SND_SOURCES;
    S.SourceStop(s);
    S.Sourcei(s, AL_BUFFER, (int)S.buf[k]);
    S.Sourcef(s, AL_GAIN, gain);
    S.Sourcef(s, AL_PITCH, pitch > 0.1f ? pitch : 1.0f);
    S.Source3f(s, AL_POSITION, x, y, z);
    S.SourcePlay(s);
    lua_pushboolean(l, 1);
    return 1;
}
