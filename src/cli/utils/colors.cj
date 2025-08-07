package cli.cli.utils

// ANSI颜色代码定义
const RESET = "\u{1B}[0m"
const BOLD = "\u{1B}[1m"
const DIM = "\u{1B}[2m"
const ITALIC = "\u{1B}[3m"
const UNDERLINE = "\u{1B}[4m"
const STRIKETHROUGH = "\u{1B}[9m"

// 前景色
const BLACK = "\u{1B}[30m"
const RED = "\u{1B}[31m"
const GREEN = "\u{1B}[32m"
const YELLOW = "\u{1B}[33m"
const BLUE = "\u{1B}[34m"
const MAGENTA = "\u{1B}[35m"
const CYAN = "\u{1B}[36m"
const WHITE = "\u{1B}[37m"

// 亮色前景色
const BRIGHT_BLACK = "\u{1B}[90m"
const BRIGHT_RED = "\u{1B}[91m"
const BRIGHT_GREEN = "\u{1B}[92m"
const BRIGHT_YELLOW = "\u{1B}[93m"
const BRIGHT_BLUE = "\u{1B}[94m"
const BRIGHT_MAGENTA = "\u{1B}[95m"
const BRIGHT_CYAN = "\u{1B}[96m"
const BRIGHT_WHITE = "\u{1B}[97m"

// 背景色
const BG_BLACK = "\u{1B}[40m"
const BG_RED = "\u{1B}[41m"
const BG_GREEN = "\u{1B}[42m"
const BG_YELLOW = "\u{1B}[43m"
const BG_BLUE = "\u{1B}[44m"
const BG_MAGENTA = "\u{1B}[45m"
const BG_CYAN = "\u{1B}[46m"
const BG_WHITE = "\u{1B}[47m"

// 特殊主题颜色
const THEME_PRIMARY = BRIGHT_CYAN
const THEME_SECONDARY = BRIGHT_BLUE
const THEME_SUCCESS = BRIGHT_GREEN
const THEME_WARNING = BRIGHT_YELLOW
const THEME_ERROR = BRIGHT_RED
const THEME_INFO = BRIGHT_WHITE
const THEME_MUTED = BRIGHT_BLACK
const THEME_YELLOW = BRIGHT_YELLOW
