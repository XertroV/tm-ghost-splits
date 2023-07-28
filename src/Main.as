void Main() {
    SetupIntercepts();
    startnew(WatchForReset);
}

// void Update(float dt) {
//     CheckPaused();
// }

//! pause doesn't work with ghost scrubber (but does work without it)
// bool IsPaused = false;
// int PauseAt = -1;
// void TogglePause() {
//     if (IsPaused) IsPaused = false;
//     else {
//         try {
//             IsPaused = true;
//             auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
//             PauseAt = pgScript.Now - g_LastSetStartTime;
//         } catch {
//             IsPaused = false;
//         }
//     }
// }
// void CheckPaused() {
//     if (!IsPaused) return;
//     try {
//         auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
//         pgScript.Ghosts_SetStartTime(pgScript.Now - PauseAt - 10);
//         print("set start time: " + g_LastSetStartTime);
//     } catch {
//         IsPaused = false;
//     }
// }

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

[Setting hidden]
bool ShowSplitDeltasInstead = false;

[Setting hidden]
bool S_LoadedGhostsOnly = true;

const MLFeed::GhostInfo_V2@ relativeTo = null;
const MLFeed::GhostInfo_V2@ spectating = null;
const MLFeed::GhostInfo_V2@ bestGhost = null;

void WatchForReset() {
    auto gd = MLFeed::GetGhostData();
    auto lastNbGhosts = gd.NbGhosts;
    while (true) {
        yield();
        if (lastNbGhosts != gd.NbGhosts && gd.NbGhosts == 0) {
            @relativeTo = null;
            @spectating = null;
            @bestGhost = null;
            deletedGhosts.DeleteAll();
        }
        lastNbGhosts = gd.NbGhosts;
    }
}

