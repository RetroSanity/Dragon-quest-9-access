/* Speech for blind players (Access mod): the player's screen reader if one is
 * running (through Prism: NVDA, JAWS, Narrator, ZDSR, System Access and more;
 * without Prism: NVDA, JAWS), otherwise a Windows voice. UTF-8 text. */
#pragma once

void speech_init(void);
/* interrupt: cut off what is being said first; otherwise it waits its turn */
void speech_say(const char* utf8, int interrupt);
void speech_stop(void);
const char* speech_engine(void);    /* "NVDA", "JAWS", "SAPI", "<name> (Prism)" or "none" */
void speech_shutdown(void);
