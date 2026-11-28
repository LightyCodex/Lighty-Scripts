-- MovementSense V3.0 - MemeDash
-- Menu novo (layout do mockup), Input Capture, watermark, hotkeys e otimizacoes.

local cloneref = cloneref or function(x) return x end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local VirtualUser = cloneref(game:GetService("VirtualUser"))
local Lighting = cloneref(game:GetService("Lighting"))
local Stats = cloneref(game:GetService("Stats"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local TweenService = cloneref(game:GetService("TweenService"))
local LocalPlayer = Players.LocalPlayer

-- Re-executar: limpa a instancia anterior (conexoes, objetos, GUI)
if getgenv().BaconCleanup then
    pcall(getgenv().BaconCleanup)
end

if setfpscap then pcall(setfpscap, 240) end

-- Constantes
local VERSION = "V3.0"
local METER = 0.28                  -- 1 stud = 0.28 m (usado no ESP)
local FARM_HEIGHT = 100 / METER     -- 100 m reais em studs (~357)
local SPEED_VALUE = 300
local FLY_SPEED = 100
local KORBLOX_MESH_ID = "rbxassetid://101851696"      -- mesh da perna Korblox
local KORBLOX_COLOR = Color3.fromRGB(50, 50, 50)      -- cinza escuro

-- Estado (funcoes ligadas/desligadas)
local State = {
    FlyFarm = false, Speed = false, Fly = false, Noclip = false,
    Players = false, Bots = false, LightBoost = false, AntiAFK = false,
    Headless = false, Korblox = false,
    -- configuracoes do menu
    Watermark = true, CustomCursor = true, Compact = false, Resizable = true,
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
    if not (State.Headless or State.Korblox) then return end
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
-- SCREENGUI + ESP (players e bots, em qualquer pasta do workspace)
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
local botSet = setmetatable({}, { __mode = "k" }) -- fraca: nao segura NPCs removidos
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
-- GUI: tema, ajudantes, arrastar/redimensionar
------------------------------------------------------------------
local FONT, FONT_BOLD = Enum.Font.Arial, Enum.Font.ArialBold
local TAB_NAMES = { "MOVE", "ESP", "WORLD", "SET", "AVATAR", "INFO" }

local THEMES = {
    Classic = {
        bg = Color3.fromRGB(16, 16, 16), panel = Color3.fromRGB(21, 21, 21),
        border = Color3.fromRGB(85, 85, 85), panelBorder = Color3.fromRGB(69, 69, 69),
        line = Color3.fromRGB(41, 41, 41), sidebar = Color3.fromRGB(11, 11, 11),
        sidebarBorder = Color3.fromRGB(68, 68, 68), tabActive = Color3.fromRGB(27, 27, 27),
        tabHover = Color3.fromRGB(32, 32, 32), text = Color3.fromRGB(221, 221, 221),
        muted = Color3.fromRGB(136, 136, 136), box = Color3.fromRGB(51, 51, 51),
        boxBorder = Color3.fromRGB(85, 85, 85), field = Color3.fromRGB(25, 25, 25),
        fieldBorder = Color3.fromRGB(48, 48, 48), bad = Color3.fromRGB(230, 80, 80),
    },
    Dark = {
        bg = Color3.fromRGB(8, 8, 8), panel = Color3.fromRGB(13, 13, 13),
        border = Color3.fromRGB(50, 50, 50), panelBorder = Color3.fromRGB(40, 40, 40),
        line = Color3.fromRGB(28, 28, 28), sidebar = Color3.fromRGB(5, 5, 5),
        sidebarBorder = Color3.fromRGB(38, 38, 38), tabActive = Color3.fromRGB(20, 20, 20),
        tabHover = Color3.fromRGB(16, 16, 16), text = Color3.fromRGB(200, 200, 200),
        muted = Color3.fromRGB(110, 110, 110), box = Color3.fromRGB(30, 30, 30),
        boxBorder = Color3.fromRGB(60, 60, 60), field = Color3.fromRGB(16, 16, 16),
        fieldBorder = Color3.fromRGB(36, 36, 36), bad = Color3.fromRGB(220, 70, 70),
    },
    Minimal = {
        bg = Color3.fromRGB(32, 32, 34), panel = Color3.fromRGB(38, 38, 40),
        border = Color3.fromRGB(62, 62, 66), panelBorder = Color3.fromRGB(58, 58, 62),
        line = Color3.fromRGB(54, 54, 58), sidebar = Color3.fromRGB(27, 27, 29),
        sidebarBorder = Color3.fromRGB(58, 58, 62), tabActive = Color3.fromRGB(46, 46, 50),
        tabHover = Color3.fromRGB(42, 42, 45), text = Color3.fromRGB(236, 236, 236),
        muted = Color3.fromRGB(150, 150, 156), box = Color3.fromRGB(60, 60, 64),
        boxBorder = Color3.fromRGB(92, 92, 98), field = Color3.fromRGB(42, 42, 45),
        fieldBorder = Color3.fromRGB(70, 70, 74), bad = Color3.fromRGB(235, 90, 90),
    },
}
local THEME_NAMES = { "Classic", "Dark", "Minimal" }

local ACCENTS = {
    { "Lime", Color3.fromRGB(164, 207, 40) },
    { "Cyan", Color3.fromRGB(82, 199, 236) },
    { "Magenta", Color3.fromRGB(198, 89, 200) },
    { "Orange", Color3.fromRGB(240, 150, 40) },
    { "Red", Color3.fromRGB(230, 70, 70) },
    { "White", Color3.fromRGB(235, 235, 235) },
}

local CURSOR_STYLES = { "Classic white", "Accent", "Dark" }

local Settings = { theme = 1, scale = 100, opacity = 100, accent = 1, cursorStyle = 1 }

local palette = {}
local bindings = {}      -- { objeto, propriedade, chave da paleta }
local paletteHooks = {}  -- funcoes chamadas quando o tema/cor muda

local function loadPalette()
    for k, v in pairs(THEMES[THEME_NAMES[Settings.theme]]) do palette[k] = v end
    palette.accent = ACCENTS[Settings.accent][2]
end
loadPalette()

local function bind(obj, prop, key)
    obj[prop] = palette[key]
    table.insert(bindings, { obj, prop, key })
end

local function applyPalette()
    loadPalette()
    for _, b in ipairs(bindings) do
        pcall(function() b[1][b[2]] = palette[b[3]] end)
    end
    for _, fn in ipairs(paletteHooks) do pcall(fn) end
end

local function accentHex()
    local c = palette.accent
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function stroke(parent, key)
    local s = Instance.new("UIStroke")
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    bind(s, "Color", key)
    s.Parent = parent
    return s
end

-- Rotulo de texto (cor ligada a uma chave da paleta, ou cor fixa em props.raw)
local function text(parent, str, props)
    props = props or {}
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.Font = props.bold and FONT_BOLD or FONT
    l.TextSize = props.size or 13
    l.Text = str
    l.TextXAlignment = props.align or Enum.TextXAlignment.Left
    l.Size = props.sizeU or UDim2.new(1, 0, 1, 0)
    if props.pos then l.Position = props.pos end
    if props.raw then l.TextColor3 = props.raw else bind(l, "TextColor3", props.color or "text") end
    l.Parent = parent
    return l
end

local function dot(parent, key, pos)
    local d = new("Frame", {
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = pos,
        Size = UDim2.fromOffset(7, 7),
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
    bind(d, "BackgroundColor3", key)
    return d
end

-- Barra RGB animada: tira com 2 ciclos de cores deslizando 1 ciclo em loop.
-- Usa um Tween (nenhum custo por frame no script).
local rgbTweens = {}
local RGB_COLORS = { Color3.fromRGB(82, 199, 236), Color3.fromRGB(198, 89, 200), Color3.fromRGB(164, 207, 40) }
local function makeRgbBar(parent, pos, size)
    local clip = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
        Position = pos, Size = size,
    }, parent)
    local strip = new("Frame", {
        BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(2, 0, 1, 0),
    }, clip)
    local keys = {}
    for i = 0, 6 do
        keys[i + 1] = ColorSequenceKeypoint.new(i / 6, RGB_COLORS[(i % 3) + 1])
    end
    new("UIGradient", { Color = ColorSequence.new(keys) }, strip)
    local tween = TweenService:Create(
        strip,
        TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
        { Position = UDim2.new(-1, 0, 0, 0) }
    )
    tween:Play()
    table.insert(rgbTweens, tween)
    return clip
end

-- Arrastar / redimensionar / sliders (um unico par de eventos globais)
local drag = nil
local function makeDraggable(target, handle)
    handle.Active = true
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = {
                kind = "move", target = target,
                startMouse = UserInputService:GetMouseLocation(), startPos = target.Position,
            }
        end
    end)
end

-- Estado do Input Capture (a logica fica no fim do script, isolada com pcall)
local capture = { active = false }

------------------------------------------------------------------
-- GUI: janela principal
------------------------------------------------------------------
local MIN_W, MIN_H, MAX_W, MAX_H = 550, 450, 1600, 1000
local cam = workspace.CurrentCamera
local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
local startW = math.clamp(math.floor(vp.X * 0.9), MIN_W, 840)
local startH = math.clamp(math.floor(vp.Y * 0.85), MIN_H, 720)

local opacityTargets = {}
local rowLayouts = {}

local MainFrame, uiScale, headingLabel, panelsHolder, sidebar, FpsLabel, resizeHandle

do
    MainFrame = new("Frame", {
        Name = "Menu", BorderSizePixel = 0, Active = true,
        Size = UDim2.fromOffset(startW, startH),
        Position = UDim2.fromOffset(math.floor((vp.X - startW) / 2), math.floor((vp.Y - startH) / 2)),
    }, ScreenGui)
    bind(MainFrame, "BackgroundColor3", "bg")
    stroke(MainFrame, "border")
    table.insert(opacityTargets, MainFrame)
    uiScale = new("UIScale", { Scale = 1 }, MainFrame)

    -- borda dupla (como no mockup)
    local doubleBorder = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8),
    }, MainFrame)
    stroke(doubleBorder, "border")

    local root = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24),
    }, MainFrame)

    makeRgbBar(root, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 2))

    -- cabecalho
    local header = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 58),
    }, root)
    local headerLine = new("Frame", {
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1),
    }, header)
    bind(headerLine, "BackgroundColor3", "line")

    local brand = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0.7, 0, 1, 0),
    }, header)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, brand)
    local brandA = text(brand, "MovementSense", { bold = true, size = 19, sizeU = UDim2.fromOffset(0, 26) })
    brandA.AutomaticSize = Enum.AutomaticSize.X
    brandA.LayoutOrder = 1
    local brandB = text(brand, ".lol", { bold = true, size = 19, color = "accent", sizeU = UDim2.fromOffset(0, 26) })
    brandB.AutomaticSize = Enum.AutomaticSize.X
    brandB.LayoutOrder = 2

    local versionLabel = text(header, VERSION, {
        size = 12, color = "muted", align = Enum.TextXAlignment.Right,
        sizeU = UDim2.fromOffset(80, 16),
    })
    versionLabel.AnchorPoint = Vector2.new(1, 0.5)
    versionLabel.Position = UDim2.new(1, -8, 0.5, 0)
    makeDraggable(MainFrame, header)

    -- corpo
    local body = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 1, -98),
    }, root)

    sidebar = new("Frame", {
        BorderSizePixel = 0, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(0, 60, 1, -32),
    }, body)
    bind(sidebar, "BackgroundColor3", "sidebar")
    stroke(sidebar, "sidebarBorder")
    table.insert(opacityTargets, sidebar)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
    }, sidebar)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)

    local content = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(72, 16), Size = UDim2.new(1, -72, 1, -32),
    }, body)

    -- titulo da aba + "Active"
    local headingRow = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24),
    }, content)
    headingLabel = text(headingRow, "Movement", { bold = true, pos = UDim2.fromOffset(2, 0), sizeU = UDim2.new(0.6, 0, 1, 0) })
    local activeBox = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(80, 24),
    }, headingRow)
    dot(activeBox, "accent", UDim2.new(0, 4, 0.5, 0))
    text(activeBox, "Active", { color = "accent", pos = UDim2.fromOffset(16, 0), sizeU = UDim2.new(1, -16, 1, 0) })

    panelsHolder = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36),
    }, content)

    -- rodape
    local footer = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 38),
    }, root)
    local footerLine = new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1) }, footer)
    bind(footerLine, "BackgroundColor3", "line")
    dot(footer, "accent", UDim2.new(0, 6, 0.5, 0))
    text(footer, "MovementSense.lol", { size = 12, color = "muted", pos = UDim2.fromOffset(20, 0), sizeU = UDim2.new(0.6, 0, 1, 0) })
    FpsLabel = text(footer, "-- FPS", {
        size = 12, color = "accent", align = Enum.TextXAlignment.Right,
        sizeU = UDim2.fromOffset(120, 16),
    })
    FpsLabel.AnchorPoint = Vector2.new(1, 0.5)
    FpsLabel.Position = UDim2.new(1, -30, 0.5, 0)

    -- alca de redimensionar (canto inferior direito, desenhada com linhas)
    resizeHandle = new("TextButton", {
        Name = "ResizeHandle", BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
        AutoButtonColor = false, AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -5, 1, -5), Size = UDim2.fromOffset(18, 18), ZIndex = 20,
    }, MainFrame)
    for _, d in ipairs({ 3, 6, 9 }) do
        local ln = new("Frame", {
            BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -45, ZIndex = 21,
            Position = UDim2.fromOffset(17 - d, 17 - d),
            Size = UDim2.fromOffset(math.min(math.floor(d * 2.83), 17), 1),
        }, resizeHandle)
        bind(ln, "BackgroundColor3", "accent")
    end
    resizeHandle.InputBegan:Connect(function(input)
        if State.Resizable and input.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = { kind = "resize", startMouse = UserInputService:GetMouseLocation(), startSize = MainFrame.AbsoluteSize }
        end
    end)
