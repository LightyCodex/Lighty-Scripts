-- MovementSense v2 (corrigido) - MemeDash
local cloneref = cloneref or function(x) return x end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local VirtualUser = cloneref(game:GetService("VirtualUser"))
local Lighting = cloneref(game:GetService("Lighting"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local LocalPlayer = Players.LocalPlayer

-- Re-executar: limpa a instancia anterior (conexoes, objetos, GUI)
if getgenv().BaconCleanup then
    pcall(getgenv().BaconCleanup)
end

if setfpscap then pcall(setfpscap, 240) end

-- Constantes
local METER = 0.28                  -- 1 stud = 0.28 m (usado no ESP)
local FARM_HEIGHT = 100 / METER     -- 100 m reais em studs (~357)
local SPEED_VALUE = 300
local FLY_SPEED = 100
local KORBLOX_MESH_ID = "rbxassetid://101851696"      -- mesh da perna Korblox
local KORBLOX_COLOR = Color3.fromRGB(50, 50, 50)      -- cinza escuro

-- Estado
local State = {
    FlyFarm = false, Speed = false, Fly = false, Noclip = false,
    Players = false, Bots = false, LightBoost = false, AntiAFK = false,
    Headless = false, Korblox = false,
}

local connections = {}
local function track(conn)
    table.insert(connections, conn)
    return conn
end

local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getHrp()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------
-- NOCLIP / COLISAO (com restauracao)
------------------------------------------------------------------
local charParts = {}
local charConn
local collideOrig = {}

local function restoreCollisions()
    for part, value in pairs(collideOrig) do
        if part.Parent then
            pcall(function() part.CanCollide = value end)
        end
    end
    table.clear(collideOrig)
end

local function indexCharacter(char)
    if charConn then charConn:Disconnect() end
    table.clear(collideOrig)
    charParts = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(charParts, d) end
    end
    charConn = char.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then table.insert(charParts, d) end
    end)
end

------------------------------------------------------------------
-- SPEED
------------------------------------------------------------------
local origSpeed = 16
local speedApplied = false

------------------------------------------------------------------
-- FLY (LinearVelocity + AlignOrientation)
------------------------------------------------------------------
local flyAtt, flyLV, flyAO
local flyActive = false

local function destroyFly()
    if flyLV then flyLV:Destroy() flyLV = nil end
    if flyAO then flyAO:Destroy() flyAO = nil end
    if flyAtt then flyAtt:Destroy() flyAtt = nil end
    if flyActive then
        local hum = getHum()
        if hum then hum.PlatformStand = false end
    end
    flyActive = false
end

local function ensureFly(hrp)
    if flyAtt and flyAtt.Parent == hrp and flyLV and flyLV.Parent and flyAO and flyAO.Parent then
        return
    end
    destroyFly()
    flyAtt = Instance.new("Attachment")
    flyAtt.Name = "BaconFlyAtt"
    flyAtt.Parent = hrp

    flyLV = Instance.new("LinearVelocity")
    flyLV.Attachment0 = flyAtt
    flyLV.RelativeTo = Enum.ActuatorRelativeTo.World
    flyLV.MaxForce = 1e9
    flyLV.VectorVelocity = Vector3.zero
    flyLV.Parent = hrp

    flyAO = Instance.new("AlignOrientation")
    flyAO.Mode = Enum.OrientationAlignmentMode.OneAttachment
    flyAO.Attachment0 = flyAtt
    flyAO.RigidityEnabled = false
    flyAO.MaxTorque = 1e7
    flyAO.Responsiveness = 50
    flyAO.Parent = hrp
end

------------------------------------------------------------------
-- AUTO FARM 100m (trava de altitude)
------------------------------------------------------------------
local farmTargetY = nil
local farmAtt, farmLV

local function destroyFarm()
    farmTargetY = nil
    if farmLV then farmLV:Destroy() farmLV = nil end
    if farmAtt then farmAtt:Destroy() farmAtt = nil end
end

local function ensureFarm(hrp)
    if farmAtt and farmAtt.Parent == hrp and farmLV and farmLV.Parent then return end
    if farmLV then farmLV:Destroy() end
    if farmAtt then farmAtt:Destroy() end
    farmAtt = Instance.new("Attachment")
    farmAtt.Name = "BaconFarmAtt"
    farmAtt.Parent = hrp
    farmLV = Instance.new("LinearVelocity")
    farmLV.Attachment0 = farmAtt
    farmLV.RelativeTo = Enum.ActuatorRelativeTo.World
    farmLV.MaxForce = 1e6
    farmLV.VectorVelocity = Vector3.zero
    farmLV.Parent = hrp
end

------------------------------------------------------------------
-- LIGHT BOOST (com restauracao)
------------------------------------------------------------------
local lbOrig = {}
local lbLighting = nil
local lbToken = 0
local lbConn = nil

local function boostInstance(v)
    if lbOrig[v] then return end
    if v:IsA("Terrain") then return end
    if v:IsA("BasePart") then
        lbOrig[v] = { Material = v.Material, Reflectance = v.Reflectance }
        v.Material = Enum.Material.Plastic
        v.Reflectance = 0
    elseif v:IsA("Decal") or v:IsA("Texture") then
        lbOrig[v] = { Transparency = v.Transparency }
        v.Transparency = 1
    elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
        lbOrig[v] = { Enabled = v.Enabled }
        v.Enabled = false
    end
end

local function setLightBoost(on)
    lbToken = lbToken + 1
    local token = lbToken
    if lbConn then lbConn:Disconnect() lbConn = nil end

    if on then
        if not lbLighting then
            lbLighting = {
                GlobalShadows = Lighting.GlobalShadows,
                FogEnd = Lighting.FogEnd,
                Brightness = Lighting.Brightness,
            }
            pcall(function() lbLighting.Quality = settings().Rendering.QualityLevel end)
        end
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 1
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)

        lbConn = workspace.DescendantAdded:Connect(function(d)
            pcall(boostInstance, d)
        end)
        task.spawn(function()
            local n = 0
            for _, d in ipairs(workspace:GetDescendants()) do
                if token ~= lbToken then return end
                pcall(boostInstance, d)
                n = n + 1
                if n % 400 == 0 then task.wait() end
            end
        end)
    else
        for inst, props in pairs(lbOrig) do
            if inst.Parent then
                for k, val in pairs(props) do
                    pcall(function() inst[k] = val end)
                end
            end
        end
        table.clear(lbOrig)
        if lbLighting then
            Lighting.GlobalShadows = lbLighting.GlobalShadows
            Lighting.FogEnd = lbLighting.FogEnd
            Lighting.Brightness = lbLighting.Brightness
            if lbLighting.Quality then
                pcall(function() settings().Rendering.QualityLevel = lbLighting.Quality end)
            end
            lbLighting = nil
        end
    end
