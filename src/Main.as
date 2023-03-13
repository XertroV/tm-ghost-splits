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

const MLFeed::GhostInfo@ relativeTo = null;
const MLFeed::GhostInfo@ spectating = null;

void WatchForReset() {
    auto gd = MLFeed::GetGhostData();
    auto lastNbGhosts = gd.NbGhosts;
    while (true) {
        yield();
        if (lastNbGhosts != gd.NbGhosts && gd.NbGhosts == 0) {
            @relativeTo = null;
            @spectating = null;
        }
        lastNbGhosts = gd.NbGhosts;
    }
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

void RenderInterface() {
    if (!ShowWindow) return;
    // UI Seq is end round when ghosts are being spectated.
    if (!IsUiSeqEndRound) return;
    auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    if (pgScript is null) return;
    auto map = GetApp().RootMap;
    if (map is null) return;

    auto gd = MLFeed::GetGhostData();
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

        if (CollapseMainUI) {
            UI::End();
            UI::PopFont();
            return;
        }

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
                auto g2 = gd.Ghosts_V2[i];
                if (spectating is null && (g2.IsLocalPlayer || g2.IsPersonalBest)) {
                    @spectating = g;
                }
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
            if (spectating is null) @spectating = relativeTo;

            UI::SameLine();
            UI::Text("/   Best: " + best.Nickname + " (" + Time::Format(best.Result_Time) + ")");
            ShowAllCpSplits = UI::Checkbox("Show All CP Splits", ShowAllCpSplits);
            ShowSplitDeltasInstead = UI::Checkbox("Show Gain/Loss", ShowSplitDeltasInstead);

            uint nbCols = 1 + (ShowAllCpSplits ? best.Checkpoints.Length : 1);

            int currTime = int(pgScript.Now) - g_LastSetStartTime;

            uint currCp = 0;
            for (uint i = 0; i < relativeTo.Checkpoints.Length; i++) {
                if (relativeTo.Checkpoints[i] <= currTime) currCp = i;
                else break;
            }
            uint specCp = 0;
            for (uint i = 0; i < spectating.Checkpoints.Length; i++) {
                if (spectating.Checkpoints[i] <= currTime) specCp = i;
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


void Render() {
    if (!ShowWindow) return;
    if (!IsUiSeqEndRound) return;
    auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    if (pgScript is null) return;
    if (relativeTo is null || spectating is null) return;
    if (relativeTo == spectating) return;

    int currTime = int(pgScript.Now) - g_LastSetStartTime;

    int lastDelta = 0;
    uint currCp = 0;
    int currDelta = 0;
    int currGainLoss = 0;
    int refCp = 0;
    int specCp = 0;

    if (currTime >= spectating.Checkpoints[0]) {
        for (uint i = 0; i < relativeTo.Checkpoints.Length; i++) {
            if (spectating.Checkpoints[i] <= currTime) {
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


int g_font = nvg::LoadFont("DroidSans-Bold.ttf");
const float TAU = 6.283185307179586;

void DrawNvgText(const string &in toDraw, const vec4 &in bufColor, bool isSecondary = false) {
    auto screen = vec2(Draw::GetWidth(), Draw::GetHeight());
    vec2 pos = (screen * vec2(0.5, 0.15));
    float fontSize = screen.y * 0.05;
    float sw = fontSize * 0.11;

    nvg::FontFace(g_font);
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
    float sw = fontSize * 0.11;

    nvg::FontFace(g_font);
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

void AddSimpleTooltip(const string &in msg) {
    if (UI::IsItemHovered()) {
        UI::BeginTooltip();
        UI::Text(msg);
        UI::EndTooltip();
    }
}