end

-- eventos globais: arrastar janela, redimensionar e sliders
track(UserInputService.InputChanged:Connect(function(input)
    if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local m = UserInputService:GetMouseLocation()
    if drag.kind == "move" then
        local d = m - drag.startMouse
        local p = drag.startPos
        drag.target.Position = UDim2.new(p.X.Scale, p.X.Offset + d.X, p.Y.Scale, p.Y.Offset + d.Y)
    elseif drag.kind == "resize" then
        local d = m - drag.startMouse
        local s = uiScale.Scale
        MainFrame.Size = UDim2.fromOffset(
            math.clamp((drag.startSize.X + d.X) / s, MIN_W, MAX_W),
            math.clamp((drag.startSize.Y + d.Y) / s, MIN_H, MAX_H)
        )
    elseif drag.kind == "slider" then
        local t = drag.track
        if t.AbsoluteSize.X > 0 then
            drag.set((m.X - t.AbsolutePosition.X) / t.AbsoluteSize.X)
        end
    end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then drag = nil end
end))

------------------------------------------------------------------
-- GUI: paineis e linhas
------------------------------------------------------------------
local toggles = {}
local onChange = {}
local updateHotkeys
local setToggle
local uiRefs = {}
local cursorPreview -- ImageLabel da aba SET (a imagem entra quando a seta carrega)
local cursorStatus  -- rotulo da aba INFO

