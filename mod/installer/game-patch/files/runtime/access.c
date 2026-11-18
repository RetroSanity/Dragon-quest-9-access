/* Access mod (access.h): runs the DQ9 Access Lua script with a BizHawk-like API.
 *
 * The script was written for BizHawk's melonDS core. The game here is the same
 * code with the same memory, so the script's addresses all hold: only the API
 * around it is provided here instead of by the emulator:
 *   mainmemory.read_u8/s8/u16_le/s16_le/u32_le/s32_le/read_bytes_as_array/hash_region
 *   memory.read_u8/u16_le/u32_le(addr, domain)    domains "ROM", "ARM9 System Bus", "Main RAM"
 *   joypad.get() / joypad.set(t)                  the DS's buttons (set: for the next frame)
 *   input.get()                                    keys and controller buttons held, by name
 *   speech.say(text, interrupt) / speech.stop()
 *   console.log, event.onexit, emu.frameadvance, emu.framecount, gameinfo.getromname
 * The script runs as a Lua coroutine: emu.frameadvance() hands back to the game
 * until the next frame. It only reads memory; the game runs exactly the same
 * unless it presses buttons (auto walk), which go through the normal input
 * (recorded in bug reports, sent to friends in a session). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <windows.h>
#include <shlobj.h>
#endif
#include "nds.h"
#include "access.h"
#include "speech.h"
#include "frontend.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int g_access_on;
uint16_t g_access_keys_on, g_access_keys_off;

static lua_State* L;
static lua_State* g_co;          /* the script's coroutine */
static int g_co_ref = LUA_NOREF, g_exit_ref = LUA_NOREF;
static int g_done;

void access_say(const char* text, int interrupt) { if (g_access_on) speech_say(text, interrupt); }

/* ---------------------------------------------------------------- memory */
static uint32_t ram_off(lua_State* l, int idx) { return (uint32_t)luaL_checkinteger(l, idx) & (MAIN_RAM_SIZE - 1); }
static uint32_t rd(uint32_t off, int n) {
    uint32_t v = 0;
    for (int i = 0; i < n; i++) v |= (uint32_t)g_main_ram[(off + (uint32_t)i) & (MAIN_RAM_SIZE - 1)] << (8 * i);
    return v;
}
static int mm_u8(lua_State* l)  { lua_pushinteger(l, rd(ram_off(l, 1), 1)); return 1; }
static int mm_s8(lua_State* l)  { lua_pushinteger(l, (int8_t)rd(ram_off(l, 1), 1)); return 1; }
static int mm_u16(lua_State* l) { lua_pushinteger(l, rd(ram_off(l, 1), 2)); return 1; }
static int mm_s16(lua_State* l) { lua_pushinteger(l, (int16_t)rd(ram_off(l, 1), 2)); return 1; }
static int mm_u32(lua_State* l) { lua_pushinteger(l, rd(ram_off(l, 1), 4)); return 1; }
static int mm_s32(lua_State* l) { lua_pushinteger(l, (int32_t)rd(ram_off(l, 1), 4)); return 1; }
static int mm_bytes(lua_State* l) {
    uint32_t off = ram_off(l, 1);
    lua_Integer n = luaL_checkinteger(l, 2);
    if (n < 0) n = 0;
    if (n > MAIN_RAM_SIZE) n = MAIN_RAM_SIZE;
    lua_createtable(l, (int)n, 0);
    for (lua_Integer i = 0; i < n; i++) {
        lua_pushinteger(l, g_main_ram[(off + (uint32_t)i) & (MAIN_RAM_SIZE - 1)]);
        lua_rawseti(l, -2, i + 1);                                 /* 1-based, as BizHawk */
    }
    return 1;
}
/* PC-only additions (the script checks they exist): a run of memory as a Lua string, and the
 * offsets of the 4-byte-aligned words in a range that equal a value, or that point at
 * themselves plus a distance (value == BASE + offset + rel). Much faster than doing it in Lua. */