end

------------------------------------------------------------------
-- HEADLESS / KORBLOX (visual, so voce ve; com restauracao)
------------------------------------------------------------------
local function makeCosmetic()
    local orig = {}
    local obj = {}
    function obj.set(inst, prop, value)
        if not inst then return end
        local ok, cur = pcall(function() return inst[prop] end)
        if not ok then return end
        orig[inst] = orig[inst] or {}
        if orig[inst][prop] == nil then orig[inst][prop] = cur end
        if cur ~= value then
            pcall(function() inst[prop] = value end)
        end
    end
    function obj.restore()
        for inst, props in pairs(orig) do
            if inst.Parent then
                for p, v in pairs(props) do
                    pcall(function() inst[p] = v end)
                end
            end
        end
        table.clear(orig)
    end
    function obj.clear()
        table.clear(orig)
    end
    return obj
end

local headCos = makeCosmetic()
local legCos = makeCosmetic()

-- Korblox: troca a mesh da perna direita (R6 "Right Leg" ou R15 "RightUpperLeg")
local korbLeg = nil
local korbMesh = nil
local korbHidden = {}   -- meshes originais tiradas da perna (para restaurar)

local function resetKorbloxState()
    korbLeg = nil
    korbMesh = nil
    table.clear(korbHidden)
end

local function removeKorblox()
    if korbMesh then
        pcall(function() korbMesh:Destroy() end)
    end
    for _, m in ipairs(korbHidden) do
        pcall(function() m.Parent = korbLeg end)
    end
    legCos.restore()
    resetKorbloxState()
end

