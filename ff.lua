getgenv().Settings = {
    Farming = {
        FarmMode = "Completion", -- VIP / Completion
        FarmRadius = 140,
        AutoCollect = true
    },

    Automation = {
        ExtraPetSlot = true,
        VendingMachines = true,
        DailyRewards = true,

        AutoTap = true,
        EquipBest = true
    },

    Analytics = {
        WSS = "",
        CurrencyTracker = false
    },

    Performance = {
        DisableRendering = false,
        DowngradedQuality = true,
    }
}

local Settings = getgenv().Settings

repeat task.wait() until game:IsLoaded()

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local tdrender = not Settings.Performance.DisableRendering
RunService:Set3dRenderingEnabled(tdrender)

local _ = require(RS:WaitForChild("Library", 10):WaitForChild("Client", 10))
repeat task.wait() until _.Loaded

local LocalPlayer = game:GetService("Players").LocalPlayer
local ZONES = debug.getupvalues(_.ZoneCmds.GetMaximumZone)[2].Zones

setreadonly(table, false)

table.filter = function(t: table, pred: (any, any) -> boolean): table
    local result = {}
    for k,v in pairs(t) do
        if pred(k, v) then result[k] = v end
    end
    return result
end

table.iterableFilter = function(t: table, pred: (any, any) -> boolean): table
    return table.iterable(table.filter(t, pred))
end

table.map = function(t: table, pred: (any, any) -> any): table
    local result = {}
    for k,v in pairs(t) do
        result[k] = pred(k, v)
    end
    return result
end

table.sorted = function(t: table, pred: (any, any) -> boolean): table
    table.sort(t, pred)
    return t
end

table.keys = function(t: table): table
    local keys = {}
    for k,_ in pairs(t) do
        table.insert(keys, k)
    end
    return keys
end

table.values = function(t: table): table
    local values = {}
    for _,v in pairs(t) do
        table.insert(values, v)
    end
    return values
end

table.iterable = function(t: table, pred: (any, any) -> boolean): table
    local result = {}
    for k,v in pairs(t) do
        table.insert(result, pred and pred(k, v) or v)
    end
    return result
end

local FarmingPets = {}
function GetFarmPets()
    local pets = {}
    for id,_ in pairs(_.PetCmds.GetEquipped()) do
        if not FarmingPets[id] then
            table.insert(pets, id)
        end
    end
    return pets
end

function FarmCoin(id, pet)
    FarmingPets[id] = pet
    _.Network.Fire("Breakables_JoinPet", id, pet)
    task.wait(.08)
    _.Network.Fire("Breakables_UnjoinPet", id, pet)
    table.remove(FarmingPets, id)
end

local CanTap = true
function Tap(id)
    if CanTap then
        _.Network.Fire("Breakables_PlayerDealDamage", id)
        CanTap = false
        task.delay(0.1, function()
            CanTap = true
        end)
    end
end

function GetAllCoinModels()
    return table.iterableFilter(workspace["__THINGS"].Breakables:GetChildren(), function(_,v)
        return v:IsA("Model") and v:FindFirstChild("Hitbox", true)
    end)
end

function GetMaxZoneUpgrade(zone)
    local up = {}
    for _,v in pairs(_.UpgradeCmds.All()) do up[v.ZoneID] = v.UpgradeID end
    local zone = (zone or _.ZoneCmds.GetMaximumZone()).ZoneName
    return up[zone], zone
end

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local MAXZONE = 0
for _,z in pairs(require(RS.Library.Directory).Zones) do
    MAXZONE = math.max(MAXZONE, z.ZoneNumber)
end

local CanBuyZone = true
function TryBuyZone()
    if CanBuyZone then
        local zonenum = _.ZoneCmds.GetMaximumZone().ZoneNumber
        local rebirth = tonumber(_.RebirthCmds.Get())

        if zonenum == MAXZONE and rebirth == 2 then return end

        local bought = _.Network.Invoke("Zones_RequestPurchase", _.ZoneCmds.GetNextZone())
        if not bought then
            CanBuyZone = false
            task.delay(8, function()
                CanBuyZone = true
            end)
        end
    end
end

local CanRedeemRewards = true
function RedeemRankRewards()
    if CanRedeemRewards then
        local ranks = require(RS.Library.Util.RanksUtil).GetArray()
        local redeemed = _.Save.Get().RedeemedRankRewards
        local stars = _.Save.Get().RankStars

        local r = table.filter(
            ranks[_.RankCmds.GetMaxRank()].Rewards,
            function(k, v)
                return not table.find(table.keys(redeemed), tostring(k))
                    and stars >= v.StarsRequired
            end
        )

        CanRedeemRewards = false
        task.delay(15, function()
            CanRedeemRewards = true
        end)

        for k,_v in pairs(r) do
            _.Network.Fire("Ranks_ClaimReward", tonumber(k))
            task.wait(1)
        end
    end