static int mm_string(lua_State* l) {
    uint32_t off = ram_off(l, 1);
    lua_Integer n = luaL_checkinteger(l, 2);
    if (n < 0) n = 0;
    if (n > MAIN_RAM_SIZE) n = MAIN_RAM_SIZE;
    if (off + (uint32_t)n <= MAIN_RAM_SIZE) { lua_pushlstring(l, (const char*)g_main_ram + off, (size_t)n); return 1; }
    luaL_Buffer b; luaL_buffinit(l, &b);
    for (lua_Integer i = 0; i < n; i++) luaL_addchar(&b, (char)g_main_ram[(off + (uint32_t)i) & (MAIN_RAM_SIZE - 1)]);
    luaL_pushresult(&b);
    return 1;
}
static int mm_find(lua_State* l, int rel_mode) {
    uint32_t off = ram_off(l, 1) & ~3u;
    lua_Integer n = luaL_checkinteger(l, 2);
    uint32_t want = (uint32_t)luaL_checkinteger(l, 3);
    lua_Integer max = luaL_optinteger(l, 4, 4096);
    if (n < 0) n = 0;
    if (off + (uint64_t)n > MAIN_RAM_SIZE) n = MAIN_RAM_SIZE - off;
    lua_newtable(l);
    lua_Integer k = 0;
    for (uint32_t i = 0; i + 4 <= (uint32_t)n && k < max; i += 4) {
        const uint8_t* q = g_main_ram + off + i;
        uint32_t v = q[0] | (uint32_t)q[1] << 8 | (uint32_t)q[2] << 16 | (uint32_t)q[3] << 24;
        uint32_t target = rel_mode ? 0x02000000u + off + i + want : want;
        if (v == target) { lua_pushinteger(l, off + i); lua_rawseti(l, -2, ++k); }
    }
    return 1;
}
static int mm_find_u32(lua_State* l) { return mm_find(l, 0); }
static int mm_find_rel(lua_State* l) { return mm_find(l, 1); }
static int mm_hash(lua_State* l) {
    uint32_t off = ram_off(l, 1);
    lua_Integer n = luaL_checkinteger(l, 2);
    uint64_t h = 1469598103934665603ull;                           /* FNV-1a */
    for (lua_Integer i = 0; i < n && i < MAIN_RAM_SIZE; i++) { h ^= g_main_ram[(off + (uint32_t)i) & (MAIN_RAM_SIZE - 1)]; h *= 1099511628211ull; }
    char s[20]; snprintf(s, sizeof s, "%016llX", (unsigned long long)h);
    lua_pushstring(l, s);
    return 1;
}

/* memory.*: a domain; the ARM9 bus without side effects (registers are read from their store) */
static uint32_t bus_read(uint32_t a, int n, const char* dom) {
    uint32_t v = 0;
    for (int i = 0; i < n; i++) {
        uint32_t x = a + (uint32_t)i, b = 0;
        if (dom && !strcmp(dom, "ROM")) b = g_rom && x < g_rom_size ? g_rom[x] : 0;
        else if (!dom || !strcmp(dom, "Main RAM")) b = g_main_ram[x & (MAIN_RAM_SIZE - 1)];
        else if ((x >> 24) == 0x04) b = (x & 0xFFFFFF) < sizeof g_io ? g_io[x & 0xFFFFFF] : 0;
        else if ((x >> 24) == 0x02 || (x >> 24) == 0x03 || (x >> 24) == 0x05 || (x >> 24) == 0x06 || (x >> 24) == 0x07) b = mem_read8(x);
        v |= b << (8 * i);
    }
    return v;
}
static const char* dom_arg(lua_State* l, int idx) { return lua_isstring(l, idx) ? lua_tostring(l, idx) : NULL; }
static int m_u8(lua_State* l)  { lua_pushinteger(l, bus_read((uint32_t)luaL_checkinteger(l, 1), 1, dom_arg(l, 2))); return 1; }
static int m_u16(lua_State* l) { lua_pushinteger(l, bus_read((uint32_t)luaL_checkinteger(l, 1), 2, dom_arg(l, 2))); return 1; }
static int m_u32(lua_State* l) { lua_pushinteger(l, bus_read((uint32_t)luaL_checkinteger(l, 1), 4, dom_arg(l, 2))); return 1; }
static int m_s32(lua_State* l) { lua_pushinteger(l, (int32_t)bus_read((uint32_t)luaL_checkinteger(l, 1), 4, dom_arg(l, 2))); return 1; }

