#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#define VK_BACK 0x08
#define VK_TAB 0x09
#define VK_ENTER 0x0D
#define VK_ESCAPE 0x1B
#define VK_DELETE 0x2E
#define VK_UP 0x26
#define VK_DOWN 0x28
#define VK_LEFT 0x25
#define VK_RIGHT 0x27

// Static storage for original terminal settings
static HANDLE h_console = 0;
// Flag to track whether we are in raw mode
static int flag = 0;
static DWORD origin_mode = 0;
static UINT code_page_id = 65001;

const BYTE VK_UP_UTF8[]    = {0x1B, 0x5B, 0x41};  // ESC [ A
const BYTE VK_DOWN_UTF8[]  = {0x1B, 0x5B, 0x42};  // ESC [ B
const BYTE VK_LEFT_UTF8[]  = {0x1B, 0x5B, 0x44};  // ESC [ D
const BYTE VK_RIGHT_UTF8[] = {0x1B, 0x5B, 0x43};  // ESC [ C
const BYTE VK_ESCAPE_UTF8[]= {0x1B};              // ESC
const BYTE VK_BACK_UTF8[]  = {0x08};              // Backspace
const BYTE VK_DELETE_UTF8[]= {0x1B, 0x5B, 0x33, 0x7E};  // ESC [ 3 ~
const BYTE VK_TAB_UTF8[]   = {0x09};              // Tab
const BYTE VK_ENTER_UTF8[] = {0x0A};              // LF

typedef struct {
    WORD           vk_code; 
    const BYTE*    utf8_buf;
    size_t         buf_len;  
} VkToUtf8Map;

const VkToUtf8Map vk_utf8_map[] = {
    {VK_UP,    VK_UP_UTF8,    sizeof(VK_UP_UTF8)},
    {VK_DOWN,  VK_DOWN_UTF8,  sizeof(VK_DOWN_UTF8)},
    {VK_LEFT,  VK_LEFT_UTF8,  sizeof(VK_LEFT_UTF8)},
    {VK_RIGHT, VK_RIGHT_UTF8, sizeof(VK_RIGHT_UTF8)},
    {VK_BACK,  VK_BACK_UTF8,  sizeof(VK_BACK_UTF8)},
    {VK_TAB,   VK_TAB_UTF8,   sizeof(VK_TAB_UTF8)},
    {VK_ESCAPE,VK_ESCAPE_UTF8,sizeof(VK_ESCAPE_UTF8)},
    {VK_DELETE,VK_DELETE_UTF8,sizeof(VK_DELETE_UTF8)},
    {VK_ENTER, VK_ENTER_UTF8, sizeof(VK_ENTER_UTF8)},
};

static int vk_map_count = sizeof(vk_utf8_map)/sizeof(VkToUtf8Map);

/**
 * Enters raw input mode.
 * - Disables ICANON (line buffering)
 * - Disables ECHO (character echoing)
 * - Sets VMIN=1, VTIME=0 (return immediately after one byte)
 * - Uses cfmakeraw() for base raw settings, then disables ECHO explicitly
 *
 * @return TRUE on success, FALSE on error (e.g., tcgetattr fails)
 */
int enterRaw() {
    SetConsoleCP(code_page_id);
    SetConsoleOutputCP(code_page_id);
    h_console = GetStdHandle(STD_INPUT_HANDLE);
    if (h_console == INVALID_HANDLE_VALUE) {
        return FALSE;
    }
    
    // Only modify terminal if not already in raw mode
    if (!flag) {
        if (!GetConsoleMode(h_console, &origin_mode)) {
            return FALSE;
        }
        DWORD raw_mode = origin_mode;
        raw_mode &= ~ENABLE_ECHO_INPUT;
        raw_mode &= ~ENABLE_LINE_INPUT;
        raw_mode &= ~ENABLE_MOUSE_INPUT;
        raw_mode &= ~ENABLE_WINDOW_INPUT;
        if (!SetConsoleMode(h_console, raw_mode)) {
            return FALSE;
        }
        flag = 1;
    }
    return TRUE;
}

/**
 * Exits raw mode and restores the original terminal settings.
 * This function is idempotent — calling it multiple times has no side effect.
 */