end

function TryBuyNextPetSlot()
    while true do
        local nextSlot = _.Save.Get().MaxPetsEquipped - (_.Gamepasses.Owns(259437976) and 15 or 0) - 4 + 1
        if nextSlot > _.RankCmds.GetMaxPurchasableEquipSlots() or not _.ZoneCmds.Owns("Green Forest") then break end

        if not _.MachineCmds.CanUse("EquipSlotsMachine") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = ZONES["Green Forest"].ZoneFolder:FindFirstChild("EquipSlotsMachine", true).Arrow.CFrame
        end

        _.Network.Invoke("EquipSlotsMachine_RequestPurchase", nextSlot)
        task.wait(1)
    end
end

local CanBuyVending = true
function TryBuyFromVendingMachines()
    if CanBuyVending then
        for machine, stock in pairs(_.Save.Get().VendingStocks) do
            local bal = _.CurrencyCmds.Get("Coins")
            local cost = require(RS.Library.Directory.VendingMachines)[machine].CurrencyCost * stock
            if not _.MachineCmds.Owns(machine) or stock < 3 or ((cost / bal) * 100) > 5 then continue end

            while stock > 0 do
                CanBuyVending = false

                if not _.MachineCmds.CanUse(machine) then
                    local model = workspace.Map:FindFirstChild(machine, true)
                    local hrp = LocalPlayer.Character.HumanoidRootPart
                    hrp.CFrame = model.Arrow.CFrame
                end

                local toBuy = math.min(stock, 3)
                local bought = _.Network.Invoke("VendingMachines_Purchase", machine, toBuy)

                if bought then
                    stock -= toBuy
                    task.wait(1)
                end
            end
        end

        task.delay(30, function()
            CanBuyVending = true
        end)
    end
end

function GetDailyRewards()
    local rewards = {
        ["GroupRewards"] = _.Save.Get().GroupVerification,
        ["TwitterRewards"] = _.Save.Get().IsFollowingOnTwitter,
        ["VIPRewards"] = _.Gamepasses.Owns(257811346),
        ["SmallDailyDiamonds"] = _.ZoneCmds.Owns("Castle"),
        ["DailyPotions"] = _.ZoneCmds.Owns("Jungle"),
        ["DailyEnchants"] = _.ZoneCmds.Owns("Coral Reef"),
        ["DailyItems"] = _.ZoneCmds.Owns("Palm Beach"),
        ["MediumDailyDiamonds"] = _.ZoneCmds.Owns("Red Desert")
    }

    for k, v in pairs(rewards) do
        local rm = require(RS["__DIRECTORY"].TimedRewards['TimedReward | ' .. k])
        if v and os.time() - (_.Save.Get().TimedRewardTimestamps[k] or os.time()) > rm.Cooldown then
            local model = workspace.Map:FindFirstChild(k, true)
            local hrp = LocalPlayer.Character.HumanoidRootPart
            hrp.CFrame = model.Pad.CFrame + Vector3.new(0, 3, 0)
            task.wait(1)
            _.Network.Invoke("DailyRewards_Redeem", k)
        end
    end
end

function GetBestOfEnchant(enchant)
    local equipped = {}
    for _,v in pairs(_.Save.Get().EquippedEnchants) do table.insert(equipped, v) end

    local enchants = {}
    for k, v in pairs(_.Save.Get().Inventory.Enchant) do
        if v.id:lower() == enchant:lower() then
            setreadonly(v, false)
            v.uid = k
            table.insert(enchants, v)
        end
    end

    table.sort(enchants, function(a, b) return tonumber(a.tn) > tonumber(b.tn) end)

    return not table.find(equipped, enchants[1].uid) and enchants[1].uid or nil
end

function EatAllFruit(fruit)
    for k,v in pairs(_.Save.Get().Inventory.Fruit) do
        if v.id == fruit then
            while #(_.FruitCmds.GetActiveFruits()[fruit] or {}) < 20 do
                _.FruitCmds.Consume(k)
                task.wait(.1)
            end
            break
        end
    end
end

if not getgenv().patched then
    getgenv().patched = true

    local Blunder = require(RS:FindFirstChild("BlunderList", true))
    local OldGet = Blunder.getAndClear

    setreadonly(Blunder, false)
    Blunder.getAndClear = function(...)
        local Packet = ...
        for i,v in next, Packet.list do
            if v.message ~= "PING" then
                table.remove(Packet.list, i)
            end
        end
        return OldGet(Packet)
    end

    local Audio = require(RS:WaitForChild("Library", 10):WaitForChild("Audio", 10))
    hookfunction(Audio.Play, function(...)
        return {
            Play = function() end,
            Stop = function() end,
            IsPlaying = function() return false end
        }
    end)