/* ---------------------------------------------------------------- joypad */
static const struct { const char* name; int bit; } BUTTONS[] = {
    { "A", 0 }, { "B", 1 }, { "Select", 2 }, { "Start", 3 }, { "Right", 4 }, { "Left", 5 },
    { "Up", 6 }, { "Down", 7 }, { "R", 8 }, { "L", 9 }, { "X", 10 }, { "Y", 11 },
};
#define N_BUTTONS ((int)(sizeof BUTTONS / sizeof BUTTONS[0]))
static int button_bit(const char* s) {
    if (!strncmp(s, "P1 ", 3)) s += 3;
    for (int i = 0; i < N_BUTTONS; i++) if (!strcmp(BUTTONS[i].name, s)) return BUTTONS[i].bit;
    return -1;
}
static int jp_get(lua_State* l) {
    lua_createtable(l, 0, N_BUTTONS);
    for (int i = 0; i < N_BUTTONS; i++) {
        lua_pushboolean(l, (g_keys_down >> BUTTONS[i].bit) & 1);
        lua_setfield(l, -2, BUTTONS[i].name);
    }
    return 1;
}
static int jp_set(lua_State* l) {
    luaL_checktype(l, 1, LUA_TTABLE);
    lua_pushnil(l);
    while (lua_next(l, 1)) {
        if (lua_type(l, -2) == LUA_TSTRING) {
            int b = button_bit(lua_tostring(l, -2));
            if (b >= 0 && !lua_isnil(l, -1)) {
                if (lua_toboolean(l, -1)) { g_access_keys_on |= (uint16_t)(1u << b); g_access_keys_off &= (uint16_t)~(1u << b); }
                else { g_access_keys_off |= (uint16_t)(1u << b); g_access_keys_on &= (uint16_t)~(1u << b); }
            }
        }
        lua_pop(l, 1);
    }
    return 0;
}

/* ---------------------------------------------------------------- input */
static int in_get(lua_State* l) {
    const char* names[128];
    int n = frontend_access_input(names, 128);
    lua_createtable(l, 0, n);
    for (int i = 0; i < n; i++) { lua_pushboolean(l, 1); lua_setfield(l, -2, names[i]); }
    return 1;
}

/* ---------------------------------------------------------------- speech, console, events */
static int sp_say(lua_State* l) {
    const char* s = luaL_optstring(l, 1, "");
    int interrupt = lua_isnoneornil(l, 2) ? 1 : lua_toboolean(l, 2);
    speech_say(s, interrupt);
    return 0;
}
static int sp_stop(lua_State* l) { (void)l; speech_stop(); return 0; }
static int sp_engine(lua_State* l) { lua_pushstring(l, speech_engine()); return 1; }
static int con_log(lua_State* l) {
    int n = lua_gettop(l);
    luaL_Buffer b; luaL_buffinit(l, &b);
    for (int i = 1; i <= n; i++) { if (i > 1) luaL_addchar(&b, ' '); luaL_tolstring(l, i, NULL); luaL_addvalue(&b); }
    luaL_pushresult(&b);
    static int all = -1; if (all < 0) all = getenv("DQIX_ACCESS_LOG") != NULL;
    const char* m = lua_tostring(l, -1);
    if (all || strstr(m, "error")) fprintf(stderr, "access: %s\n", m);   /* (the script logs everything it says) */
    return 0;
}
static int ev_onexit(lua_State* l) {
    luaL_checktype(l, 1, LUA_TFUNCTION);
    lua_pushvalue(l, 1);
    if (g_exit_ref != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, g_exit_ref);
    lua_xmove(l, L, 1);
    g_exit_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pushstring(l, "onexit");
    return 1;
}
static int emu_advance(lua_State* l) { return lua_yield(l, 0); }
static int emu_framecount(lua_State* l) { lua_pushinteger(l, (lua_Integer)g_frame); return 1; }
static int gi_romname(lua_State* l) { lua_pushstring(l, "Dragon Quest IX - Sentinels of the Starry Skies (USA)"); return 1; }
static int gi_hash(lua_State* l) { lua_pushstring(l, ""); return 1; }
static int nothing(lua_State* l) { (void)l; return 0; }