local function addRow(list, inst)
    inst.LayoutOrder = #list:GetChildren()
    inst.Parent = list
end

local function makePanel(parent, isLeft, title)
    local p = new("Frame", {
        BorderSizePixel = 0,
        Position = isLeft and UDim2.new(0, 0, 0, 0) or UDim2.new(0.5, 5, 0, 0),
        Size = UDim2.new(0.5, -5, 1, 0),
    }, parent)
    bind(p, "BackgroundColor3", "panel")
    stroke(p, "panelBorder")
    table.insert(opacityTargets, p)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 13), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 13), PaddingRight = UDim.new(0, 13),
    }, p)
    text(p, title, { bold = true, sizeU = UDim2.new(1, 0, 0, 18) })
    local ln = new("Frame", {
        BorderSizePixel = 0, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 1),
    }, p)
    bind(ln, "BackgroundColor3", "line")
    local list = new("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40),
    }, p)
    bind(list, "ScrollBarImageColor3", "boxBorder")
    new("UIPadding", { PaddingRight = UDim.new(0, 8) }, list)
    local layout = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }, list)
    table.insert(rowLayouts, layout)
    return list
end

local function toggleRow(list, str, key)
    local row = new("TextButton", {
        BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
        Size = UDim2.new(1, 0, 0, 20),
    })
    local box = new("Frame", {
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(11, 11),
    }, row)
    stroke(box, "boxBorder")
    text(row, str, { pos = UDim2.fromOffset(24, 0), sizeU = UDim2.new(1, -24, 1, 0) })
    toggles[key] = { box = box }
    row.MouseButton1Click:Connect(function() setToggle(key, not State[key]) end)
    addRow(list, row)
end

local function labelRow(list, str, props)
    props = props or {}
    props.sizeU = UDim2.new(1, 0, 0, props.h or 16)
    local l = text(nil, str, props)
    addRow(list, l)
    return l
end

local function noteRow(list, str)
    local l = text(nil, str, { size = 12, color = "muted", sizeU = UDim2.new(1, 0, 0, 0) })
    l.TextWrapped = true
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.AutomaticSize = Enum.AutomaticSize.Y
    addRow(list, l)
    return l
end

local function hrRow(list)
    local row = new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 13) })
    local ln = new("Frame", {
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 1),
    }, row)
    bind(ln, "BackgroundColor3", "line")
    addRow(list, row)
end

-- linha "chave ........ valor"
local function kvRow(list, key, value, valueKey)
    local row = new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 18) })
    text(row, key, { color = "muted", size = 12, sizeU = UDim2.new(0.5, 0, 1, 0) })
    local v = text(row, value, {
        color = valueKey or "text", size = 12, align = Enum.TextXAlignment.Right,
        pos = UDim2.new(0.5, 0, 0, 0), sizeU = UDim2.new(0.5, 0, 1, 0),
    })
    addRow(list, row)
    return v
end

local function keyRow(list, key, desc)
    local row = new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 18) })
    text(row, key, { bold = true, color = "accent", sizeU = UDim2.fromOffset(30, 18) })
    text(row, desc, { pos = UDim2.fromOffset(34, 0), sizeU = UDim2.new(1, -34, 1, 0) })
    addRow(list, row)
end