end

LocalPlayer.PlayerScripts.Scripts.Core["Idle Tracking"].Enabled = false
for _,v in pairs(getconnections(LocalPlayer.Idled)) do
    if v["Disable"] then
        v["Disable"](v)
    elseif v["Disconnect"] then
        v["Disconnect"](v)
    end
end

if Settings.Performance.DisableRendering then
    local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
    local btn = Instance.new("TextButton", ScreenGui)

    btn.BackgroundColor3 = Color3.fromRGB(18, 21, 28)
    btn.BorderSizePixel = 0
    btn.Text = "3D Render"
    btn.TextColor3 = Color3.new(255, 255, 255)
    btn.TextScaled = true
    btn.Size = UDim2.new(0, 150, 0, 50)
    btn.Position = UDim2.new(0.3, 0, 0.3, 0)
    btn.MouseButton1Click:Connect(function()
        tdrender = not tdrender
        RunService:Set3dRenderingEnabled(tdrender)
    end)
end

if Settings.Performance.DowngradedQuality then
    local lighting = game.Lighting
    lighting.GlobalShadows = false
    lighting.FogStart = 0
    lighting.FogEnd = 0
    lighting.Brightness = 0
    settings().Rendering.QualityLevel = "Level01"

    for _,v in pairs(game:GetDescendants()) do
        pcall(function()
            if v:IsA("Part") or v:IsA("UnionOperation") or v:IsA("CornerWedgePart") or v:IsA("TrussPart") then
                v.Material = "Plastic"
                v.Reflectance = 0
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                v.Lifetime = NumberRange.new(0)
            elseif v:IsA("Explosion") then
                v.BlastPressure = 1
                v.BlastRadius = 1
            elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") or v:IsA("Sparkles") then
                v.Enabled = false
            elseif v:IsA("MeshPart") then
                v.Material = "Plastic"
                v.Reflectance = 0
            end
        end)
    end

    for _,e in pairs(lighting:GetChildren()) do
        if e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") or e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") then
            e.Enabled = false
        end
    end
end

function CanFarmVIP()
    return Settings.Farming.FarmMode:lower() == "vip" and _.Gamepasses.Owns(257811346)
end
if CanFarmVIP() then
    coroutine.wrap(function()
        if not Settings.Analytics.WSS or not Settings.Analytics.CurrencyTracker then return end

        local Get = _.CurrencyCmds.Get

        local success, ws = false, nil
        local function ConnectWS()
            repeat
                success, ws = pcall(WebSocket.connect, Settings.Analytics.WSS)
                if not success then task.wait(10) end
            until success
        end

        local last_amt = Get("Diamonds")
        while task.wait(10) do
            if not ws then ConnectWS() end

            local dims = Get("Diamonds")
            local d = dims - last_amt
            last_amt = Get("Diamonds")

            if d <= 0 then continue end
                
            ws:Send(HttpService:JSONEncode({
                id = LocalPlayer.UserId,
                username = LocalPlayer.Name,
                currency = "diamonds",
                amount = d
            }))
        end
    end)()
end

if Settings.Farming.AutoCollect then
    coroutine.wrap(function()
        while task.wait(.3) do
            --for _i,v in pairs(workspace["__THINGS"].Orbs:GetChildren()) do
            --    _.Network.Fire("Orbs: Collect", { tonumber(v.Name) })
            --end
loadstring(game:HttpGet("https://raw.githubusercontent.com/Opboltejshshskidhdbd/Ps99/Opboltejshshskidhdbd-patch-1/auto%20orb%20lootbox"))()
            local success, magnet = pcall(GetBestOfEnchant, "Magnet")
            if success then
                _.EnchantCmds.Equip(magnet)
            end

            local Claim = getsenv(LocalPlayer.PlayerScripts.Scripts.Game["Lootbags Frontend"]).Claim
            for i,v in pairs(debug.getupvalue(Claim, 1)) do
                if v.readyForCollection() then Claim(i) end
            end

            for _i,v in pairs(LocalPlayer.PlayerGui._MISC.FreeGifts.Frame.ItemsFrame.Gifts:GetDescendants()) do
                if v.ClassName == "TextLabel" and v.Text == "Redeem!" then
                    _.Network.Invoke("Redeem Free Gift", tonumber(string.match(v.Parent.Name, "%d+")))
                end
            end
        end
    end)()
end

local rangeCircle = Instance.new("Part")
rangeCircle.Shape = Enum.PartType.Cylinder
rangeCircle.Material = Enum.Material.Plastic
rangeCircle.Orientation = Vector3.new(0, 0, 90)
rangeCircle.Anchored = true
rangeCircle.CanCollide = false
rangeCircle.Transparency = 0.6
rangeCircle.BrickColor = BrickColor.new("Bright blue")
rangeCircle.Parent = workspace