static void reg(const char* name, const luaL_Reg* fns) {
    lua_newtable(L);
    luaL_setfuncs(L, fns, 0);
    lua_setglobal(L, name);
}

/* Where the mod is: its own folder, "DQ9 access" in the player's Documents, or
 * (as before) the access folder in the game's folder. DQIX_ACCESS can name the
 * script instead ("0": no mod). The script's other files (the maps, the saved
 * places, the logs) are in the same folder as it: ACCESS_DIR for the script. */
static char g_dir[600] = "access/";
const char* access_dir(void) { return g_dir; }
static int file_there(const char* p) { FILE* f = fopen(p, "rb"); if (!f) return 0; fclose(f); return 1; }
static int documents_folder(char* out, size_t n) {
#ifdef _WIN32
    wchar_t w[MAX_PATH];
    if (SHGetFolderPathW(NULL, CSIDL_PERSONAL, NULL, 0, w) != S_OK) return 0;
    return WideCharToMultiByte(CP_ACP, 0, w, -1, out, (int)n, NULL, NULL) > 0;
#else
    const char* h = getenv("HOME");
    if (!h) return 0;
    snprintf(out, n, "%s/Documents", h);
    return 1;
#endif
}
static const char* script_path(void) {
    static char p[600];
    const char* e = getenv("DQIX_ACCESS");
    if (e && *e) {
        if (!strcmp(e, "0")) return NULL;
        snprintf(p, sizeof p, "%s", e);
    } else {
        char docs[400];
        p[0] = 0;
        if (documents_folder(docs, sizeof docs)) {
            snprintf(p, sizeof p, "%s/DQ9 access/dq9-access.lua", docs);
            if (!file_there(p)) p[0] = 0;
        }
        if (!p[0]) snprintf(p, sizeof p, "access/dq9-access.lua");
    }
    snprintf(g_dir, sizeof g_dir, "%s", p);
    char* cut = NULL;
    for (char* c = g_dir; *c; c++) if (*c == '/' || *c == '\\') cut = c;
    if (cut) cut[1] = 0; else g_dir[0] = 0;
    return p;
}

/* The script is loaded again whenever its file changes (a new version of the mod
 * takes over at once, without closing the game; the script reads its saved places
 * again as it starts). */
static char g_path[600];
static long long g_mtime = -1, g_msize = -1;
static void file_stamp(long long* mt, long long* sz) {
    struct stat st;
    if (stat(g_path, &st) == 0) { *mt = (long long)st.st_mtime; *sz = (long long)st.st_size; }
    else { *mt = -1; *sz = -1; }
}