void exitRaw() {
    if (flag) {
        SetConsoleMode(h_console, origin_mode);
        flag = 0;
    }
}


/*
 *Function: Reads console input characters, compatible with both ASCII and wide characters, and returns results via pointers.
 *Parameter Description:
 *charValuePtr: Stores the character value (uses the lower 8 bits for ASCII characters; stores the 16-bit value directly for wide characters).
 *isVirtualPtr: Indicates whether the input is a virtual key (TRUE = virtual key, FALSE = regular character).
 * return TRUE if success else FALSE
 */
BOOL getConsoleChar(unsigned short* charValuePtr, BOOL* isVirtualPtr) {
    if (charValuePtr == NULL || isVirtualPtr == NULL) {
        *charValuePtr = 0;
        *isVirtualPtr = FALSE;
        return FALSE;
    }
    INPUT_RECORD inputRecord;
    DWORD eventsRead;

    if (!ReadConsoleInputW(h_console, &inputRecord, 1, &eventsRead) || eventsRead != 1) {
        return FALSE;
    }

    if (inputRecord.EventType == KEY_EVENT && inputRecord.Event.KeyEvent.bKeyDown) {
        KEY_EVENT_RECORD keyEvent = inputRecord.Event.KeyEvent;
        
        if (keyEvent.wVirtualKeyCode != 0 && keyEvent.uChar.UnicodeChar == 0) {
            *isVirtualPtr = TRUE;
            *charValuePtr = keyEvent.wVirtualKeyCode;
        } else {
            *isVirtualPtr = FALSE;
            if (keyEvent.uChar.UnicodeChar != 0) {
                *charValuePtr = keyEvent.uChar.UnicodeChar;
            } else {
                *charValuePtr = keyEvent.uChar.AsciiChar; 
            }
        }
        return TRUE;
    }
    return TRUE;
}


BOOL is_high_surrogate(WORD wchar) {
    return (wchar >= 0xD800 && wchar <= 0xDBFF);
}

BOOL is_low_surrogate(WORD wchar) {
    return (wchar >= 0xDC00 && wchar <= 0xDFFF);
}

uint32_t merge_surrogate_pair(WORD high, WORD low) {
    return 0x10000U + ((uint32_t)(high - 0xD800) << 10) + (uint32_t)(low - 0xDC00);
}


/**
 * return 0: SINGLE WORD ONLY
 *        1: LOW SURROGATE NEEDED
 *        2：DOUBLE WORD READED
 *       -1: ILLEAGEL => SKIP
 */
int get_codepoint(WORD wchar, DWORD* out_codepoint, WORD* high_surrogate) {
    if (out_codepoint == NULL || high_surrogate == NULL) return -1;
    
    if (is_high_surrogate(wchar)) {
        *high_surrogate = wchar;
        return 1;
    }

    if (*high_surrogate != 0 && is_low_surrogate(wchar)) {
        WORD high = *high_surrogate;
        *high_surrogate = 0;
        *out_codepoint = merge_surrogate_pair(high, wchar);
        return 2;
    }

    // ILLEGAL
    if (is_low_surrogate(wchar)) {
        return -1;
    }

    // SINGLE SURROGATE
    *out_codepoint = (DWORD)wchar;
    return 0;
}


