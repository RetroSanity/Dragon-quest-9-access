/* Access mod: a screen reader for blind players. Runs access/dq9-access.lua
 * (the DQ9 Access script, made for BizHawk) with the parts of BizHawk's Lua
 * API it uses: memory reads, the DS buttons, the keyboard and controller, and
 * speech (speech.h). The script reads the game's memory and talks; it can
 * press the D-pad (auto walk). */
#pragma once
#include <stdint.h>

extern int g_access_on;                 /* the script is running */
void access_init(void);                 /* once, before the first frame (no script: stays off) */
void access_frame(void);                /* once per frame, after the frontend's input, before input_update */
void access_shutdown(void);
void access_say(const char* text, int interrupt);   /* the program's own messages (notices) */
const char* access_dir(void);           /* the mod's folder ("access/", or Documents\\DQ9 access\\) */

/* the D-pad and buttons the script holds or lets go of for the next frame
 * (DS key bits, input.c applies them) */
extern uint16_t g_access_keys_on, g_access_keys_off;

/* frontend: the keys and controller buttons held now, by BizHawk's names
 * ("A", "PageDown", "LeftCtrl", "X1 LeftTrigger", "X1 DpadUp"...); returns how many */
int frontend_access_input(const char** names, int max);