local function createSlider(list, min, max, getValue, onValue)
    local holder = new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 40) })
    local hit = new("TextButton", {
        BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
        Size = UDim2.new(1, 0, 0, 20),
    }, holder)
    local trackF = new("Frame", {
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -8, 0, 6),
    }, hit)
    bind(trackF, "BackgroundColor3", "box")
    stroke(trackF, "boxBorder")
    local fill = new("Frame", { BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0) }, trackF)
    bind(fill, "BackgroundColor3", "accent")
    local thumb = new("Frame", {
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2,
        Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(8, 14),
    }, trackF)
    bind(thumb, "BackgroundColor3", "accent")
    local valueLbl = text(holder, "", {
        color = "accent", align = Enum.TextXAlignment.Center,
        pos = UDim2.fromOffset(0, 22), sizeU = UDim2.new(1, 0, 0, 16),
    })

    local function render()
        local v = getValue()
        local a = (v - min) / (max - min)
        fill.Size = UDim2.new(a, 0, 1, 0)
        thumb.Position = UDim2.new(a, 0, 0.5, 0)
        valueLbl.Text = v .. "%"
    end
    local function setAlpha(a)
        local v = math.clamp(math.floor(min + math.clamp(a, 0, 1) * (max - min) + 0.5), min, max)
        if v ~= getValue() then
            onValue(v)
            render()
        end
    end
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = { kind = "slider", track = trackF, set = setAlpha }
            local m = UserInputService:GetMouseLocation()
            if trackF.AbsoluteSize.X > 0 then
                setAlpha((m.X - trackF.AbsolutePosition.X) / trackF.AbsoluteSize.X)
            end
        end
    end)
    addRow(list, holder)
    render()
    return render
end

-- "select": clique para ir para a proxima opcao
local function createSelect(list, options, getIndex, onPick)
    local btn = new("TextButton", {
        BorderSizePixel = 0, AutoButtonColor = false, Text = "",
        Size = UDim2.new(1, 0, 0, 28),
    })
    bind(btn, "BackgroundColor3", "field")
    stroke(btn, "fieldBorder")
    local lbl = text(btn, "", { pos = UDim2.fromOffset(8, 0), sizeU = UDim2.new(1, -30, 1, 0) })
    text(btn, "v", { color = "muted", size = 12, align = Enum.TextXAlignment.Right, sizeU = UDim2.new(1, -8, 1, 0) })
    local function render() lbl.Text = options[getIndex()] end
    btn.MouseButton1Click:Connect(function()
        onPick(getIndex() % #options + 1)
        render()
    end)
    addRow(list, btn)
    render()
    return render
end

local function createButton(list, str, onClick)
    local btn = new("TextButton", {
        BorderSizePixel = 0, AutoButtonColor = false, Font = FONT, TextSize = 13, Text = str,
        Size = UDim2.new(1, 0, 0, 34),
    })
    bind(btn, "BackgroundColor3", "field")
    bind(btn, "TextColor3", "text")
    stroke(btn, "fieldBorder")
    btn.MouseEnter:Connect(function() btn.TextColor3 = palette.accent end)
    btn.MouseLeave:Connect(function() btn.TextColor3 = palette.text end)
    btn.MouseButton1Click:Connect(onClick)
    addRow(list, btn)
    return btn
end

------------------------------------------------------------------
-- GUI: configuracoes (aplicar tema, escala, opacidade, cursor...)
------------------------------------------------------------------
local function applyOpacity()
    local t = 1 - Settings.opacity / 100
    for _, o in ipairs(opacityTargets) do o.BackgroundTransparency = t end
end

local function applyCompact()
    local pad = UDim.new(0, State.Compact and 5 or 12)
    for _, l in ipairs(rowLayouts) do l.Padding = pad end
end

local function cursorTint()
    if Settings.cursorStyle == 2 then return palette.accent end
    if Settings.cursorStyle == 3 then return Color3.fromRGB(70, 70, 70) end
    return Color3.new(1, 1, 1)
end

local function applyCursorStyle()
    local c = cursorTint()
    if cursorPreview then cursorPreview.ImageColor3 = c end
    if capture.cursorImage then capture.cursorImage.ImageColor3 = c end
end
table.insert(paletteHooks, applyCursorStyle)

local function refreshToggle(key)
    local t = toggles[key]
    if t then t.box.BackgroundColor3 = State[key] and palette.accent or palette.box end
end
table.insert(paletteHooks, function()
    for key in pairs(toggles) do refreshToggle(key) end
end)

local function resetSettings()
    Settings.theme, Settings.scale, Settings.opacity = 1, 100, 100
    Settings.accent, Settings.cursorStyle = 1, 1
    setToggle("Watermark", true)
    setToggle("CustomCursor", true)
    setToggle("Compact", false)
    setToggle("Resizable", true)
    uiScale.Scale = 1
    applyOpacity()
    applyPalette()
    for _, refresh in pairs(uiRefs) do pcall(refresh) end
end

------------------------------------------------------------------
-- GUI: paginas
------------------------------------------------------------------
local pages = {}
local function buildPage(leftTitle, rightTitle)
    local f = new("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false,
    }, panelsHolder)
    table.insert(pages, f)
    return makePanel(f, true, leftTitle), makePanel(f, false, rightTitle)
end

local TABS = {
    { "✥", "Movement" }, { "◎", "Visuals" }, { "☼", "World" },
    { "⚙", "Settings" }, { "♙", "Avatar" }, { "▣", "Info" },
}

-- 1. MOVE
do
    local left, right = buildPage("Movement", "Hotkeys")
    toggleRow(left, "Auto Farm 100m", "FlyFarm")
    toggleRow(left, "Speed 300 (X)", "Speed")
    toggleRow(left, "Fly (E)", "Fly")
    toggleRow(left, "Noclip", "Noclip")
    keyRow(right, "B", "open / close menu")
    keyRow(right, "X", "speed 300")
    keyRow(right, "E", "fly")
    hrRow(right)
    noteRow(right, "With the menu open, the character controls are paused and the mouse is free.")
end

-- 2. ESP
do
    local left, right = buildPage("ESP", "Legend")
    toggleRow(left, "ESP Players", "Players")
    toggleRow(left, "ESP Bots", "Bots")
    labelRow(right, "Players", { raw = Color3.fromRGB(80, 220, 255) })
    labelRow(right, "Bots", { raw = Color3.fromRGB(255, 80, 80) })
    hrRow(right)
    noteRow(right, "Shows name and distance in meters.")
end

-- 3. WORLD
do
    local left, right = buildPage("Performance", "Misc")
    toggleRow(left, "Fix Lag / Light Boost", "LightBoost")
    noteRow(left, "Lowers shadows, textures and particles. Everything is restored when turned off.")
    toggleRow(right, "Anti-AFK", "AntiAFK")
    noteRow(right, "Prevents the idle kick.")
end

