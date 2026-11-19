/* Speech (speech.h). On Windows: Prism (prism.dll in the mod's folder: every
 * screen reader it supports, or a Windows voice); without it, NVDA through its
 * controller client (nvdaControllerClient64.dll), JAWS through its COM
 * interface, or SAPI. Elsewhere (tests): written to stderr and, if
 * DQIX_SPEECH_LOG names a file, to that file. */
#include "speech.h"
#include "access.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE* g_speech_log;
static void log_text(const char* tag, const char* s) {
    static int init;
    if (!init) { init = 1; const char* p = getenv("DQIX_SPEECH_LOG"); if (p) g_speech_log = fopen(p, "a"); }
    if (g_speech_log) { fprintf(g_speech_log, "%s%s\n", tag, s); fflush(g_speech_log); }
}

#ifdef _WIN32
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <sapi.h>
#include <stdint.h>
#include <stdbool.h>

/* ---------------------------------------------------------------- NVDA */
typedef unsigned long (__stdcall *NvdaTest)(void);
typedef unsigned long (__stdcall *NvdaSpeak)(const wchar_t*);
typedef unsigned long (__stdcall *NvdaCancel)(void);
static HMODULE g_nvda;
static NvdaTest nvda_test; static NvdaSpeak nvda_speak; static NvdaCancel nvda_cancel;

static int nvda_running(void) {
    if (!g_nvda) {
        static int tried;
        if (tried) return 0;
        tried = 1;
        g_nvda = LoadLibraryA("nvdaControllerClient64.dll");
        if (!g_nvda) {                                          /* the copy in the mod's folder */
            char p[700];
            snprintf(p, sizeof p, "%snvdaControllerClient64.dll", access_dir());
            g_nvda = LoadLibraryA(p);
        }
        if (!g_nvda) g_nvda = LoadLibraryA("access\\nvdaControllerClient64.dll");
        if (!g_nvda) return 0;
        nvda_test = (NvdaTest)(void*)GetProcAddress(g_nvda, "nvdaController_testIfRunning");
        nvda_speak = (NvdaSpeak)(void*)GetProcAddress(g_nvda, "nvdaController_speakText");
        nvda_cancel = (NvdaCancel)(void*)GetProcAddress(g_nvda, "nvdaController_cancelSpeech");
        if (!nvda_test || !nvda_speak || !nvda_cancel) { FreeLibrary(g_nvda); g_nvda = NULL; return 0; }
    }
    return nvda_test() == 0;
}

/* ---------------------------------------------------------------- JAWS (FreedomSci.JawsApi, IDispatch) */
static IDispatch* g_jaws;
static DISPID g_jaws_say = DISPID_UNKNOWN, g_jaws_stop = DISPID_UNKNOWN;
static int jaws_running(void) {
    if (!FindWindowW(L"JFWUI2", NULL)) return 0;               /* JAWS's main window */
    if (!g_jaws) {
        CLSID clsid;
        if (FAILED(CLSIDFromProgID(L"FreedomSci.JawsApi", &clsid))) return 0;
        if (FAILED(CoCreateInstance(&clsid, NULL, CLSCTX_ALL, &IID_IDispatch, (void**)&g_jaws))) { g_jaws = NULL; return 0; }
        LPOLESTR n1 = L"SayString", n2 = L"StopSpeech";
        IDispatch_GetIDsOfNames(g_jaws, &IID_NULL, &n1, 1, LOCALE_USER_DEFAULT, &g_jaws_say);
        IDispatch_GetIDsOfNames(g_jaws, &IID_NULL, &n2, 1, LOCALE_USER_DEFAULT, &g_jaws_stop);
    }
    return g_jaws != NULL;
}
static void jaws_say(const wchar_t* w, int interrupt) {
    VARIANT args[2]; VariantInit(&args[0]); VariantInit(&args[1]);
    args[1].vt = VT_BSTR; args[1].bstrVal = SysAllocString(w);       /* (arguments in reverse order) */
    args[0].vt = VT_BOOL; args[0].boolVal = interrupt ? VARIANT_TRUE : VARIANT_FALSE;
    DISPPARAMS dp = { args, NULL, 2, 0 };
    VARIANT r; VariantInit(&r);
    IDispatch_Invoke(g_jaws, g_jaws_say, &IID_NULL, LOCALE_USER_DEFAULT, DISPATCH_METHOD, &dp, &r, NULL, NULL);
    SysFreeString(args[1].bstrVal);
}
static void jaws_stop(void) {
    DISPPARAMS dp = { NULL, NULL, 0, 0 };
    VARIANT r; VariantInit(&r);
    if (g_jaws_stop != DISPID_UNKNOWN) IDispatch_Invoke(g_jaws, g_jaws_stop, &IID_NULL, LOCALE_USER_DEFAULT, DISPATCH_METHOD, &dp, &r, NULL, NULL);
}