array<const MLFeed::GhostInfo_V2@>@ UpdateGhosts() {
    auto gd = MLFeed::GetGhostData();
    array<const MLFeed::GhostInfo_V2@> sorted = {};
    auto sourceGhosts = S_LoadedGhostsOnly ? gd.LoadedGhosts : gd.SortedGhosts;
    if (sourceGhosts.Length < 1) return sorted;
    if (sourceGhosts.Length < 2) return {sourceGhosts[0]};

    bool isInit = spectating is null && relativeTo is null;

    for (uint i = 0; i < sourceGhosts.Length; i++) {
        auto g = sourceGhosts[i];
        if (deletedGhosts.Exists(g.IdName)) continue;
        if (bestGhost is null) {
            @bestGhost = g;
            sorted.InsertLast(g);
        }

        if (spectating is null && (g.IsLocalPlayer || g.IsPersonalBest)) {
            @spectating = g;
        }
        if (g.Result_Time < bestGhost.Result_Time) {
            @bestGhost = g;
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

    if (relativeTo is null) @relativeTo = bestGhost;
    if (spectating is null) @spectating = relativeTo;
    if (isInit && AreGhostDupliates(relativeTo, sorted[0])) {
        @spectating = sorted[sorted.Length - 1];
    };
    return sorted;
}


bool CollapseMainUI = false;

UI::Font@ g_fontSmall = UI::LoadFont("DroidSans.ttf", 16, -1, -1, true, true, true);
UI::Font@ g_fontMedium = UI::LoadFont("DroidSans.ttf", 20, -1, -1, true, true, true);
UI::Font@ g_fontLarge = UI::LoadFont("DroidSans.ttf", 26, -1, -1, true, true, true);
[Setting hidden]
int fontSizeIx = 0;
UI::Font@[] g_fonts = {g_fontSmall, g_fontMedium, g_fontLarge};

void IncrFontSize() {
    fontSizeIx = Math::Clamp(fontSizeIx + 1, 0, g_fonts.Length - 1);
}
void DecrFontSize() {
    fontSizeIx = Math::Clamp(fontSizeIx - 1, 0, g_fonts.Length - 1);
}

dictionary deletedGhosts;

void RenderInterface() {
    if (!IsWatchingGhost) return;
    auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    if (pgScript is null) return;
    auto map = GetApp().RootMap;
    if (map is null) return;

    // run update ghosts once before exiting when ghosts aren't set so that it shows up by default when overlay is hidden.
    if (!ShowWindow) return;

    UI::PushFont(g_fonts[Math::Clamp(fontSizeIx, 0, g_fonts.Length - 1)]);
    if (UI::Begin(MenuTitle, ShowWindow, UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoCollapse)) {
        if (UI::Button(CollapseMainUI ? "Expand" : "Collapse")) {
            CollapseMainUI = !CollapseMainUI;
        }
        UI::SameLine();
        if (UI::Button("+")) {
            IncrFontSize();
        }
        UI::SameLine();
        if (UI::Button("-")) {
            DecrFontSize();
        }
        UI::SameLine();
        if (UI::Button(Icons::Refresh + Icons::TrashO)) {
            deletedGhosts.DeleteAll();
        }

        if (CollapseMainUI) {
            UI::End();
            UI::PopFont();
            return;
        }

        auto sorted = UpdateGhosts();

        // UI::AlignTextToFramePadding();
        UI::Text(ColoredString(map.MapName) + "\\$z by " + map.AuthorNickName);
        UI::Text("Nb. Ghosts: " + sorted.Length);
        if (sorted.Length == 0 || sorted[0].Checkpoints.Length == 0) {
            UI::Text("Load some ghosts to view times.\n(Toggle the ghost if it doesn't show up.)");
            UI::Text("\\$888Alternatively: this might show if the first ghost has 0 checkpoint times.");
        } else if (bestGhost !is null) {
            UI::SameLine();
            UI::Text("/   Best: " + bestGhost.Nickname + " (" + Time::Format(bestGhost.Result_Time) + ")");
            ShowAllCpSplits = UI::Checkbox("Show All CP Splits", ShowAllCpSplits);
            // UI::SameLine();
            ShowSplitDeltasInstead = UI::Checkbox("Show Gain/Loss", ShowSplitDeltasInstead);
            // UI::SameLine();
            S_LoadedGhostsOnly = UI::Checkbox("Show only Loaded Ghosts", S_LoadedGhostsOnly);
            AddSimpleTooltip("If disabled, any ghost previously loaded during this session will be available.");

            uint nbCols = 2 + (ShowAllCpSplits ? bestGhost.Checkpoints.Length : 1);

            int currTime = int(pgScript.Now) - g_LastSetStartTime;

            uint currCp = 0;
            for (uint i = 0; i < relativeTo.Checkpoints.Length; i++) {
                if (int(relativeTo.Checkpoints[i]) <= currTime) currCp = i;
                else break;
            }
            uint specCp = 0;
            for (uint i = 0; i < spectating.Checkpoints.Length; i++) {
                if (int(spectating.Checkpoints[i]) <= currTime) specCp = i;
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
                    AddSimpleTooltip("Select Reference/Target Ghost");
                    UI::SameLine();
                    if (UI::Button(Icons::Eye)) {
                        @spectating = g;
                    }
                    AddSimpleTooltip("Select Spectating Ghost");
                    UI::SameLine();
                    bool isFocusGhost = relativeTo == g;
                    bool isSpecGhost = spectating == g;
                    UI::AlignTextToFramePadding();
                    UI::Text((isFocusGhost ? "\\$4f4" : isSpecGhost ? "\\$48f" : "") + g.Nickname);

                    int lastDelta = 0;
                    for (uint cp = 0; cp < g.Checkpoints.Length; cp++) {
                        auto bestT = relativeTo.Checkpoints[cp];
                        auto t = g.Checkpoints[cp];
                        if (ShowAllCpSplits || cp == currCp) {
                            UI::TableNextColumn();
                            string cpColor = ShowAllCpSplits ? (cp == currCp ? "\\$4f4" : cp == specCp ? "\\$48f" : "") : "";
                            UI::Text(isFocusGhost ? (cpColor + Time::Format(bestT)) : TimeDelta(bestT, t, true));
                            if (ShowSplitDeltasInstead && !isFocusGhost) {
                                UI::Text(TimeDelta(lastDelta, t - bestT, true));
                            }
                        }
                        lastDelta = t - bestT;
                    }

                    UI::TableNextColumn();
                    if (UI::Button(Icons::TrashO)) {
                        HideGhostFromList(g);
                    }

                    UI::PopID();
                }

                UI::EndTable();
            }

        }
    }
    // need to keep this in sync with early return point: CollapseMainUI
    UI::End();
    UI::PopFont();
}


void HideGhostFromList(const MLFeed::GhostInfo@ g) {
    auto gd = MLFeed::GetGhostData();
    for (uint i = 0; i < gd.Ghosts.Length; i++) {
        if (AreGhostDupliates(g, gd.Ghosts[i])) {
            deletedGhosts[gd.Ghosts[i].IdName] = true;
        }

    }
}


void Render() {
    if (!IsWatchingGhost) return;
    auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    if (pgScript is null) return;

    if (!ShowWindow) return;

    auto gd = MLFeed::GetGhostData();
    if ((relativeTo is null || spectating is null || bestGhost is null) && gd.NbGhosts >= 2) {
        UpdateGhosts();
    }

    if (relativeTo is null || spectating is null) return;
    if (relativeTo == spectating) return;

    int currTime = int(pgScript.Now) - g_LastSetStartTime;

    int lastDelta = 0;
    uint currCp = 0;
    int currDelta = 0;
    int currGainLoss = 0;
    int refCp = 0;
    int specCp = 0;

    if (currTime >= int(spectating.Checkpoints[0])) {
        for (uint i = 0; i < relativeTo.Checkpoints.Length; i++) {
            if (int(spectating.Checkpoints[i]) <= currTime) {
                specCp = spectating.Checkpoints[i];
                refCp = relativeTo.Checkpoints[i];
                currCp = i;
                currGainLoss = currDelta;
                lastDelta = currDelta;
                currDelta = specCp - refCp;
                currGainLoss -= currDelta;
            } else break;
        }
    }

    nvg::Reset();
    DrawNvgTitle(relativeTo.Nickname + " (ref) vs. " + spectating.Nickname + " (spec)");
    DrawNvgText(TimeDelta(refCp, specCp, false), GetBufColor(refCp, specCp));
    DrawNvgText(TimeDelta(lastDelta, currDelta, false), GetBufColor(lastDelta, currDelta), true);
    // print(spectating.Nickname);
}

[Setting category="General" name="Splits Color, Ahead" color]
vec4 S_SplitsAhead = vec4(0.082f, 0.819f, 0.000f, 1.000f);
[Setting category="General" name="Splits Color, Behind" color]
vec4 S_SplitsBehind = vec4(1, 0, 0, 1);


vec4 GetBufColor(int target, int spec) {
    if (spec < target) return S_SplitsAhead;
    if (spec == target) return vec4(1, 1, 1, 1);
    return S_SplitsBehind;
}


int g_nvgFont = nvg::LoadFont("DroidSans-Bold.ttf");
const float TAU = 6.283185307179586;

void DrawNvgText(const string &in toDraw, const vec4 &in bufColor, bool isSecondary = false) {
    auto screen = vec2(Draw::GetWidth(), Draw::GetHeight());
    vec2 pos = (screen * vec2(0.5, 0.15));
    float fontSize = screen.y * 0.05;
    float sw = fontSize * 0.11;

    nvg::FontFace(g_nvgFont);
    nvg::FontSize(fontSize);
    nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);
    // auto sizeWPad = nvg::TextBounds(toDraw.SubStr(0, toDraw.Length - 3) + "000") + vec2(20, 10);

    if (isSecondary) {
        float secTimerScale = .65;
        pos = pos + vec2(0, fontSize * (1. + secTimerScale) / 2. + 10 - .25);
        fontSize *= secTimerScale;
        sw *= Math::Sqrt(secTimerScale);
        nvg::FontSize(fontSize);
    }

    // "stroke"
    if (true) {
        float nCopies = 32; // this does not seem to be expensive
        nvg::FillColor(vec4(0,0,0, bufColor.w));
        for (float i = 0; i < nCopies; i++) {
            float angle = TAU * float(i) / nCopies;
            vec2 offs = vec2(Math::Sin(angle), Math::Cos(angle)) * sw;
            nvg::Text(pos + offs, toDraw);
        }
    }

    nvg::FillColor(bufColor);
    nvg::Text(pos, toDraw);
}