local function applyCosmetics()
    local char = LocalPlayer.Character
    if not char then return end

    if State.Headless then
        local head = char:FindFirstChild("Head")
        if head then
            headCos.set(head, "Transparency", 1)
            local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
            headCos.set(face, "Transparency", 1)
        end
    end

    if State.Korblox then
        local leg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightUpperLeg")
        if leg then
            if korbLeg ~= leg then
                removeKorblox()
                korbLeg = leg
                for _, child in ipairs(leg:GetChildren()) do
                    if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then
                        table.insert(korbHidden, child)
                        child.Parent = nil
                    end
                end
                korbMesh = Instance.new("SpecialMesh")
                korbMesh.Name = "BaconKorblox"
                korbMesh.MeshType = Enum.MeshType.FileMesh
                korbMesh.MeshId = KORBLOX_MESH_ID
                korbMesh.Scale = Vector3.new(1, 1, 1)
                korbMesh.Parent = leg
            end
            if korbMesh and korbMesh.Parent ~= leg then
                korbMesh.Parent = leg
            end
            legCos.set(leg, "Color", KORBLOX_COLOR)
        end
    end
end

------------------------------------------------------------------
-- ESP (players e bots, em qualquer pasta do workspace)
------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BaconScriptHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

do
    local hui = gethui and gethui()
    for _, parent in ipairs({ CoreGui, hui }) do
        if parent then
            local old = parent:FindFirstChild("BaconScriptHub")
            if old then old:Destroy() end
        end
    end
    if syn and syn.protect_gui then pcall(syn.protect_gui, ScreenGui) end
    ScreenGui.Parent = hui or CoreGui
end

local espGuis = {}
local botSet = {}
local wanted = {}

local function removeEsp(model)
    local e = espGuis[model]
    if e then
        e.gui:Destroy()
        espGuis[model] = nil
    end
end

local function ensureEsp(model, isBot)
    local e = espGuis[model]
    if e and e.gui.Parent then return e end
    local adornee = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
    if not adornee then return nil end

    local bb = Instance.new("BillboardGui")
    bb.Name = "BaconEspTag"
    bb.Adornee = adornee
    bb.Size = UDim2.new(0, 150, 0, 40)
    bb.StudsOffset = Vector3.new(0, 2.5, 0)
    bb.AlwaysOnTop = true

    local txt = Instance.new("TextLabel")
    txt.Name = "EspLabel"
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundTransparency = 1
    txt.Font = Enum.Font.SourceSansBold
    txt.TextSize = 14
    txt.TextColor3 = isBot and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(80, 220, 255)
    txt.TextStrokeTransparency = 0
    txt.Parent = bb

    bb.Parent = ScreenGui
    e = { gui = bb, label = txt, adornee = adornee, isBot = isBot }
    espGuis[model] = e
    return e
end

local function registerBotFromDescendant(d)
    if d:IsA("Humanoid") then
        local m = d.Parent
        if m and m:IsA("Model") then botSet[m] = true end
    end
end

local function scanBots()
    task.spawn(function()
        local n = 0
        for _, d in ipairs(workspace:GetDescendants()) do
            registerBotFromDescendant(d)
            n = n + 1
            if n % 400 == 0 then task.wait() end
        end
    end)
end

local function updateEsp()
    local myChar = LocalPlayer.Character
    local myHrp = getHrp()
    table.clear(wanted)

    if State.Players then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local e = ensureEsp(plr.Character, false)
                if e then
                    wanted[plr.Character] = true
                    local root = plr.Character:FindFirstChild("HumanoidRootPart") or e.adornee
                    local dist = myHrp and math.floor((myHrp.Position - root.Position).Magnitude * METER) or 0
                    e.label.Text = plr.DisplayName .. " [" .. dist .. "m]"
                end
            end
        end
    end

    if State.Bots then
        for model in pairs(botSet) do
            if not model.Parent then
                botSet[model] = nil
            elseif model ~= myChar and not Players:GetPlayerFromCharacter(model) then
                local e = ensureEsp(model, true)
                if e then
                    wanted[model] = true
                    local root = model:FindFirstChild("HumanoidRootPart") or e.adornee
                    local dist = myHrp and math.floor((myHrp.Position - root.Position).Magnitude * METER) or 0
                    e.label.Text = "[BOT] " .. model.Name .. " [" .. dist .. "m]"
                end
            end
        end
    end

    for model in pairs(espGuis) do
        if not wanted[model] or not model.Parent then
            removeEsp(model)
        end
    end
end