/* ---------------------------------------------------------------- Prism
 * prism.dll (github.com/ethindp/prism, MPL 2.0), in the mod's folder: one way to
 * talk through every screen reader it knows (NVDA, JAWS, Narrator, ZDSR, System
 * Access, PC-Talker, ZoomText, Window-Eyes...) or a Windows voice. Used first when
 * it is there; without it, the NVDA / JAWS / SAPI code below. Loaded at run time,
 * so the game builds and runs without it. */
typedef struct {
    uint8_t version;
    void* registry;
    void (__cdecl *availability_callback)(void*, uint64_t, const char*, bool);
    void* availability_userdata;
    uint32_t availability_poll_interval_ms, availability_debounce_samples, availability_backoff_max_ms;
    bool availability_auto_power_manage;
    void (__cdecl *availability_baseline_callback)(void*);
} PrismCfg;
enum { PRISM_E_NOT_INITIALIZED = 1, PRISM_E_BACKEND_NOT_AVAILABLE = 16 };
static PrismCfg (__cdecl *pr_config_init)(void);
static void* (__cdecl *pr_init)(PrismCfg*);
static void* (__cdecl *pr_create_best)(void*);
static void (__cdecl *pr_free)(void*);
static const char* (__cdecl *pr_name)(void*);
static int (__cdecl *pr_output)(void*, const char*, bool);
static int (__cdecl *pr_stop)(void*);
static void* g_pr_ctx;
static void* g_pr;
static volatile LONG g_pr_reselect = 1;
static char g_pr_name[64];
static void __cdecl pr_changed(void* u, uint64_t id, const char* name, bool available) {
    (void)u; (void)id; (void)name; (void)available;
    InterlockedExchange(&g_pr_reselect, 1);                       /* (Prism's thread: only note it) */
}
static void __cdecl pr_baseline(void* u) { (void)u; InterlockedExchange(&g_pr_reselect, 1); }
static int prism_load(void) {
    static int tried;
    if (g_pr_ctx) return 1;
    if (tried) return 0;
    tried = 1;
    char p[700];
    snprintf(p, sizeof p, "%sprism.dll", access_dir());
    HMODULE m = LoadLibraryExA(p, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!m) m = LoadLibraryA("prism.dll");
    if (!m) return 0;
    FARPROC f;
#define GET(v, n) (f = GetProcAddress(m, n), memcpy(&v, &f, sizeof v), f != NULL)
    if (!GET(pr_config_init, "prism_config_init") || !GET(pr_init, "prism_init") || !GET(pr_create_best, "prism_registry_create_best") ||
        !GET(pr_free, "prism_backend_free") || !GET(pr_name, "prism_backend_name") || !GET(pr_output, "prism_backend_output") ||
        !GET(pr_stop, "prism_backend_stop")) return 0;
#undef GET
    PrismCfg cfg = pr_config_init();
    cfg.availability_callback = pr_changed;
    cfg.availability_baseline_callback = pr_baseline;
    g_pr_ctx = pr_init(&cfg);
    return g_pr_ctx != NULL;
}
/* the backend to use now: chosen again when Prism says what is running has changed
 * (a screen reader started or closed), and tried again every 2 seconds while there is none */
static void* prism_backend(void) {
    static DWORD tried;
    if (!prism_load()) return NULL;
    if (InterlockedExchange(&g_pr_reselect, 0)) { if (g_pr) { pr_free(g_pr); g_pr = NULL; } tried = 0; }
    if (!g_pr) {
        DWORD now = GetTickCount();
        if (tried && now - tried < 2000) return NULL;
        tried = now | 1;
        g_pr = pr_create_best(g_pr_ctx);
        const char* n = g_pr ? pr_name(g_pr) : NULL;
        snprintf(g_pr_name, sizeof g_pr_name, "%s", n ? n : "none");
    }
    return g_pr;
}
static int prism_say(const char* s, int interrupt) {
    void* b = prism_backend();
    if (!b) return 0;
    int e = pr_output(b, s, interrupt != 0);
    if (e == PRISM_E_BACKEND_NOT_AVAILABLE || e == PRISM_E_NOT_INITIALIZED) {   /* the screen reader was closed */
        pr_free(g_pr);
        g_pr = pr_create_best(g_pr_ctx);
        if (!g_pr) return 0;
        const char* n = pr_name(g_pr);
        snprintf(g_pr_name, sizeof g_pr_name, "%s", n ? n : "none");
        e = pr_output(g_pr, s, interrupt != 0);
    }
    return e == 0;
}

