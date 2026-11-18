/* Speech (speech.h). On Windows: NVDA through its controller client
 * (nvdaControllerClient64.dll next to the game), JAWS through its COM
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
    switch (pick()) {
    case 1: nvda_cancel(); break;
    case 2: jaws_stop(); break;
    case 3: ISpVoice_Speak(g_sapi, L"", SPF_ASYNC | SPF_PURGEBEFORESPEAK, NULL); break;
    default: break;
    }
}
const char* speech_engine(void) { pick(); return g_engine; }
void speech_shutdown(void) {
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