------------------------------------------------------------------
-- GUI
------------------------------------------------------------------
local function panel(parent, x, y, w, h, color)
    local f = Instance.new("Frame", parent)
    f.Position = UDim2.fromOffset(x, y)
    f.Size = UDim2.fromOffset(w, h)
    f.BackgroundColor3 = color
    f.BorderColor3 = Color3.fromRGB(45, 45, 45)
    return f
end

local function label(parent, txt, x, y, w, h)
    local l = Instance.new("TextLabel", parent)
    l.Position = UDim2.fromOffset(x, y)
    l.Size = UDim2.fromOffset(w, h)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 13
    l.TextColor3 = Color3.fromRGB(210, 210, 210)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = txt
    return l
end

local GREEN = Color3.fromRGB(164, 207, 40)

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.fromOffset(540, 340)
MainFrame.Position = UDim2.new(0.5, -270, 0.5, -170)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
MainFrame.BorderColor3 = Color3.fromRGB(75, 75, 75)
MainFrame.Active = true
MainFrame.Draggable = true

local bar = panel(MainFrame, 5, 5, 530, 2, Color3.new(1, 1, 1))
bar.BorderSizePixel = 0
local gradient = Instance.new("UIGradient", bar)

local side = panel(MainFrame, 6, 12, 48, 321, Color3.fromRGB(12, 12, 12))
local logo = label(side, "MS", 0, 8, 48, 30)
logo.Font = Enum.Font.SourceSansBold
logo.TextSize = 22
logo.TextXAlignment = Enum.TextXAlignment.Center
logo.TextColor3 = GREEN
panel(side, 7, 43, 34, 1, Color3.fromRGB(55, 55, 55))

local brand = label(MainFrame, "", 65, 12, 350, 24)
brand.Font = Enum.Font.SourceSansBold
brand.TextSize = 19
brand.RichText = true
brand.Text = 'MovementSense<font color="#A4CF28">.lol</font>'

local FpsLabel = label(MainFrame, "FPS: --", 425, 12, 105, 24)
FpsLabel.TextColor3 = GREEN

label(MainFrame, "MOVEMENTSENSE  |  B to open menu", 65, 315, 460, 20)

-- Paginas (abas MOVE / VIEW funcionais)
local pages = {}
local tabs = {}
local function makePage()
    local f = Instance.new("Frame", MainFrame)
    f.Position = UDim2.fromOffset(65, 44)
    f.Size = UDim2.fromOffset(467, 270)
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    return f
end
pages[1] = makePage()
pages[2] = makePage()

local function selectTab(index)
    for i, page in ipairs(pages) do
        page.Visible = (i == index)
        tabs[i].TextColor3 = (i == index) and GREEN or Color3.fromRGB(150, 150, 150)
    end
end

for i, item in ipairs({ { "MOVE", "M" }, { "VIEW", "V" } }) do
    local tile = Instance.new("TextButton", side)
    tile.Position = UDim2.fromOffset(5, 53 + (i - 1) * 66)
    tile.Size = UDim2.fromOffset(38, 58)
    tile.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    tile.BorderColor3 = Color3.fromRGB(45, 45, 45)
    tile.AutoButtonColor = false
    tile.Font = Enum.Font.SourceSansBold
    tile.RichText = true
    tile.Text = '<font size="23">' .. item[2] .. '</font>\n<font size="10">' .. item[1] .. '</font>'
    tabs[i] = tile
    tile.MouseButton1Click:Connect(function() selectTab(i) end)
end

local moveLeft = panel(pages[1], 0, 0, 229, 270, Color3.fromRGB(24, 24, 24))
local moveRight = panel(pages[1], 237, 0, 230, 270, Color3.fromRGB(24, 24, 24))
local viewLeft = panel(pages[2], 0, 0, 229, 270, Color3.fromRGB(24, 24, 24))
local viewRight = panel(pages[2], 237, 0, 230, 270, Color3.fromRGB(24, 24, 24))

label(moveLeft, "Movement", 10, 5, 200, 24)
label(moveRight, "Misc", 10, 5, 200, 24)
label(viewLeft, "ESP", 10, 5, 200, 24)
label(viewRight, "Avatar", 10, 5, 215, 24)

label(viewRight, "Teclas", 10, 135, 200, 20)
for i, line in ipairs({ "B  - abrir/fechar menu", "X  - speed 300", "E  - fly" }) do
    label(viewRight, line, 12, 158 + (i - 1) * 22, 205, 20)
end

