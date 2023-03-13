void Main() {
    SetupIntercepts();
    startnew(WatchForReset);
}

void Notify(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
    trace("Notified: " + msg);
}

void NotifyError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .3, .1, .3), 15000);
}

void NotifyWarning(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Warning", msg, vec4(.9, .6, .2, .3), 15000);
}

const string PluginIcon = Icons::SnapchatGhost;
const string MenuTitle = "\\$26d" + PluginIcon + "\\$z " + Meta::ExecutingPlugin().Name;

// show the window immediately upon installation
[Setting hidden]
bool ShowWindow = true;

/** Render function called every frame intended only for menu items in `UI`. */
void RenderMenu() {
    if (UI::MenuItem(MenuTitle, "", ShowWindow)) {
        ShowWindow = !ShowWindow;
    }
}

[Setting hidden]
bool ShowAllCpSplits = false;

const MLFeed::GhostInfo@ relativeTo = null;
void WatchForReset() {
    auto gd = MLFeed::GetGhostData();
    auto lastNbGhosts = gd.NbGhosts;
    while (true) {
        yield();
        if (lastNbGhosts != gd.NbGhosts && gd.NbGhosts == 0) {
            @relativeTo = null;
        }
        lastNbGhosts = gd.NbGhosts;
    }
}

void RenderInterface() {
    if (!ShowWindow) return;
    // UI Seq is end round when ghosts are being spectated.
    if (!IsUiSeqEndRound) return;
    auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    if (pgScript is null) return;
    auto map = GetApp().RootMap;
    if (map is null) return;

    auto gd = MLFeed::GetGhostData();
    if (UI::Begin(MenuTitle, ShowWindow, UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoCollapse)) {
        // UI::AlignTextToFramePadding();
        UI::Text(ColoredString(map.MapName) + "\\$z by " + map.AuthorNickName);
        UI::Text("Nb. Ghosts: " + gd.NbGhosts);
        if (gd.NbGhosts == 0 || gd.Ghosts[0].Checkpoints.Length == 0) {
            UI::Text("Load some ghosts to view times.\n(Toggle the ghost if it doesn't show up.)");
            UI::Text("\\$888Alternatively: this might show if the first ghost has 0 checkpoint times.");
        } else {
            auto best = gd.Ghosts[0];
            array<const MLFeed::GhostInfo@> sorted = {best};
            // uint lastCpIx = best.Checkpoints.Length - 1;
            for (uint i = 1; i < gd.Ghosts.Length; i++) {
                auto g = gd.Ghosts[i];
                if (g.Result_Time < best.Result_Time) {
                    @best = g;
                }
                bool inserted = false;
                for (uint j = 0; j < sorted.Length; j++) {
                    auto item = sorted[j];
                    if (g.Result_Time < item.Result_Time) {
                        sorted.InsertAt(j, g);
                        inserted = true;
                        break;
                    } else if (AreGhostDupliates(g, item)) {
                        inserted = true;
                        break;
                    }
                }
                // if we haven't yet inserted a ghost to sorted
                if (!inserted) {
                    sorted.InsertLast(g);
                }
            }

            if (relativeTo is null) @relativeTo = best;

            UI::SameLine();
            UI::Text("/   Best: " + best.Nickname + " (" + Time::Format(best.Result_Time) + ")");
            ShowAllCpSplits = UI::Checkbox("Show All CP Splits", ShowAllCpSplits);
            uint nbCols = 1 + (ShowAllCpSplits ? best.Checkpoints.Length : 1);

            int currTime = int(pgScript.Now) - g_LastSetStartTime;

            uint currCp = 0;
            for (uint i = 0; i < relativeTo.Checkpoints.Length; i++) {
                int t = relativeTo.Checkpoints[i];
                if (t <= currTime) currCp = i;
                else break;
            }
            UI::Text("Current Race Time: " + Time::Format(currTime));
            UI::SameLine();
            UI::Text("/   CP: " + (currCp + 1));

            UI::Separator();

            if (UI::BeginTable("ghost cp times table", nbCols, UI::TableFlags::SizingStretchProp)) {

                for (uint i = 0; i < sorted.Length; i++) {
                    auto g = sorted[i];
                    UI::PushID("ghost-"+i);

                    UI::TableNextRow();
                    UI::TableNextColumn();
                    if (UI::Button(Icons::Crosshairs)) {
                        @relativeTo = g;
                    }
                    UI::SameLine();
                    bool isFocusGhost = relativeTo == g;
                    UI::AlignTextToFramePadding();
                    UI::Text((isFocusGhost ? "\\$4f4" : "") + g.Nickname);

                    for (uint cp = 0; cp < g.Checkpoints.Length; cp++) {
                        if (ShowAllCpSplits || cp == currCp) {
                            UI::TableNextColumn();
                            auto bestT = relativeTo.Checkpoints[cp];
                            auto t = g.Checkpoints[cp];
                            UI::Text(isFocusGhost ? ((ShowAllCpSplits && cp == currCp ? "\\$4f4" : "") + Time::Format(bestT)) : TimeDelta(bestT, t, true));
                        }
                    }
                    UI::PopID();
                }

                UI::EndTable();
            }

        }
    }
    UI::End();
}

// formats (secTime - baseTime) with appropriate +/-
const string TimeDelta(int baseTime, int secTime, bool withColor = false) {
    auto sign = secTime < baseTime ? "-" : "+";
    auto color = !withColor ? "" : secTime < baseTime ? "\\$48f" : "\\$f84";
    return color + sign + Time::Format(Math::Abs(secTime - baseTime));
}


bool AreGhostDupliates(const MLFeed::GhostInfo@ g, const MLFeed::GhostInfo@ other) {
    if (g is null || other is null) return false;
    bool isEqNoCps = true
        && g.Nickname == other.Nickname
        && g.Result_Score == other.Result_Score
        && g.Result_Time == other.Result_Time
        && g.Checkpoints.Length == other.Checkpoints.Length
        ;
    if (isEqNoCps) {
        for (uint i = 0; i < g.Checkpoints.Length; i++) {
            if (g.Checkpoints[i] != other.Checkpoints[i])
                return false;
        }
    }
    return isEqNoCps;
}


bool IsUiSeqEndRound {
    get {
        try {
            auto gameTerm = cast<CSmArenaClient>(GetApp().CurrentPlayground).GameTerminals[0];
            return gameTerm.UISequence_Current == SGamePlaygroundUIConfig::EUISequence::EndRound;
        } catch {
            return false;
        }
    }
}