void DrawNvgTitle(const string &in toDraw, const vec4 &in bufColor = vec4(1, 1, 1, 1)) {
    auto screen = vec2(Draw::GetWidth(), Draw::GetHeight());
    vec2 pos = (screen * vec2(0.5, 0.05));
    float fontSize = screen.y * 0.04;

    nvg::FontFace(g_nvgFont);
    nvg::FontSize(fontSize);
    nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);

    nvg::FillColor(bufColor);
    nvg::Text(pos, toDraw);
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


bool IsWatchingGhost {
    get {
        try {
            auto gameTerm = cast<CSmArenaClient>(GetApp().CurrentPlayground).GameTerminals[0];
            auto viewingEntityOffset = 0x100;
            bool isWatching = Dev::GetOffsetUint8(gameTerm, viewingEntityOffset) == 0x1;
            bool entIdOkay = Dev::GetOffsetUint32(gameTerm, viewingEntityOffset + 0x4) & 0x04000000 > 0;
            bool uiSeqOkay = gameTerm.UISequence_Current == SGamePlaygroundUIConfig::EUISequence::EndRound
                || gameTerm.UISequence_Current == SGamePlaygroundUIConfig::EUISequence::UIInteraction;
            return isWatching && entIdOkay && uiSeqOkay;
        } catch {
            return false;
        }
    }
}


void AddSimpleTooltip(const string &in msg) {
    if (UI::IsItemHovered()) {
        UI::BeginTooltip();
        UI::Text(msg);
        UI::EndTooltip();
    }
}