-- Toggles
local toggles = {}
local onChange = {}
local updateHotkeys
local setToggle

local function createToggle(parent, name, index, key)
    local btn = Instance.new("TextButton", parent)
    btn.Position = UDim2.fromOffset(12, 35 + index * 34)
    btn.Size = UDim2.fromOffset(205, 28)
    btn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(210, 210, 210)
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Font = Enum.Font.Code
    btn.TextSize = 12
    local padding = Instance.new("UIPadding", btn)
    padding.PaddingLeft = UDim.new(0, 18)
    local mark = panel(btn, -18, 10, 8, 8, Color3.fromRGB(65, 65, 65))
    toggles[key] = { btn = btn, name = name, mark = mark }
    btn.MouseButton1Click:Connect(function()
        setToggle(key, not State[key])
    end)
end

function setToggle(key, value)
    State[key] = value
    local t = toggles[key]
    if t then
        t.mark.BackgroundColor3 = value and GREEN or Color3.fromRGB(65, 65, 65)
    end
    -- Fly e Auto Farm nao rodam juntos
    if value and key == "Fly" and State.FlyFarm then setToggle("FlyFarm", false) end
    if value and key == "FlyFarm" and State.Fly then setToggle("Fly", false) end
    if onChange[key] then pcall(onChange[key], value) end
    if updateHotkeys then updateHotkeys() end
end

createToggle(moveLeft, "Auto Farm 100m", 0, "FlyFarm")
createToggle(moveLeft, "Speed 300 (X)", 1, "Speed")
createToggle(moveLeft, "Fly (E)", 2, "Fly")
createToggle(moveLeft, "Noclip", 3, "Noclip")
createToggle(moveRight, "Fix Lag / Light Boost", 0, "LightBoost")
createToggle(moveRight, "Anti-AFK", 1, "AntiAFK")
createToggle(viewLeft, "ESP Players", 0, "Players")
createToggle(viewLeft, "ESP Bots", 1, "Bots")
createToggle(viewRight, "Headless", 0, "Headless")
createToggle(viewRight, "Korblox", 1, "Korblox")

onChange.Headless = function(on)
    if not on then headCos.restore() end
end
onChange.Korblox = function(on)
    if not on then removeKorblox() end
end
onChange.LightBoost = setLightBoost
onChange.Bots = function(on)
    if on then scanBots() end
end

-- Overlay de hotkeys
local hotkeys = panel(ScreenGui, 20, 180, 195, 30, Color3.fromRGB(16, 16, 16))
hotkeys.Active = true
hotkeys.Draggable = true
local hotbar = panel(hotkeys, 2, 2, 191, 2, Color3.new(1, 1, 1))
hotbar.BorderSizePixel = 0
local hotgradient = Instance.new("UIGradient", hotbar)
local heading = label(hotkeys, "hotkeys", 0, 5, 195, 20)
heading.TextXAlignment = Enum.TextXAlignment.Center
panel(hotkeys, 5, 26, 185, 1, Color3.fromRGB(45, 45, 45))

local hotItems = { { "Speed Hack", "Speed" }, { "Fly", "Fly" } }
local entries = {}
for i, item in ipairs(hotItems) do
    local line = panel(hotkeys, 5, 30, 185, 20, Color3.fromRGB(16, 16, 16))
    line.BorderSizePixel = 0
    label(line, item[1], 3, 0, 100, 20)
    local status = label(line, "[toggled]", 105, 0, 77, 20)
    status.TextColor3 = GREEN
    entries[i] = line
end
local empty = label(hotkeys, "No active hotkeys", 0, 30, 195, 20)
empty.TextXAlignment = Enum.TextXAlignment.Center
empty.TextColor3 = Color3.fromRGB(130, 130, 130)

function updateHotkeys()
    local count = 0
    for i, line in ipairs(entries) do
        local on = State[hotItems[i][2]]
        line.Visible = on
        if on then
            line.Position = UDim2.fromOffset(5, 30 + count * 20)
            count = count + 1
        end
    end
    empty.Visible = count == 0
    hotkeys.Size = UDim2.fromOffset(195, 34 + math.max(1, count) * 20)
end

selectTab(1)
updateHotkeys()

------------------------------------------------------------------
-- LOOPS
------------------------------------------------------------------
local rgbStart = os.clock()
local frameCount = 0
local lastCheck = os.clock()

