void SetupIntercepts() {
    Dev::InterceptProc("CSmArenaRulesMode", "Ghosts_SetStartTime", _Ghosts_SetStartTime);
}

int g_LastSetStartTime = -1;
int g_LastSetStartTimeNow = -1;

bool _Ghosts_SetStartTime(CMwStack&in stack, CMwNod@ nod) {
    g_LastSetStartTime = stack.CurrentInt(0);
    g_LastSetStartTimeNow = Time::Now;
    return true;
}