-- 4. SETTINGS
do
    local left, right = buildPage("General", "Customization")
    toggleRow(left, "Watermark", "Watermark")
    toggleRow(left, "Custom cursor", "CustomCursor")
    toggleRow(left, "Compact mode", "Compact")
    toggleRow(left, "Resizable menu", "Resizable")
    hrRow(left)
    labelRow(left, "Interface theme")
    uiRefs.theme = createSelect(left, THEME_NAMES, function() return Settings.theme end, function(i)
        Settings.theme = i
        applyPalette()
    end)
    labelRow(left, "Menu scale")
    uiRefs.scale = createSlider(left, 75, 150, function() return Settings.scale end, function(v)
        Settings.scale = v
        uiScale.Scale = v / 100
    end)

    labelRow(right, "Accent color")
    do
        local row = new("TextButton", {
            BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
            Size = UDim2.new(1, 0, 0, 22),
        })
        local sw = new("Frame", {
            BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(35, 14),
        }, row)
        bind(sw, "BackgroundColor3", "accent")
        local hex = text(row, "", { pos = UDim2.fromOffset(43, 0), sizeU = UDim2.new(1, -43, 1, 0) })
        local function render()
            hex.Text = accentHex() .. "  " .. ACCENTS[Settings.accent][1] .. "  (click)"
        end
        row.MouseButton1Click:Connect(function()
            Settings.accent = Settings.accent % #ACCENTS + 1
            applyPalette()
        end)
        table.insert(paletteHooks, render)
        uiRefs.accent = render
        render()
        addRow(right, row)
    end
    labelRow(right, "Menu opacity")
    uiRefs.opacity = createSlider(right, 50, 100, function() return Settings.opacity end, function(v)
        Settings.opacity = v
        applyOpacity()
    end)
    hrRow(right)
    labelRow(right, "Cursor style")
    do
        local row = new("TextButton", {
            BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
            Size = UDim2.new(1, 0, 0, 28),
        })
        cursorPreview = new("ImageLabel", {
            BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(18, 24),
        }, row)
        local name = text(row, "", { pos = UDim2.fromOffset(28, 0), sizeU = UDim2.new(1, -28, 1, 0) })
        local function render()
            name.Text = CURSOR_STYLES[Settings.cursorStyle] .. "  (click)"
            applyCursorStyle()
        end
        row.MouseButton1Click:Connect(function()
            Settings.cursorStyle = Settings.cursorStyle % #CURSOR_STYLES + 1
            render()
        end)
        uiRefs.cursor = render
        render()
        addRow(right, row)
    end
    createButton(right, "Reset settings", resetSettings)
end

-- 5. AVATAR
do
    local left, right = buildPage("Avatar", "Info")
    toggleRow(left, "Headless", "Headless")
    toggleRow(left, "Korblox", "Korblox")
    noteRow(right, "Visual only. Only you can see these changes.")
end

-- 6. INFO
do
    local left, right = buildPage("About", "Executor features")
    kvRow(left, "Version", VERSION)
    kvRow(left, "Player", LocalPlayer.Name)
    local execName = "unknown"
    if identifyexecutor then
        local okE, n = pcall(identifyexecutor)
        if okE and n then execName = tostring(n) end
    end
    kvRow(left, "Executor", execName)
    kvRow(left, "Place ID", tostring(game.PlaceId))

    local function feature(name, available)
        kvRow(right, name, available and "yes" or "no", available and "accent" or "bad")
    end
    feature("writefile", writefile ~= nil)
    feature("getcustomasset", (getcustomasset or getsynasset) ~= nil)
    feature("gethui", gethui ~= nil)
    cursorStatus = kvRow(right, "cursor image", "...", "muted")
end

------------------------------------------------------------------
-- GUI: abas (barra lateral)
------------------------------------------------------------------
local tabButtons = {}
local activeTab = 1

local function refreshTabs()
    for i, t in ipairs(tabButtons) do
        local on = i == activeTab
        t.btn.BackgroundTransparency = on and 0 or 1
        t.btn.BackgroundColor3 = palette.tabActive
        t.glyph.TextColor3 = on and palette.text or palette.muted
        t.caption.TextColor3 = on and palette.text or palette.muted
        t.under.BackgroundColor3 = palette.accent
        t.under.Visible = on
    end
end
table.insert(paletteHooks, refreshTabs)

local function selectTab(i)
    activeTab = i
    for idx, p in ipairs(pages) do p.Visible = idx == i end
    headingLabel.Text = TABS[i][2]
    refreshTabs()
end

for i, info in ipairs(TABS) do
    local btn = new("TextButton", {
        BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = i,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46),
    }, sidebar)
    local glyph = new("TextLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Font = FONT, TextSize = 20, Text = info[1],
        Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 24),
    }, btn)
    local caption = new("TextLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Font = FONT_BOLD, TextSize = 9, Text = TAB_NAMES[i],
        Position = UDim2.fromOffset(0, 29), Size = UDim2.new(1, 0, 0, 12),
    }, btn)
    local under = new("Frame", {
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2),
    }, btn)
    tabButtons[i] = { btn = btn, glyph = glyph, caption = caption, under = under }
    btn.MouseEnter:Connect(function()
        if i ~= activeTab then
            btn.BackgroundTransparency = 0
            btn.BackgroundColor3 = palette.tabHover
            glyph.TextColor3 = palette.text
        end
    end)
    btn.MouseLeave:Connect(refreshTabs)
    btn.MouseButton1Click:Connect(function() selectTab(i) end)
end

------------------------------------------------------------------
-- GUI: watermark (arrastavel)
------------------------------------------------------------------
local wmFrame, wmLabel, lastFps, refreshWatermark

do
    wmFrame = new("Frame", {
        Name = "Watermark", BorderSizePixel = 0, Active = true, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -15, 0, 15), Size = UDim2.fromOffset(330, 28),
    }, ScreenGui)
    bind(wmFrame, "BackgroundColor3", "bg")
    stroke(wmFrame, "panelBorder")
    makeRgbBar(wmFrame, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 2))
    wmLabel = new("TextLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Font = FONT, TextSize = 13, RichText = true,
        Size = UDim2.fromScale(1, 1), Text = "",
    }, wmFrame)
    bind(wmLabel, "TextColor3", "text")
    makeDraggable(wmFrame, wmFrame)

    local pingStat
    pcall(function() pingStat = Stats.Network.ServerStatsItem["Data Ping"] end)
    lastFps = 0
    function refreshWatermark()
        if not State.Watermark then return end
        local ping = 0
        if pingStat then
            pcall(function() ping = math.round(pingStat:GetValue()) end)
        end
        wmLabel.Text = string.format(
            '<font color="%s">%s</font> | %d fps | %d ms | %s',
            accentHex(), LocalPlayer.Name, lastFps, ping, os.date("%H:%M")
        )
        wmFrame.Size = UDim2.fromOffset(math.max(200, wmLabel.TextBounds.X + 24), 28)
    end
    table.insert(paletteHooks, refreshWatermark)
    refreshWatermark()