-- Visual: RGB, FPS, ESP
track(RunService.RenderStepped:Connect(function()
    local now = os.clock()

    local phase = (now - rgbStart) / 4
    local points = {}
    for i = 0, 12 do
        local t = i / 12
        points[i + 1] = ColorSequenceKeypoint.new(t, Color3.fromHSV((t - phase) % 1, 0.65, 0.9))
    end
    local seq = ColorSequence.new(points)
    gradient.Color = seq
    hotgradient.Color = seq

    frameCount = frameCount + 1
    if now - lastCheck >= 1 then
        FpsLabel.Text = "FPS: " .. frameCount
        frameCount = 0
        lastCheck = now
    end

    updateEsp()
end))

-- Speed + Fly
track(RunService.RenderStepped:Connect(function()
    local hum = getHum()
    if hum then
        if hum.WalkSpeed ~= SPEED_VALUE then origSpeed = hum.WalkSpeed end
        if State.Speed then
            if hum.MoveDirection.Magnitude > 0 then
                hum.WalkSpeed = SPEED_VALUE
            else
                hum.WalkSpeed = origSpeed
            end
            speedApplied = true
        elseif speedApplied then
            hum.WalkSpeed = origSpeed
            speedApplied = false
        end
    end

    if State.Fly then
        local hrp = getHrp()
        if hrp and hum then
            ensureFly(hrp)
            flyActive = true
            hum.PlatformStand = true
            local cam = workspace.CurrentCamera
            local dir = Vector3.zero
            if not UserInputService:GetFocusedTextBox() then
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
            end
            if dir.Magnitude > 0 then dir = dir.Unit end
            flyLV.VectorVelocity = dir * FLY_SPEED
            flyAO.CFrame = cam.CFrame
        end
    elseif flyActive or flyAtt then
        destroyFly()
    end
end))

-- Noclip + Auto Farm (fisica)
track(RunService.Stepped:Connect(function()
    local collideOff = State.Noclip or State.FlyFarm
    if collideOff then
        for _, part in ipairs(charParts) do
            if part.Parent then
                if collideOrig[part] == nil then collideOrig[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
    elseif next(collideOrig) then
        restoreCollisions()
    end

    if State.FlyFarm then
        local hrp = getHrp()
        if hrp then
            if not farmTargetY then farmTargetY = hrp.Position.Y + FARM_HEIGHT end
            ensureFarm(hrp)
            hrp.CFrame = CFrame.new(hrp.Position.X, farmTargetY, hrp.Position.Z) * hrp.CFrame.Rotation
        end
    elseif farmTargetY or farmLV then
        destroyFarm()
    end
end))

-- Headless / Korblox (reaplica todo frame, o jogo pode resetar)
track(RunService.RenderStepped:Connect(applyCosmetics))

-- Personagem (respawn)
track(LocalPlayer.CharacterAdded:Connect(function(char)
    farmTargetY = nil
    headCos.clear()
    legCos.clear()
    resetKorbloxState()
    indexCharacter(char)
end))
if LocalPlayer.Character then indexCharacter(LocalPlayer.Character) end

-- Bots: registra novos Humanoids em qualquer lugar do workspace
track(workspace.DescendantAdded:Connect(registerBotFromDescendant))

-- Anti-AFK
track(LocalPlayer.Idled:Connect(function()
    if State.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end))

-- Teclas: B (menu), X (speed), E (fly)
track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.B then
        MainFrame.Visible = not MainFrame.Visible
    elseif input.KeyCode == Enum.KeyCode.X then
        setToggle("Speed", not State.Speed)
    elseif input.KeyCode == Enum.KeyCode.E then
        setToggle("Fly", not State.Fly)
    end
end))

------------------------------------------------------------------
-- CLEANUP (chamado automaticamente ao re-executar)
------------------------------------------------------------------
local cleaned = false
local function cleanup()
    if cleaned then return end
    cleaned = true
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if charConn then pcall(function() charConn:Disconnect() end) end
    pcall(setLightBoost, false)
    headCos.restore()
    removeKorblox()
    destroyFly()
    destroyFarm()
    restoreCollisions()
    local hum = getHum()
    if hum and speedApplied then hum.WalkSpeed = origSpeed end
    for model in pairs(espGuis) do removeEsp(model) end
    ScreenGui:Destroy()
    getgenv().BaconCleanup = nil
end
getgenv().BaconCleanup = cleanup