int codepoint_to_utf8(DWORD codepoint, BYTE* out_buf) {
    if (out_buf == NULL) return -1; 

    // ILLEAGAL CHECKPOIT：USING RELACE BYTES U+FFFD（UTF-8: 0xEF 0xBF 0xBD）
    if (codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF)) {
        out_buf[0] = 0xEF;
        out_buf[1] = 0xBF;
        out_buf[2] = 0xBD;
        return 3;
    }

    // U+0000 ~ U+007F & ASCII
    if (codepoint <= 0x7F) {
        out_buf[0] = (BYTE)codepoint;
        return 1;
    }
    // U+0080 ~ U+07FF
    else if (codepoint <= 0x7FF) {
        out_buf[0] = 0xC0 | (BYTE)(codepoint >> 6);          // 110xxxxx
        out_buf[1] = 0x80 | (BYTE)(codepoint & 0x3F);        // 10xxxxxx
        return 2;
    }
    // U+0800 ~ U+FFFF
    else if (codepoint <= 0xFFFF) {
        out_buf[0] = 0xE0 | (BYTE)(codepoint >> 12);         // 1110xxxx
        out_buf[1] = 0x80 | (BYTE)((codepoint >> 6) & 0x3F); // 10xxxxxx
        out_buf[2] = 0x80 | (BYTE)(codepoint & 0x3F);        // 10xxxxxx
        return 3;
    }
    // U+10000 ~ U+10FFFF
    else {
        out_buf[0] = 0xF0 | (BYTE)(codepoint >> 18);         // 11110xxx
        out_buf[1] = 0x80 | (BYTE)((codepoint >> 12) & 0x3F); // 10xxxxxx
        out_buf[2] = 0x80 | (BYTE)((codepoint >> 6) & 0x3F);  // 10xxxxxx
        out_buf[3] = 0x80 | (BYTE)(codepoint & 0x3F);         // 10xxxxxx
        return 4;
    }
}


int find_vk_utf8(WORD vk_code, BYTE* out_buf) {
    if (out_buf == NULL) return -1;

    for (size_t i = 0; i < vk_map_count; i++) {
        if (vk_utf8_map[i].vk_code == vk_code) {
            memcpy(out_buf, vk_utf8_map[i].utf8_buf, vk_utf8_map[i].buf_len);
            return vk_utf8_map[i].buf_len;
        }
    }
    return -1;
}

/**
 * get WCHAR (2BYTES)
 * @param out_bytes: 输出UTF-8字节的缓冲区（需提前分配至少4字节，建议8字节冗余）
 * @return: out_bytes size
 */
int rawGetBytes(BYTE* out_bytes) {
    // params check
    if (out_bytes == NULL) {
        return -1;
    }

    WORD high_surrogate = 0;
    while (1) {
        unsigned short wchar = 0;
        BOOL is_virtual = FALSE;
        if(!getConsoleChar(&wchar, &is_virtual)) {
            return -1;
        }

        if (wchar == 0) continue;

        if (is_virtual) {
            int size = find_vk_utf8(wchar, out_bytes);
            if (size > 0) {
                return size;
            }
        } else {
            DWORD codepoint;
            int res = get_codepoint(wchar, &codepoint, &high_surrogate);
            if (res == 2 || res == 0) {
                int size = codepoint_to_utf8(codepoint, out_bytes);
                if (size > 0) {
                    return size;
                }
            }
        }
    }
    return -1;
}


/**
 * Reads input and returns:
 * - Normal UTF-8 characters as-is
 * - Arrow keys mapped to Unicode arrow symbols (U+2190-U+2193) in UTF-8
 *
 * @param bytes Output buffer (at least 4 bytes)
 * @return Number of bytes written, TRUE on EOF, FALSE on error
 */
int getRawUtf8(BYTE *bytes) {
    if (bytes == NULL) {
        return -1;
    }
    int size = rawGetBytes(bytes);
    if (size < 0) {
        return -1;
    }

    BYTE c = bytes[0];
    
    // --- 0. Escape Sequence (Special Keys) ---
    if (c == 0x1b) {  // ESC
        if (size == 1) { //Just ESC
            return 1;
        }
        c = bytes[1];
        if (c != 0x5b) {
            return 1;  //Just ESC
        } 
        c = bytes[2];
        switch (c) {
            case 'A': // Up Arrow → U+2191 ↑
                bytes[0] = 0xE2;  // UTF-8 for U+2191
                bytes[1] = 0x86;
                bytes[2] = 0x91;
                return 3;

            case 'B': // Down Arrow → U+2193 ↓
                bytes[0] = 0xE2;
                bytes[1] = 0x86;
                bytes[2] = 0x93;
                return 3;

            case 'C': // Right Arrow → U+2192 →
                bytes[0] = 0xE2;
                bytes[1] = 0x86;
                bytes[2] = 0x92;
                return 3;

            case 'D': // Left Arrow → U+2190 ←
                bytes[0] = 0xE2;
                bytes[1] = 0x86;
                bytes[2] = 0x90;
                return 3;

            default:
                return -1; // Unknown CSI
        }
    }

    return size;
}