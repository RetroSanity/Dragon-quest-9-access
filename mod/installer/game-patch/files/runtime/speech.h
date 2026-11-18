/* Speech for blind players (Access mod): the player's screen reader if one is
 * running (NVDA, JAWS), otherwise Windows' own voice (SAPI). UTF-8 text. */
#pragma once

void speech_init(void);
/* interrupt: cut off what is being said first; otherwise it waits its turn */
void speech_say(const char* utf8, int interrupt);
void speech_stop(void);
const char* speech_engine(void);    /* "NVDA", "JAWS", "SAPI" or "none" */
void speech_shutdown(void);
