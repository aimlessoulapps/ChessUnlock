package com.aimlessoul.chessunlock

// Run with python3 tool/test_foreground_state.py (uses the cached Kotlin compiler).
fun main() {
    val now = 2 * 24 * 60 * 60_000L
    val state = ForegroundAppState()
    check(state.queryStartMs(now) <= now - 60_000L) // Find a resume older than ten seconds.
    state.resumed("blocked.app")
    state.queryCompleted(now)
    check(state.packageName == "blocked.app")
    check(state.queryStartMs(now + 800) == now - 1000)
    check(state.packageName == "blocked.app") // No new events: still foreground.
    state.paused("unrelated.app")
    check(state.packageName == "blocked.app")
    state.paused("blocked.app")
    check(state.packageName == null)
    state.resumed("blocked.app")
    state.resumed("launcher")
    state.paused("blocked.app")
    check(state.packageName == "launcher") // A late pause must not erase the launcher.
    state.screenHidden()
    check(state.packageName == null)
    check(state.queryStartMs(now + 60 * 60_000L) == now - 1000) // Include sleep gap.
    state.resumed("old.app")
    check(state.queryStartMs(now - 60_000) == now - 60_000 - 24 * 60 * 60_000L)
    check(state.packageName == null) // Backward clock change rebuilds state.
    println("ForegroundAppState: 8 transition/recovery scenarios passed")
}