coroutine.wrap(function()
    while CanFarmVIP() do
        local zone = ZONES["Spawn"].ZoneFolder.INTERACT:FindFirstChild("VIP", true)
        local char = LocalPlayer.Character
        if (char.HumanoidRootPart.Position - zone.Position).magnitude > 5 then
            char.HumanoidRootPart.CFrame = zone.CFrame
        end
        task.wait(1)
    end
end)()

coroutine.wrap(function()
    local pets = {}
    while task.wait(.1) do
        local plr_pos = LocalPlayer.Character.HumanoidRootPart.Position
        local radius = Settings.Farming.FarmRadius or 50

        rangeCircle.Size = Vector3.new(0.1, radius * 2, radius * 2)
        rangeCircle.Position = plr_pos - Vector3.new(0, 2, 0)

        local function GetMag(v)
            return (plr_pos - v:FindFirstChild("Hitbox", true).Position).magnitude
        end

        local coins = table.iterable(table.map(
            table.sorted(
                table.iterableFilter(GetAllCoinModels(), function(_,v) return GetMag(v) <= radius end),
                function(a, b) return GetMag(a) < GetMag(b) end
            ),
            function(_,v) return v.Name end
        ))

        if Settings.Automation.ExtraPetSlot then pcall(TryBuyNextPetSlot) end
        if Settings.Automation.VendingMachines then pcall(TryBuyFromVendingMachines) end
        if Settings.Automation.DailyRewards then pcall(GetDailyRewards) end
        pcall(task.spawn, RedeemRankRewards)

        if CanFarmVIP() then -- vip autofarm
            pcall(EatAllFruit, "Orange")

            for _i,v in pairs(coins) do
                if #pets == 0 then pets = GetFarmPets() end
                local pet = pets[1]
                table.remove(pets, 1)
                task.spawn(_.Network.Fire, "Breakables_JoinPet", v, pet)
                task.spawn(Tap, v)
                task.wait(.05)
            end
        else -- completion autofarm
            for _,p in pairs(GetFarmPets()) do
                if #coins == 0 then break end
                local coin = coins[1]
                table.remove(coins, 1)
                task.spawn(Tap, Coin)
                Tap(coin)
                FarmCoin(coin, p)
            end
        end
    end
end)()


	-- Assuming you have a folder where zones are added as children
	local zonesFolder = game:GetService("Workspace").Map -- Change this to the actual path in your game
	 
	-- Function to handle new zones
	local function HandleNewZone(newZone)
	    -- Your logic for handling new zones goes here
	    print("New zone added:", newZone.Name)
	    -- Update MAXZONE
	    MAXZONE = math.max(MAXZONE, newZone.ZoneNumber)
	end
	 
	-- Listen for new zones
	zonesFolder.ChildAdded:Connect(HandleNewZone)

if Settings.Farming.FarmMode:lower() == "completion" then
    coroutine.wrap(function()
        local hrp = LocalPlayer.Character.HumanoidRootPart

        while true do
            local maxzone = _.ZoneCmds.GetMaximumZone()
            local zonenum = maxzone.ZoneNumber
            local rebirth = tonumber(_.RebirthCmds.Get())

            local up, zone = GetMaxZoneUpgrade(maxzone)
            if up ~= nil and not _.UpgradeCmds.Owns(up, zone) then
                hrp.CFrame = maxzone.ZoneFolder.INTERACT.Upgrades[up]:FindFirstChild("Pad").CFrame
                task.wait(1)
                _.UpgradeCmds.Purchase(up, zone)
                task.wait(1)
            end

            local tppart = maxzone.ZoneFolder.INTERACT["BREAK_ZONES"]["BREAK_ZONE"]
            if (hrp.Position - tppart.Position).magnitude >= 10 then
                hrp.CFrame = tppart.CFrame
            end

            if (zonenum >= 25 and rebirth == 0) or (zonenum >= 50 and rebirth == 1) then
                _.Network.Invoke("Rebirth_Request", tostring(rebirth + 1))
                task.wait(10)
            end

            pcall(TryBuyZone)

            task.wait(1)
        end
    end)()
end -- Add this line to close the "else" block

if Settings.Automation.AutoTap and _.Gamepasses.Owns(265324265) and not _.Save.Get().AutoTapper then
    _.Network.Invoke("AutoTapper_Toggle")
end

if Settings.Automation.EquipBest and _.Save.Get().FavoriteModeEnabled then
    _.Network.Fire("Pets_ToggleFavoriteMode")
    _.Save.Get().FavoriteModeEnabled = false
end
