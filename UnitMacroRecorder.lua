-- Unit Macro Recorder with ObsidianUi

local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local E = RS:WaitForChild("endpoints"):WaitForChild("client_to_server")
local watched = {
    [E:WaitForChild("spawn_unit")] = "Place unit",
    [E:WaitForChild("use_active_attack")] = "Use skill",
    [E:WaitForChild("use_custom_unit_control")] = "Use unit control",
}

local G = getgenv()
local M = G.UnitMacroRecorder or {steps = {}, hooked = false}
G.UnitMacroRecorder = M
M.recording, M.playing, M.autoReplay, M.autoStart = false, false, false, false
M.replayDelay, M.startedThisMatch = 3, false

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/yukvx/ObsidianUi/main/Library.lua"))()
local Window = Library:CreateWindow({
    Title = "Unit Macro Recorder", Footer = "Placement + skill timeline",
    ToggleKeybind = Enum.KeyCode.RightControl, Center = true, AutoShow = true,
    Size = UDim2.fromOffset(720, 470), Icon = "play",
})

local Recorder = Window:AddTab("Recorder", "circle-dot")
local Automation = Window:AddTab("Automation", "repeat-2")
local Timeline = Window:AddTab("Timeline", "list")
local Capture = Recorder:AddLeftGroupbox("Capture")
local Playback = Recorder:AddRightGroupbox("Playback")
local Auto = Automation:AddLeftGroupbox("Automatic runs")
local Saved = Timeline:AddLeftGroupbox("Saved actions")
local Status = Capture:AddLabel("Status: Ready")
local Count = Saved:AddLabel("No actions saved")
local List = Saved:AddLabel({Text = "Record placements and skills to build a timeline.", DoesWrap = true})

local function status(text) Status:SetText("Status: " .. text) end
local function refresh()
    Count:SetText(#M.steps .. " saved action" .. (#M.steps == 1 and "" or "s"))
    if #M.steps == 0 then List:SetText("Record placements and skills to build a timeline.") return end
    local rows = {}
    for i, step in ipairs(M.steps) do rows[i] = string.format("%02d  %s  +%.2fs", i, step.label, step.delay) end
    List:SetText(table.concat(rows, "\n"))
end

function M:Play()
    if self.playing or self.recording or #self.steps == 0 then return false end
    self.playing = true
    task.spawn(function()
        for i, step in ipairs(self.steps) do
            if not self.playing then break end
            status(string.format("Playing %d/%d: %s", i, #self.steps, step.label))
            task.wait(step.delay)
            pcall(function()
                if step.method == "InvokeServer" then
                    step.remote:InvokeServer(table.unpack(step.args, 1, step.args.n))
                else
                    step.remote:FireServer(table.unpack(step.args, 1, step.args.n))
                end
            end)
        end
        self.playing = false
        status("Playback complete")
        if self.autoReplay and #self.steps > 0 then
            task.wait(self.replayDelay)
            if self.autoReplay then self:Play() end
        end
    end)
    return true
end

Capture:AddButton({Text = "Start recording", Func = function()
    if M.playing then return end
    M.steps, M.recording, M.lastAt = {}, true, os.clock()
    status("Recording placements and skills")
    refresh()
end})
Capture:AddButton({Text = "Stop recording", Func = function() M.recording = false status("Recording saved") end})
Capture:AddButton({Text = "Clear timeline", Risky = true, Func = function()
    if M.playing then return end
    M.recording, M.steps = false, {}
    status("Timeline cleared")
    refresh()
end})
Playback:AddButton({Text = "Play saved macro", Func = function()
    if #M.steps == 0 then status("Record an action first") else M:Play() end
end})
Playback:AddLabel({Text = "The first action plays immediately; later steps preserve recorded timing.", DoesWrap = true})

Auto:AddToggle("AutoReplay", {Text = "Auto Replay", Default = false, Callback = function(value)
    M.autoReplay = value
    status(value and "Auto Replay enabled" or "Auto Replay disabled")
end})
Auto:AddSlider("ReplayDelay", {Text = "Replay delay", Default = 3, Min = 1, Max = 30, Rounding = 0, Suffix = " sec", Callback = function(value) M.replayDelay = value end})
Auto:AddToggle("AutoStart", {Text = "Auto Start on match", Default = false, Callback = function(value)
    M.autoStart, M.startedThisMatch = value, false
    status(value and "Auto Start armed" or "Auto Start disabled")
    local wave = WS:FindFirstChild("_waves_started")
    if value and wave and wave.Value then M.startedThisMatch = true M:Play() end
end})
Auto:AddLabel({Text = "Auto Start runs the macro once when the match begins.", DoesWrap = true})

local wave = WS:FindFirstChild("_waves_started")
if wave and not M.waveConnection then
    M.waveConnection = wave:GetPropertyChangedSignal("Value"):Connect(function()
        if not wave.Value then
            M.startedThisMatch = false
        elseif M.autoStart and not M.startedThisMatch then
            M.startedThisMatch = true
            M:Play()
        end
    end)
end

if not M.hooked and hookmetamethod and getnamecallmethod and newcclosure then
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if M.recording and not M.playing and watched[self] and (method == "InvokeServer" or method == "FireServer") then
            local now = os.clock()
            table.insert(M.steps, {remote = self, method = method, args = table.pack(...), label = watched[self], delay = #M.steps == 0 and 0 or math.max(0, now - M.lastAt)})
            M.lastAt = now
            refresh()
            status(#M.steps .. " action" .. (#M.steps == 1 and "" or "s") .. " captured")
        end
        return old(self, ...)
    end))
    M.hooked = true
end

refresh()
Library:Notify({Title = "Unit Macro Recorder", Description = "ObsidianUi loaded.", Time = 4})