end

------------------------------------------------------------------
-- GUI: overlay de hotkeys (arrastavel)
------------------------------------------------------------------
do
    local hotkeys = new("Frame", {
        Name = "Hotkeys", BorderSizePixel = 0, Active = true,
        Position = UDim2.fromOffset(20, 180), Size = UDim2.fromOffset(195, 54),
    }, ScreenGui)
    bind(hotkeys, "BackgroundColor3", "bg")
    stroke(hotkeys, "panelBorder")
    makeRgbBar(hotkeys, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 2))
    text(hotkeys, "hotkeys", { align = Enum.TextXAlignment.Center, pos = UDim2.fromOffset(0, 5), sizeU = UDim2.new(1, 0, 0, 20) })
    local hotLine = new("Frame", {
        BorderSizePixel = 0, Position = UDim2.fromOffset(5, 26), Size = UDim2.new(1, -10, 0, 1),
    }, hotkeys)
    bind(hotLine, "BackgroundColor3", "line")
    makeDraggable(hotkeys, hotkeys)

    local hotItems = { { "Speed Hack", "Speed" }, { "Fly", "Fly" } }
    local hotEntries = {}
    for i, item in ipairs(hotItems) do
        local line = new("Frame", {
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(5, 30), Size = UDim2.new(1, -10, 0, 20),
        }, hotkeys)
        text(line, item[1], { pos = UDim2.fromOffset(3, 0), sizeU = UDim2.fromOffset(100, 20) })
        text(line, "[toggled]", { color = "accent", pos = UDim2.fromOffset(105, 0), sizeU = UDim2.fromOffset(77, 20) })
        hotEntries[i] = line
    end
    local hotEmpty = text(hotkeys, "No active hotkeys", {
        color = "muted", align = Enum.TextXAlignment.Center,
        pos = UDim2.fromOffset(0, 30), sizeU = UDim2.new(1, 0, 0, 20),
    })

    function updateHotkeys()
        local count = 0
        for i, line in ipairs(hotEntries) do
            local on = State[hotItems[i][2]]
            line.Visible = on
            if on then
                line.Position = UDim2.fromOffset(5, 30 + count * 20)
                count = count + 1
            end
        end
        hotEmpty.Visible = count == 0
        hotkeys.Size = UDim2.fromOffset(195, 34 + math.max(1, count) * 20)
    end
end

------------------------------------------------------------------
-- Toggles (liga/desliga) e reacoes
------------------------------------------------------------------
function setToggle(key, value)
    State[key] = value
    refreshToggle(key)
    -- Fly e Auto Farm nao rodam juntos
    if value and key == "Fly" and State.FlyFarm then setToggle("FlyFarm", false) end
    if value and key == "FlyFarm" and State.Fly then setToggle("Fly", false) end
    if onChange[key] then pcall(onChange[key], value) end
    if updateHotkeys then updateHotkeys() end
end

onChange.Watermark = function(on)
    wmFrame.Visible = on
    if on then refreshWatermark() end
end
onChange.Compact = applyCompact
onChange.Resizable = function(on)
    resizeHandle.Visible = on
    if not on and drag and drag.kind == "resize" then drag = nil end
end
-- (Headless, Korblox, LightBoost e Bots sao ligados mais abaixo, junto das funcoes)

for key in pairs(toggles) do refreshToggle(key) end
applyCompact()
applyOpacity()
applyCursorStyle()
selectTab(1)
updateHotkeys()

local function setMenuVisible(visible)
    MainFrame.Visible = visible
    if capture.set then capture.set(visible) end
end


------------------------------------------------------------------
-- Funcoes ligadas aos botoes
------------------------------------------------------------------
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

------------------------------------------------------------------
-- LOOPS
------------------------------------------------------------------
local fpsFrames, fpsElapsed = 0, 0
local espElapsed = 0
local ESP_INTERVAL = 1 / 15 -- o ESP atualiza ~15x por segundo (nao precisa de todo frame)

-- Visual: FPS, watermark e ESP
track(RunService.RenderStepped:Connect(function(dt)
    fpsFrames = fpsFrames + 1
    fpsElapsed = fpsElapsed + dt
    if fpsElapsed >= 0.5 then
        lastFps = math.round(fpsFrames / fpsElapsed)
        fpsFrames, fpsElapsed = 0, 0
        FpsLabel.Text = lastFps .. " FPS"
        refreshWatermark()
    end

    if State.Players or State.Bots or next(espGuis) then
        espElapsed = espElapsed + dt
        if espElapsed >= ESP_INTERVAL then
            espElapsed = 0
            updateEsp()
        end
    end
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
            if not UserInputService:GetFocusedTextBox() and not capture.active then
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
        setMenuVisible(not MainFrame.Visible)
    elseif input.KeyCode == Enum.KeyCode.X then
        setToggle("Speed", not State.Speed)
    elseif input.KeyCode == Enum.KeyCode.E then
        setToggle("Fly", not State.Fly)
    end
end))