static void load_script(void) {
    if (L) { lua_close(L); L = NULL; g_co = NULL; g_co_ref = g_exit_ref = LUA_NOREF; }
    g_done = 1;
    g_access_keys_on = g_access_keys_off = 0;
    file_stamp(&g_mtime, &g_msize);
    L = luaL_newstate();
    if (!L) return;
    luaL_openlibs(L);
    static const luaL_Reg mm[] = {
        { "read_u8", mm_u8 }, { "read_s8", mm_s8 }, { "read_u16_le", mm_u16 }, { "read_s16_le", mm_s16 },
        { "read_u32_le", mm_u32 }, { "read_s32_le", mm_s32 }, { "read_bytes_as_array", mm_bytes }, { "hash_region", mm_hash },
        { "read_string", mm_string }, { "find_u32", mm_find_u32 }, { "find_rel", mm_find_rel },
        { NULL, NULL } };
    static const luaL_Reg mem[] = {
        { "read_u8", m_u8 }, { "read_u16_le", m_u16 }, { "read_u32_le", m_u32 }, { "read_s32_le", m_s32 }, { NULL, NULL } };
    static const luaL_Reg jp[] = { { "get", jp_get }, { "set", jp_set }, { NULL, NULL } };
    static const luaL_Reg in[] = { { "get", in_get }, { NULL, NULL } };
    static const luaL_Reg sp[] = { { "say", sp_say }, { "stop", sp_stop }, { "engine", sp_engine }, { NULL, NULL } };
    static const luaL_Reg con[] = { { "log", con_log }, { "writeline", con_log }, { "clear", nothing }, { NULL, NULL } };
    static const luaL_Reg ev[] = { { "onexit", ev_onexit }, { NULL, NULL } };
    static const luaL_Reg emu[] = { { "frameadvance", emu_advance }, { "framecount", emu_framecount }, { "yield", emu_advance }, { NULL, NULL } };
    static const luaL_Reg gi[] = { { "getromname", gi_romname }, { "getromhash", gi_hash }, { NULL, NULL } };
    reg("mainmemory", mm); reg("memory", mem); reg("joypad", jp); reg("input", in); reg("speech", sp);
    reg("console", con); reg("event", ev); reg("emu", emu); reg("gameinfo", gi);
    lua_pushboolean(L, 1); lua_setglobal(L, "DQIX_PC");                /* the script can tell it is the PC version */
    lua_pushstring(L, g_dir); lua_setglobal(L, "ACCESS_DIR");          /* the mod's folder, for its other files */
    g_co = lua_newthread(L);
    g_co_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    if (luaL_loadfilex(g_co, g_path, "t") != LUA_OK) {
        fprintf(stderr, "access: %s\n", lua_tostring(g_co, -1));
        speech_say("The access mod could not start: the script has an error.", 1);
        return;
    }
    g_done = 0;
    fprintf(stderr, "access: %s loaded (speech: %s)\n", g_path, speech_engine());
}


/* ---------------------------------------------------------------- auto update
 * When the game starts, the mod's files are brought up to date from its GitHub
 * repository (in the background; the game does not wait). mod/manifest.txt
 * there says the mod's version, the version of these changes to the game
 * ("patch") and the files with their sizes; when its version is newer than the
 * one in version.txt in the mod's folder, every file is downloaded again (to a
 * .tmp file first, put in place only when it is whole). The new script is then
 * loaded as usual (its file changed). An update that also changes the game
 * (a newer "patch") is said: the installer has to build the game again.
 * No update: a file called no-auto-update.txt in the mod's folder. */