/* ---------------------------------------------------------------- SAPI */
static ISpVoice* g_sapi;
static int sapi_ready(void) {
    static int tried;
    if (g_sapi) return 1;
    if (tried) return 0;
    tried = 1;
    if (FAILED(CoCreateInstance(&CLSID_SpVoice, NULL, CLSCTX_ALL, &IID_ISpVoice, (void**)&g_sapi))) g_sapi = NULL;
    return g_sapi != NULL;
}

static int g_com;
static const char* g_engine = "none";
static char g_engine_buf[96];
void speech_init(void) {
    if (!g_com) { HRESULT h = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED); g_com = SUCCEEDED(h) || h == RPC_E_CHANGED_MODE; }
}
static wchar_t* widen(const char* s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (n <= 0) {                                                  /* not UTF-8: the old code page */
        n = MultiByteToWideChar(CP_ACP, 0, s, -1, NULL, 0);
        wchar_t* w = malloc(sizeof(wchar_t) * (size_t)(n > 0 ? n : 1));
        if (n > 0) MultiByteToWideChar(CP_ACP, 0, s, -1, w, n); else w[0] = 0;
        return w;
    }
    wchar_t* w = malloc(sizeof(wchar_t) * (size_t)n);
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}
/* which engine to use now (the player may start or quit the screen reader while playing) */
static int pick(void) {
    static DWORD last; static int which;
    DWORD now = GetTickCount();
    if (last && now - last < 2000) return which;
    last = now;
    speech_init();
    if (nvda_running()) which = 1;
    else if (jaws_running()) which = 2;
    else if (sapi_ready()) which = 3;
    else which = 0;
    g_engine = which == 1 ? "NVDA" : which == 2 ? "JAWS" : which == 3 ? "SAPI" : "none";
    return which;
}
void speech_say(const char* s, int interrupt) {
    if (!s || !*s) return;
    log_text(interrupt ? "! " : "  ", s);
    speech_init();
    if (prism_say(s, interrupt)) { g_engine = g_pr_name; return; }
    wchar_t* w = widen(s);
    switch (pick()) {
    case 1: if (interrupt) nvda_cancel(); nvda_speak(w); break;
    case 2: jaws_say(w, interrupt); break;
    case 3: ISpVoice_Speak(g_sapi, w, SPF_ASYNC | SPF_IS_NOT_XML | (interrupt ? SPF_PURGEBEFORESPEAK : 0), NULL); break;
    default: break;
    }
    free(w);
}
void speech_stop(void) {
    log_text("# ", "(stop)");
    if (prism_backend()) { pr_stop(g_pr); return; }
    switch (pick()) {
    case 1: nvda_cancel(); break;
    case 2: jaws_stop(); break;
    case 3: ISpVoice_Speak(g_sapi, L"", SPF_ASYNC | SPF_PURGEBEFORESPEAK, NULL); break;
    default: break;
    }
}
const char* speech_engine(void) {
    speech_init();
    if (prism_backend()) { snprintf(g_engine_buf, sizeof g_engine_buf, "%s (Prism)", g_pr_name); return g_engine_buf; }
    pick(); return g_engine;
}
void speech_shutdown(void) {
    if (g_pr) { pr_free(g_pr); g_pr = NULL; }
    if (g_sapi) { ISpVoice_Release(g_sapi); g_sapi = NULL; }
    if (g_jaws) { IDispatch_Release(g_jaws); g_jaws = NULL; }
}

#else
void speech_init(void) {}
void speech_say(const char* s, int interrupt) {
    if (!s || !*s) return;
    log_text(interrupt ? "! " : "  ", s);
    if (!getenv("DQIX_SPEECH_QUIET")) fprintf(stderr, "[speech%s] %s\n", interrupt ? "!" : "", s);
}
void speech_stop(void) { log_text("# ", "(stop)"); }
const char* speech_engine(void) { return "log"; }
void speech_shutdown(void) {}
#endif
