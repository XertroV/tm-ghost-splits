void SetupIntercepts() {
    Dev::InterceptProc("CSmArenaRulesMode", "Ghosts_SetStartTime", _Ghosts_SetStartTime);
    // Dev::InterceptProc("CGamePlaygroundUIConfig", "Spectator_SetForcedTarget_Ghost", _Spectator_SetForcedTarget_Ghost);
}

int g_LastSetStartTime = -1;
int g_LastSetStartTimeNow = -1;

bool _Ghosts_SetStartTime(CMwStack&in stack, CMwNod@ nod) {
    g_LastSetStartTime = stack.CurrentInt(0);
    g_LastSetStartTimeNow = Time::Now;
    return true;
}

// ! the forced target Id is not the ghost Id. it's like an instance Id instead.

// uint g_Ghost_ForcedTarget = uint(-1);

// bool _Spectator_SetForcedTarget_Ghost(CMwStack&in stack, CMwNod@ nod) {
//     g_Ghost_ForcedTarget = stack.CurrentId(0).Value;
//     auto ghostId = stack.CurrentId(0);
//     print("Set forced target: " + ghostId.Value);
//     print("Set forced target: " + ghostId.GetName());
//     return true;
// }