#define ACCESS_PATCH 2
#define UPDATE_HOST L"raw.githubusercontent.com"
#define UPDATE_REPO "RetroSanity/Dragon-quest-9-access/main"
static volatile int g_upd_done;                 /* 1: the thread has finished (g_upd_msg: what to say) */
static char g_upd_msg[400];
#ifdef _WIN32
#include <winhttp.h>
static long long version_num(const char* v) {
    long long k = 0; int parts = 0;
    while (*v && parts < 4) {
        while (*v && (*v < '0' || *v > '9')) v++;
        long long x = 0;
        while (*v >= '0' && *v <= '9') x = x * 10 + (*v++ - '0');
        k = k * 10000 + x; parts++;
    }
    while (parts++ < 4) k *= 10000;
    return k;
}
static int http_get(const char* path, char** out, size_t* len, size_t max) {
    wchar_t wpath[600];
    if (!MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 600)) return 0;
    int ok = 0;
    HINTERNET s = WinHttpOpen(L"dq9-access-updater", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0), c = NULL, r = NULL;
    if (!s) return 0;
    WinHttpSetTimeouts(s, 8000, 8000, 15000, 60000);
    c = WinHttpConnect(s, UPDATE_HOST, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (c) r = WinHttpOpenRequest(c, L"GET", wpath, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (r && WinHttpSendRequest(r, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) && WinHttpReceiveResponse(r, NULL)) {
        DWORD code = 0, sz = sizeof code;
        WinHttpQueryHeaders(r, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &sz, WINHTTP_NO_HEADER_INDEX);
        if (code == 200) {
            size_t n = 0, cap = 1 << 16;
            char* b = malloc(cap + 1);
            ok = b != NULL;
            for (;;) {
                DWORD avail = 0, got = 0;
                if (!ok || !WinHttpQueryDataAvailable(r, &avail)) { ok = 0; break; }
                if (!avail) break;
                if (n + avail > max) { ok = 0; break; }
                if (n + avail > cap) { while (n + avail > cap) cap *= 2; char* nb = realloc(b, cap + 1); if (!nb) { ok = 0; break; } b = nb; }
                if (!WinHttpReadData(r, b + n, avail, &got)) { ok = 0; break; }
                n += got;
            }
            if (ok) { b[n] = 0; *out = b; *len = n; } else free(b);
        }
    }
    if (r) WinHttpCloseHandle(r);
    if (c) WinHttpCloseHandle(c);
    WinHttpCloseHandle(s);
    return ok;
}
static char* next_line(char** p) {               /* the next line of a text, cut off in place */
    char* s = *p;
    while (*s == '\r' || *s == '\n') s++;
    if (!*s) return NULL;
    char* e = s;
    while (*e && *e != '\r' && *e != '\n') e++;
    if (*e) *e++ = 0;
    *p = e;
    return s;
}
static int safe_name(const char* f) {
    if (!*f || strstr(f, "..") || strchr(f, ':') || f[0] == '/' || f[0] == '\\') return 0;
    for (const char* c = f; *c; c++) if (!((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') || (*c >= '0' && *c <= '9') || strchr("-_. /", *c))) return 0;
    return 1;
}
static DWORD WINAPI update_thread(LPVOID u) {
    (void)u;
    char path[700], *man = NULL; size_t mlen = 0;
    snprintf(path, sizeof path, "/" UPDATE_REPO "/mod/manifest.txt");
    if (!http_get(path, &man, &mlen, 1 << 20)) { g_upd_done = 1; return 0; }   /* offline: nothing to do */
    char have[64] = "0";
    snprintf(path, sizeof path, "%sversion.txt", g_dir);
    FILE* f = fopen(path, "r");
    if (f) { if (!fgets(have, sizeof have, f)) have[0] = 0; fclose(f); }
    char ver[64] = ""; int patch = 0;
    for (char *q = man, *line; (line = next_line(&q)); ) {
        if (!strncmp(line, "version ", 8)) snprintf(ver, sizeof ver, "%s", line + 8);
        else if (!strncmp(line, "patch ", 6)) patch = atoi(line + 6);
    }
    if (!ver[0] || version_num(ver) <= version_num(have)) { free(man); g_upd_done = 1; return 0; }
    /* the list of files: the manifest's lines were cut up; read them again from the start */
    for (size_t i = 0; i < mlen; i++) if (!man[i]) man[i] = '\n';
    int got = 0, failed = 0;
    for (char *q = man, *line; (line = next_line(&q)); ) {
        char name[300]; long long size = -1;
        if (strncmp(line, "file ", 5) || sscanf(line + 5, "%lld %299[^\n]", &size, name) != 2 || !safe_name(name)) continue;
        char url[700], dst[900], tmp[920], *data = NULL; size_t n = 0;
        char enc[600]; size_t k = 0;
        for (const char* c = name; *c && k < sizeof enc - 4; c++) { if (*c == ' ') { memcpy(enc + k, "%20", 3); k += 3; } else enc[k++] = *c; }
        enc[k] = 0;
        snprintf(url, sizeof url, "/" UPDATE_REPO "/mod/%s", enc);
        if (!http_get(url, &data, &n, 64 << 20) || (long long)n != size) { free(data); failed++; continue; }
        snprintf(dst, sizeof dst, "%s%s", g_dir, name);
        for (char* c = dst + strlen(g_dir); *c; c++) if (*c == '/') { *c = 0; CreateDirectoryA(dst, NULL); *c = '\\'; }
        /* the same as the copy here already: nothing to do (and a file in use is not touched) */
        FILE* cur = fopen(dst, "rb");
        if (cur) {
            int same = 1; size_t i = 0; int ch;
            while ((ch = fgetc(cur)) != EOF) { if (i >= n || (unsigned char)data[i] != ch) { same = 0; break; } i++; }
            fclose(cur);
            if (same && i == n) { free(data); continue; }
        }
        snprintf(tmp, sizeof tmp, "%s.tmp", dst);
        FILE* o = fopen(tmp, "wb");
        int ok = o && fwrite(data, 1, n, o) == n;
        if (o) fclose(o);
        free(data);
        if (ok && !MoveFileExA(tmp, dst, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
            /* in use (a library the game has loaded): move it aside, the new one takes its place next time */
            char old[940];
            snprintf(old, sizeof old, "%s.old", dst);
            ok = MoveFileExA(dst, old, MOVEFILE_REPLACE_EXISTING) && MoveFileExA(tmp, dst, MOVEFILE_REPLACE_EXISTING);
        }
        if (ok) got++;
        else { DeleteFileA(tmp); failed++; }
    }
    free(man);
    if (failed) { g_upd_done = 1; return 0; }                       /* try again next time */
    snprintf(path, sizeof path, "%sversion.txt", g_dir);
    f = fopen(path, "w");
    if (f) { fprintf(f, "%s\n", ver); fclose(f); }
    if (patch > ACCESS_PATCH)
        snprintf(g_upd_msg, sizeof g_upd_msg, "The access mod has been updated to version %s. This version also changes the game: "
                 "close the game, then run Install DQ9 Access in the DQ9 access folder in your Documents.", ver);
    else snprintf(g_upd_msg, sizeof g_upd_msg, "The access mod has been updated to version %s.", ver);
    g_upd_done = 1;
    (void)got;
    return 0;
}
static void update_start(void) {
    char p[700];
    snprintf(p, sizeof p, "%sno-auto-update.txt", g_dir);
    if (file_there(p)) return;
    HANDLE t = CreateThread(NULL, 0, update_thread, NULL, 0, NULL);
    if (t) CloseHandle(t);
}
#else
static void update_start(void) {}
#endif
static void update_poll(void) {
    static int said, wait;
    if (said || !g_upd_done) return;
    if (!g_upd_msg[0]) { said = 1; return; }
    if (++wait < 240) return;                                       /* after the new script has started and said so */
    said = 1;
    speech_say(g_upd_msg, 0);
    fprintf(stderr, "access: %s\n", g_upd_msg);
}

void access_init(void) {
    const char* path = script_path();
    if (!path) return;
    FILE* f = fopen(path, "rb");
    if (!f) return;                                                   /* no Access mod here: the game as usual */
    fclose(f);
    snprintf(g_path, sizeof g_path, "%s", path);
    speech_init();
    g_access_on = 1;
    load_script();
    update_start();
}

void access_frame(void) {
    if (!g_access_on) return;
    update_poll();
    if (g_frame % 30 == 0) {                                          /* a new version of the script: load it */
        static long long seen_mt = -2, seen_sz = -2;
        long long mt, sz;
        file_stamp(&mt, &sz);
        if (mt >= 0 && (mt != g_mtime || sz != g_msize)) {
            if (mt == seen_mt && sz == seen_sz) { load_script(); seen_mt = seen_sz = -2; }   /* unchanged for half a second: written */
            else { seen_mt = mt; seen_sz = sz; }
        }
    }
    if (g_done || !g_co) return;
    int nres = 0;
    int st = lua_resume(g_co, L, 0, &nres);
    if (st == LUA_YIELD) { lua_pop(g_co, nres); return; }
    g_done = 1;
    if (st != LUA_OK) {
        fprintf(stderr, "access: script stopped: %s\n", lua_tostring(g_co, -1));
        speech_say("The access mod stopped because of an error. Details are in last-run.log.", 1);
    }
}

void access_shutdown(void) {
    if (!L) return;
    if (g_exit_ref != LUA_NOREF) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, g_exit_ref);
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) lua_pop(L, 1);
    }
    speech_shutdown();
}
