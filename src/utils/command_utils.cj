package cli.utils
import std.collection.*
import std.sort.*
import magic.log.LogUtils

protected const CARRIAGE_RETURN = r'\r'
protected const ENTER = r'\n'
protected const DELETE = r'\u{7F}'
protected const BACK = r'\b'
protected const TAB = r'\t'
protected const ARROW_UP = r'\u{2191}'
protected const ARROW_DOWN = r'\u{2193}'
protected const ARROW_LEFT = r'\u{2190}'
protected const ARROW_RIGHT = r'\u{2192}'
protected let CONTROL_RUNES = [CARRIAGE_RETURN, ENTER, DELETE, BACK, TAB, ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT]

// INNER COMMANDS
protected let AT = CommandOption(r'@', ANY, true)
protected let SLASH = CommandOption(r'/', PREFIX, false)
protected let MODE = CommandOption(r'!', SINGLE, true)
protected let MODE_CN = CommandOption(r'！', SINGLE, true)
protected let INNER_COMMANDS = [AT, SLASH, MODE, MODE_CN]

protected enum CommandMode {
    | SINGLE // only single char at begging
    | PREFIX // only prefix at begging
    | ANY // any where without number limitation
}
protected class CommandOption {
    public CommandOption(let trigger: Rune, let mode: CommandMode, let visual: Bool) {
    }
}

protected class Command {
    public Command(let cmd: String, let option: CommandOption) {
    }
    prop pure: String {
        get() {
            if (option.visual) {
                this.cmd.replace(option.trigger.toString(), "")
            } else {
                this.cmd
            }
        }
    }
    prop full: String {
        get() {
            this.cmd
        }
    }

    public func toFull(str: String) {
        if (str.startsWith(option.trigger.toString())) {
            return str
        } else {
            return option.trigger.toString() + str
        }
    }
}

/**
 * combine buf and rune and get lat command starts with Trigger
 */
private func detectTrigger(buf: Collection<Rune>, rune: Rune, option: CommandOption): Bool {
    if (rune == r' ') {
        return false
    }

    match (option.mode) {
        case PREFIX => return (buf.toArray().get(0) ?? rune) == option.trigger
        case SINGLE => return buf.size == 0 && rune == option.trigger
        case _ => // MODE == ANY
            if (rune == option.trigger) {
                return true
            }
            let arr = buf.toArray()
            if (let Some(index) <- arr.lastIndexOf(option.trigger)) {
                return !String(arr[index..arr.size]).contains(' ')
            } else {
                return false
            }
    }
}

private func getCommand(buf: Collection<Rune>, rune: Rune, option: CommandOption): Option<Command> {

    if (!detectTrigger(buf, rune, option)) {
        return None
    }

    let arr: Array<Rune>
    if (CONTROL_RUNES.contains(rune) || rune == r'\0') {
        arr = buf.toArray()
    } else {
        let runeLst = ArrayList<Rune>(buf)
        runeLst.add(rune)
        arr = runeLst.toArray()
    }
    match (option.mode) {
        case SINGLE => return Command(option.trigger.toString(), option)
        case PREFIX => return Command(String(arr), option)
        case ANY => 
            if (let Some(index) <- arr.lastIndexOf(option.trigger)) {
                return Command(String(arr[index..arr.size]), option)
            } else {
                throw Exception("Logic Error: Command parse failed ${String(arr)}")
            }
        case _ => return None
    }

}

protected func detectCommand(buf: Collection<Rune>, rune: Option<Rune>): Option<Command> {
    for (option in INNER_COMMANDS) {
        if (let Some(cmd) <- getCommand(buf, rune ?? r'\0', option)) {
            return cmd
        }
    }
    return None
}

protected func listCmdsStr(command: Option<Command>): Array<String> {
    if (let Some(cmd) <- command) {
        let cmdArray: Array<String> = if (cmd.option.trigger == r'/') {
            // HELP_INFO: (command, description)
            PrintUtils.HELP_INFO.map { info => "/${info[0]}" } |> collectArray
        } else if (cmd.option.trigger == r'@') {
            listFiles(prefix: cmd.pure)
        } else { // !
            []
        }
        let prefix = cmd.pure
        return cmdArray |> filter {str => str.startsWith(prefix) && str != prefix} |> collectArray
    }
    return []   
}