------------------------------------------------------------------
-- INPUT CAPTURE
-- Menu aberto: cursor livre (com a seta propria), interface interativa
-- e controles do personagem suspensos.
-- Menu fechado: cursor e controles voltam como estavam.
-- Roda isolado (task.spawn + pcall): se algo aqui falhar ou travar,
-- o resto do script (menu, B, RGB, watermark...) continua normal.
------------------------------------------------------------------
task.spawn(function()
    local ok, err = pcall(function()
        local ContextActionService = cloneref(game:GetService("ContextActionService"))

        -- Seta customizada (PNG 48x60 gerado do SVG, embutido em base64)
        local CURSOR_B64 = "iVBORw0KGgoAAAANSUhEUgAAADAAAAA8CAYAAAAgwDn8AAAGtElEQVR4AexaW0icRxQ+G2MwppFAxEjyIKQVUkPaWshDbKMWQ/UhNsX0KaW+NBBoQy9IkpI0Zm0TmtSmlyR9si8tpKUXfRCkWLxV8VJRqdqqBRVEBKvFWmlBoWi/b9iZjuu/6+6/u65Cwvn+OXP+mfnPt3M5M2O2yRb/ZxN4YitysQm8AwLVwB5gy4hNgE6X4DEM5AJbQmwCKz6P05H+CHwEbHqxCfg7+wYM/cCjwKYVm4DuAdvZx5AZAt4ENqXYBDzaw76+Pjl69KjOMv0QDw4rDi+om0dsAsarjIwM6ezslIqKCtm+fbu2c2JzgnOia1vcU5uA6YGVlRVJSEiQ8vJy6e7uloMHD2pHucRyqf0ChoeAuItNwNGZ7OxsGRwclLNnz9rvX0LmFyAHiKusS4DeJScnS1VVldTW1srevXtpIjLwaAPeAxKBuEhIBLRnxcXFMjQ0JAUFBdrE+m8h0wtkAhsudCCsj6alpUlDQ4PcvXtXdu7cqesegcKY8SrSDZWwCWjvzp8/L/39/XLkCH1XVrK5B60BSAM2RFwToHeZmZnS29srly5dkm3bTFMFeMfgV4w05mK+6vZLiYmJcvPmTWlra5MDBw7oZjjTa5H5DEgGYiYRE9Ce5eTkqAl+5swZbWL6Mh6DwKqwjnzUJGoE6FFKSorcv39fqqurhTptAKNgJ1IvkABEVaJKQHtWUlKieoO94rPR8WvQSYSEoEZHYkKArnE+cF7cunVLduzYQRPBoTQAZVVYR961hEEg/G9wZbp48aL09PQIVyxfC7uQVgGc5JzsUN1LTAlotxgrBgYGhLFD25BymeVyWwTdtWwIAXqXlJSkojejOKM5bQAD3vdIPwWSgLBlwwhoz7iP4n6K+yptQ/oKwLmRjTQs2XAC9I47Wu5sucPdtYtTglbhZvAnaJeBkP0KuSAajbrwjMG5wTOHr3Fuy29A5zad23WowSWuBOgaT3s89fH0x1MgbQAPShxSpdCDiiMBj8ecLoNWDvRyampKvF5vyLh+/bp4PB45ceKE3WQKMp8D3wJ7AEexCZhrFY8nMgIMYnV1depSgBcDoaK+vt7JyRdg/BVYxQ55JTYB4/Xy8rJ6Gcnjzp07kVT3r7sfhh8A3haasI682ARMDzCC8mUw8KDf2toasMixY8fk1KlT9nseOytgcAtePv+F+s8BRmwCIffAyMiI5Ofnq4OMaclBqaysVNczvldcJtktXuQjwXeob8QmEFIPDA8PS25urszNzUlXV5c6H5vW/BTuf86dO6etnJTckep8VFKbwLoN0vm8vDyZnZ01Za9dC+4TJ/Du3bt1+degPAxETWwCQYcQh42/8/Sio6NDGhsbqToiNTXVf6h94FjQpdEmEHAIOfzyo/je24CS9XqhrKxM9u/nQqKKP4/n00BUxCbg2AP6l5+ZmdEfHIdCB3gjNwZd2tvbpampiaojuBO9cYM7BPP6E6NFqNgE1jQ1OjqqJqw15n9DIYb535EyWJheuHLlCkyBpbS0VA4fPqwLPAll1ekfeVcSkACdP378uD1h6Tx/eTqvP/YNFF65qxWpubkZWWdhbLl3j/de5n0lNFdnANQzYhMwc2BsbEzo/PT0tC7IUE7n/9AGX8peYGBS2cuXuRNWquODsaOoqEi/46R4XWfcpjYB00ZhYaFYzvPOk3/c8Hdel/8aCgmqXggWnVFObt++zUSD4y5VZ9ykNgEziefn53VbP0N5BpgDgsm7+qVakXTGIc3KyrL/1sAAwajsUDI0k02Aw8Guxb0Lnf/TNgbQ2Qv8g4e0tLSoVSlAOWXm9tm62eaNNrcZ6l24D5uA6QE00g3wktZ0BfLrCTdbqgwPJ0oJ8Ni3b59/cHs/QNF1zTYBXZi3Z3SeOz9tCyXlwUPNBcYERuhglS5cuCDp6em6CIPbUzoTTmoT4CrUjsrPAn8DbsSM5/V6gSR5s2195GNLD1m1CbShViHg1nlUFW511Vzg/ogRmkYb4+PjcvLkSeG1yuTkpH7F9ZqHFZ0PObUJcH37J+SagQuaFcnr9ZpSi4uLcvXqVeEqxOOm78W/SPlHdE7iL6GHLTaBsCsHqGCiM2/heGaoqamRQ4cOCVefpaUlXY3HuceRKQNc93osCMAfKeeDYFA8ffq0TExMMEtwK/IilDyAd6NI3EusCHAuqBVpYWHB9o7D5REYXA0X1FsjsSLAD/0/AUT4H0WyYIxouKD+GoklAfYCDwncNufjy2rXijSqEksCdJQB8SsqsUKsCcTKb9PuAwLmp4iT8qAH4vTDm8/+BwAA///V08oOAAAABklEQVQDACBeyIiQMpG+AAAAAElFTkSuQmCC"
        local CURSOR_SIZE = Vector2.new(24, 30)
        local CURSOR_TIP = Vector2.new(2, 2) -- ponta da seta dentro da imagem

        local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local function b64decode(data)
            local lookup = {}
            for i = 1, #B64_CHARS do
                lookup[string.byte(B64_CHARS, i)] = i - 1
            end
            local out, n = {}, 0
            local buffer, bits = 0, 0
            for i = 1, #data do
                local v = lookup[string.byte(data, i)]
                if v then
                    buffer = buffer * 64 + v
                    bits = bits + 6
                    if bits >= 8 then
                        bits = bits - 8
                        local byte = math.floor(buffer / 2 ^ bits)
                        buffer = buffer % 2 ^ bits
                        n = n + 1
                        out[n] = string.char(byte)
                    end
                end
            end
            return table.concat(out)
        end

        local function loadCursorAsset()
            local getAsset = getcustomasset or getsynasset
            if not (writefile and getAsset) then return nil end
            local okAsset, result = pcall(function()
                writefile("MovementSense_cursor.png", b64decode(CURSOR_B64))
                return getAsset("MovementSense_cursor.png")
            end)
            if okAsset and result and result ~= "" then return result end
            return nil
        end

        -- GUI do cursor (acima de tudo, mesma origem do GetMouseLocation)
        do
            local hui = gethui and gethui()
            for _, parent in ipairs({ CoreGui, hui }) do
                if parent then
                    local old = parent:FindFirstChild("BaconCursorGui")
                    if old then old:Destroy() end
                end
            end
        end

        local CursorGui = Instance.new("ScreenGui")
        CursorGui.Name = "BaconCursorGui"
        CursorGui.ResetOnSpawn = false
        CursorGui.IgnoreGuiInset = true
        CursorGui.DisplayOrder = 2000000000
        CursorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        CursorGui.Enabled = false
        CursorGui.Parent = ScreenGui.Parent

        local cursorImage = Instance.new("ImageLabel")
        cursorImage.Name = "Cursor"
        cursorImage.BackgroundTransparency = 1
        cursorImage.Size = UDim2.fromOffset(CURSOR_SIZE.X, CURSOR_SIZE.Y)
        cursorImage.ZIndex = 100
        cursorImage.Visible = false
        cursorImage.Parent = CursorGui
        capture.cursorImage = cursorImage
        applyCursorStyle()

        local cursorAsset = loadCursorAsset()
        if cursorAsset then
            cursorImage.Image = cursorAsset
            if cursorPreview then cursorPreview.Image = cursorAsset end
        else
            warn("[MovementSense] sem writefile/getcustomasset: usando a seta padrao do sistema")
        end

        -- Botao invisivel com Modal: ajuda a soltar o mouse em jogos que travam o cursor
        local modalButton = Instance.new("TextButton")
        modalButton.Name = "MouseUnlock"
        modalButton.Size = UDim2.fromOffset(0, 0)
        modalButton.BackgroundTransparency = 1
        modalButton.Text = ""
        modalButton.Parent = MainFrame

        -- Teclas e cliques bloqueados para o jogo enquanto o menu esta aberto
        local SINK_ACTION = "MovementSenseSink"
        local sinkInputs = {
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
            Enum.KeyCode.Space, Enum.KeyCode.ButtonA,
            Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2,
            Enum.UserInputType.MouseWheel,
        }
        local function sinkInput()
            return Enum.ContextActionResult.Sink
        end

        local function getControls()
            local okC, controls = pcall(function()
                local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
                local module = scripts and scripts:FindFirstChild("PlayerModule")
                if not module then return nil end
                return require(module):GetControls()
            end)
            if okC then return controls end
            return nil
        end

        local function customCursorShown()
            return State.CustomCursor and cursorAsset ~= nil and cursorImage.IsLoaded
        end

        -- Roda varias vezes por frame para vencer scripts do jogo que travam o mouse
        local function enforce()
            if not capture.active then return end
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            if customCursorShown() then
                UserInputService.MouseIconEnabled = false
                local m = UserInputService:GetMouseLocation()
                cursorImage.Position = UDim2.fromOffset(m.X - CURSOR_TIP.X, m.Y - CURSOR_TIP.Y)
                cursorImage.Visible = true
            else
                -- seta customizada indisponivel: garante a seta padrao visivel
                UserInputService.MouseIconEnabled = true
                UserInputService.MouseIcon = ""
                cursorImage.Visible = false
            end
        end

        local function setCapture(on)
            if capture.active == on then return end
            capture.active = on

            if on then
                capture.prevBehavior = UserInputService.MouseBehavior
                capture.prevIconEnabled = UserInputService.MouseIconEnabled
                capture.prevMouseIcon = UserInputService.MouseIcon

                CursorGui.Enabled = true
                pcall(function() modalButton.Modal = true end)
                enforce()

                -- bloqueia teclas de movimento/pulo e cliques para o jogo
                pcall(function()
                    ContextActionService:BindActionAtPriority(
                        SINK_ACTION, sinkInput, false,
                        Enum.ContextActionPriority.High.Value,
                        table.unpack(sinkInputs)
                    )
                end)

                local hum = getHum()
                if hum then pcall(function() hum:Move(Vector3.zero) end) end

                -- suspende os controles padrao do Roblox (em outra thread: o require pode demorar)
                task.spawn(function()
                    local controls = getControls()
                    if controls and capture.active then
                        pcall(function() controls:Disable() end)
                        capture.controls = controls
                    end
                end)
            else
                CursorGui.Enabled = false
                cursorImage.Visible = false
                pcall(function() modalButton.Modal = false end)
                pcall(function() ContextActionService:UnbindAction(SINK_ACTION) end)

                if capture.controls then
                    pcall(function() capture.controls:Enable() end)
                    capture.controls = nil
                end

                -- cursor volta como o jogo tinha deixado (travado, se era o caso)
                pcall(function()
                    UserInputService.MouseBehavior = capture.prevBehavior or Enum.MouseBehavior.Default
                    UserInputService.MouseIconEnabled = capture.prevIconEnabled ~= false
                    UserInputService.MouseIcon = capture.prevMouseIcon or ""
                end)
            end
        end

        pcall(function() RunService:UnbindFromRenderStep("MovementSenseCapture") end)
        RunService:BindToRenderStep("MovementSenseCapture", Enum.RenderPriority.Last.Value, enforce)
        local conns = {
            RunService.RenderStepped:Connect(enforce),
            RunService.Heartbeat:Connect(enforce),
        }

        capture.set = setCapture
        capture.cleanup = function()
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            pcall(function() modalButton:Destroy() end)
            pcall(function() CursorGui:Destroy() end)
        end

        setCapture(MainFrame.Visible) -- o menu comeca aberto

        -- mostra na aba INFO se a seta customizada carregou
        task.spawn(function()
            if not cursorAsset then
                if cursorStatus then cursorStatus.Text = "unavailable"; cursorStatus.TextColor3 = palette.bad end
                return
            end
            local t0 = os.clock()
            while not cursorImage.IsLoaded and os.clock() - t0 < 4 do task.wait(0.1) end
            if cursorStatus then
                cursorStatus.Text = cursorImage.IsLoaded and "loaded" or "not loaded"
                cursorStatus.TextColor3 = cursorImage.IsLoaded and palette.accent or palette.bad
            end
        end)
        print("[MovementSense] Input Capture pronto | seta customizada:", cursorAsset ~= nil)
    end)
    if not ok then
        warn("[MovementSense] Input Capture falhou: " .. tostring(err))
    end
end)

------------------------------------------------------------------
-- CLEANUP (chamado automaticamente ao re-executar)
------------------------------------------------------------------
local cleaned = false
local function cleanup()
    if cleaned then return end
    cleaned = true
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for _, t in ipairs(rgbTweens) do pcall(function() t:Cancel() end) end
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
    pcall(function() RunService:UnbindFromRenderStep("MovementSenseCapture") end)
    if capture.set then pcall(capture.set, false) end
    if capture.cleanup then pcall(capture.cleanup) end
    ScreenGui:Destroy()
    getgenv().BaconCleanup = nil
end
getgenv().BaconCleanup = cleanup
