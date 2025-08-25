package cli.utils

protected enum Direction {
    UP | DOWN | LEFT | RIGHT
}

protected enum ClearMode {
    BEHIND | LINE
}

protected func moveCursor(lines: Int64, direction: Direction) {
    match (direction) {
        case UP => print("\u{1B}[${lines}A", flush: true)
        case DOWN => print("\u{1B}[${lines}B", flush: true)
        case LEFT => print("\u{1B}[${lines}D", flush: true)
        case _ => print("\u{1B}[${lines}C", flush: true)
    }
}

protected func moveCursor(row!: ?Int64 = None, col!: ?Int64 = None) {
    if (let Some(rr) <- row) {
        print("\u{1B}[${rr}H", flush: true)
    }
    if (let Some(cc) <- col) {
        print("\u{1B}[${cc}G", flush: true)
    }
}

protected func clearRunes(mode: ClearMode) {
    match (mode) {
        case BEHIND => print("\u{1B}[J", flush: true)
        case _ => print("\r\u{1B}[K", flush: true)
    }
}

protected func restoreCursorPosition() {
    print("\u{1B}[u", flush: true)
}

protected func storeCursorPosition() {
    print("\u{1B}[s", flush: true)
}