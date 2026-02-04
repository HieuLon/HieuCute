--[[
    TITAN AI FRAMEWORK v2.0 - ARCHITECTURE SKELETON
    Part 1: Core Definitions & Interfaces
    Author: Gemini (Principal Architect)
]]

local Titan = {}
Titan.__index = Titan

--// 1. SERVICES & DEPENDENCIES //--
local Services = {
    RunService = game:GetService("RunService"),
    Players = game:GetService("Players"),
    UserInput = game:GetService("UserInputService"),
    VIM = game:GetService("VirtualInputManager")
}

--// 2. ENUMS (CHUẨN HÓA TRẠNG THÁI) //--
Titan.Enums = {
    CombatState = {
        IDLE = "IDLE",
        ENGAGING = "ENGAGING",
        DEFENDING = "DEFENDING",
        RETREATING = "RETREATING",
        EXECUTION = "EXECUTION"
    },
    EntityState = {
        NORMAL = 0,
        STUNNED = 1,
        RAGDOLL = 2,
        IFRAME = 3, -- Bất tử
        CASTING = 4
    }
}

--// 3. THE KERNEL (TRÁI TIM HỆ THỐNG) //--
-- Quản lý tất cả module con
local Kernel = {
    Modules = {},
    Events = {},
    IsRunning = false
}

function Kernel:RegisterModule(Name, ModuleTable)
    self.Modules[Name] = ModuleTable
    print("[TITAN] Module Registered:", Name)
end

function Kernel:GetModule(Name)
    return self.Modules[Name]
end

function Kernel:Start()
    self.IsRunning = true
    -- Khởi động theo thứ tự ưu tiên
    -- 1. Perception (Cảm giác)
    -- 2. Brain (Suy nghĩ)
    -- 3. Action (Hành động)
    
    for name, mod in pairs(self.Modules) do
        if mod.Init then mod:Init() end
    end
    
    -- Main Loop (Thay thế cho các vòng lặp rời rạc cũ)
    Services.RunService.Heartbeat:Connect(function(dt)
        if not self.IsRunning then return end
        
        -- Update Perception
        if self.Modules.Perception then self.Modules.Perception:Update(dt) end
        
        -- Update Brain
        if self.Modules.Brain then self.Modules.Brain:Think(dt) end
        
        -- Update Actuators
        if self.Modules.Locomotion then self.Modules.Locomotion:Update(dt) end
        if self.Modules.Combat then self.Modules.Combat:Update(dt) end
    end)
    
    print("[TITAN] KERNEL STARTED SUCCESSFULLY")
end

--// 4. ABSTRACT BASE CLASSES (LỚP CƠ SỞ) //--

-- Base Module Class
local BaseModule = {}
BaseModule.__index = BaseModule
function BaseModule.new() return setmetatable({}, BaseModule) end
function BaseModule:Init() end
function BaseModule:Update(dt) end

--// 5. GLOBAL CONFIG LOADER (Thay thế getgenv().G_Apex) //--
local Config = {
    Performance = {
        TickRate = 60, -- Hz
        ScanRate = 10 -- Hz (Cho quét diện rộng)
    },
    Combat = {
        Strategy = "AGGRESSIVE", -- AGGRESSIVE, DEFENSIVE, TROLL, HYBRID
        FlingEnabled = false, -- [cite: 88] Porting feature cũ
        EspEnabled = true     -- [cite: 124] Porting feature cũ
    }
}

--// 6. EXPORT FRAMEWORK //--
Titan.Kernel = Kernel
Titan.BaseModule = BaseModule
Titan.Config = Config

getgenv().TitanFramework = Titan 

--[[
    TITAN AI FRAMEWORK v2.0 - PART 2: CORE ENGINE
    Content: Signal Bus, Blackboard, Scheduler
]]

local Titan = getgenv().TitanFramework or {} 
local Services = {
    RunService = game:GetService("RunService")
}

--// 1. SIGNAL BUS (HỆ THẦN KINH) //--
-- Cho phép các module giao tiếp không đồng bộ
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(Callback)
    table.insert(self._listeners, Callback)
    return {
        Disconnect = function()
            for i, v in ipairs(self._listeners) do
                if v == Callback then table.remove(self._listeners, i) break end
            end
        end
    }
end

function Signal:Fire(...)
    for _, callback in ipairs(self._listeners) do
        task.spawn(callback, ...) -- Chạy trên luồng riêng để không block
    end
end

-- Global Event Hub
Titan.Events = {
    EnemySpotted = Signal.new(),    -- Khi thấy địch
    EnemyLost = Signal.new(),       -- Khi mất dấu
    HealthLow = Signal.new(),       -- Khi máu mình thấp
    AttackIncoming = Signal.new(),  -- Khi địch ra đòn (Reflex)
    RequestAttack = Signal.new()    -- Brain yêu cầu module Combat đánh
}

--// 2. BLACKBOARD (BỘ NHỚ TRUNG TÂM) //--
-- Thay thế hoàn toàn G_Apex
local Blackboard = {
    _data = {}
}

function Blackboard:Set(Key, Value)
    self._data[Key] = Value
end

function Blackboard:Get(Key, Default)
    return self._data[Key] or Default
end

-- Hỗ trợ nested path (VD: "Combat/Target")
function Blackboard:SetPath(Path, Value)
    local parts = string.split(Path, "/")
    local current = self._data
    for i = 1, #parts - 1 do
        if not current[parts[i]] then current[parts[i]] = {} end
        current = current[parts[i]]
    end
    current[parts[#parts]] = Value
end

function Blackboard:GetPath(Path, Default)
    local parts = string.split(Path, "/")
    local current = self._data
    for i = 1, #parts do
        if current[parts[i]] == nil then return Default end
        current = current[parts[i]]
    end
    return current
end

Titan.Blackboard = Blackboard

--// 3. SCHEDULER (QUẢN LÝ THỜI GIAN) //--
-- Thay thế while-wait loops
local Scheduler = {
    _tasks = {}
}

-- Đăng ký tác vụ chạy định kỳ
-- @param Name: Tên task (để quản lý)
-- @param Interval: Thời gian giữa các lần chạy (giây)
-- @param Callback: Hàm thực thi
function Scheduler:RegisterTask(Name, Interval, Callback)
    self._tasks[Name] = {
        Interval = Interval,
        LastRun = 0,
        Callback = Callback
    }
end

function Scheduler:RemoveTask(Name)
    self._tasks[Name] = nil
end

-- Hàm này sẽ được gọi bởi Kernel.Heartbeat
function Scheduler:Step(CurrentTime)
    for name, taskData in pairs(self._tasks) do
        if CurrentTime - taskData.LastRun >= taskData.Interval then
            taskData.LastRun = CurrentTime
            -- Chạy an toàn (pcall) để lỗi 1 task không sập cả AI
            local success, err = pcall(taskData.Callback)
            if not success then
                warn("[TITAN SCHEDULER] Task Failed:", name, err)
            end
        end
    end
end

Titan.Scheduler = Scheduler

--// 4. KERNEL INTEGRATION (CẬP NHẬT KERNEL) //--
-- Chúng ta cần tiêm Scheduler vào Main Loop của Kernel (đã tạo ở Part 1)

function Titan.Kernel:InjectCore()
    -- Override lại hàm Start hoặc móc vào Loop cũ
    local OriginalLoop = nil -- Giả định logic loop cũ
    
    Services.RunService.Heartbeat:Connect(function(dt)
        if not self.IsRunning then return end
        
        local Now = tick()
        
        -- 1. Chạy các tác vụ định kỳ (Quét địch, Check CD...)
        Titan.Scheduler:Step(Now)
        
        -- 2. Chạy logic từng frame (Movement, Animation)
        if self.Modules.Perception then self.Modules.Perception:Update(dt) end
        if self.Modules.Brain then self.Modules.Brain:Think(dt) end
        if self.Modules.Locomotion then self.Modules.Locomotion:Update(dt) end
        if self.Modules.Combat then self.Modules.Combat:Update(dt) end
    end)
    
    print("[TITAN] CORE ENGINE INJECTED: Events, Blackboard & Scheduler Ready.")
end

getgenv().TitanFramework = Titan
return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 3: UTILITY BRAIN
    Content: Utility AI, Action System, Scorers
]]

local Titan = getgenv().TitanFramework
local Blackboard = Titan.Blackboard
local Events = Titan.Events

--// 1. BASE ACTION CLASS (LỚP HÀNH ĐỘNG CƠ SỞ) //--
local Action = {}
Action.__index = Action

function Action.new(Name)
    return setmetatable({
        Name = Name,
        Scorers = {}, -- Danh sách các hàm chấm điểm
        Weight = 1.0  -- Trọng số ưu tiên cơ bản
    }, Action)
end

-- Thêm hàm chấm điểm cho hành động này
-- CurveFunc: Hàm trả về giá trị 0..1
function Action:AddScorer(CurveFunc)
    table.insert(self.Scorers, CurveFunc)
end

-- Tính tổng điểm tiện ích (Utility Score)
function Action:CalculateScore()
    if #self.Scorers == 0 then return 0 end
    
    local totalScore = self.Weight
    local compensation = 1 - (1 / #self.Scorers)
    
    for _, scorer in ipairs(self.Scorers) do
        local val = scorer()
        -- Logic nhân (Multiplicative): Nếu 1 điều kiện = 0, cả hành động bị hủy
        totalScore = totalScore * val
        
        -- Nếu val quá thấp, return sớm để tối ưu
        if totalScore <= 0 then return 0 end
    end
    
    return totalScore
end

function Action:Execute()
    warn("Action [", self.Name, "] execute not implemented!")
end

--// 2. THE BRAIN (BỘ NÃO) //--
local Brain = {
    Actions = {},
    CurrentAction = nil,
    ThinkRate = 0.1, -- Suy nghĩ mỗi 0.1s
    LastThink = 0
}

function Brain:RegisterAction(ActionObj)
    table.insert(self.Actions, ActionObj)
end

-- Hàm quan trọng nhất: Quyết định làm gì
function Brain:Think(dt)
    -- Giới hạn tốc độ suy nghĩ để không lag
    if tick() - self.LastThink < self.ThinkRate then return end
    self.LastThink = tick()

    local bestAction = nil
    local bestScore = -1

    -- Duyệt qua tất cả hành động khả thi
    for _, action in ipairs(self.Actions) do
        local score = action:CalculateScore()
        -- Debug dòng này nếu muốn xem AI đang nghĩ gì
        -- print(action.Name, score) 
        
        if score > bestScore then
            bestScore = score
            bestAction = action
        end
    end

    -- Nếu đổi ý định, chuyển đổi hành động
    if bestAction and bestAction ~= self.CurrentAction then
        if self.CurrentAction and self.CurrentAction.OnExit then
            self.CurrentAction:OnExit()
        end
        
        self.CurrentAction = bestAction
        -- print("[TITAN BRAIN] Switched to:", bestAction.Name, "Score:", bestScore)
        
        if self.CurrentAction.Execute then
            self.CurrentAction:Execute()
        end
    elseif bestAction then
        -- Nếu vẫn giữ hành động cũ, tiếp tục thực thi (Update)
        if self.CurrentAction.Update then
            self.CurrentAction:Update(dt)
        end
    end
end

--// 3. COMMON SCORERS (CÁC HÀM CHẤM ĐIỂM CHUẨN) //--
-- Đây là nơi biến logic cũ thành toán học

local Scorers = {}

-- Chấm điểm dựa trên khoảng cách (Gần -> Điểm cao, Xa -> Điểm thấp)
function Scorers.DistanceScore(MaxDist)
    return function()
        local target = Blackboard:Get("Combat/Target")
        local selfChar = game.Players.LocalPlayer.Character
        if not target or not selfChar then return 0 end
        
        local dist = (target.Position - selfChar.PrimaryPart.Position).Magnitude
        if dist > MaxDist then return 0 end
        return 1 - (dist / MaxDist) -- Linear Falloff
    end
end

-- Chấm điểm dựa trên HP bản thân (Máu thấp -> Điểm cao)
function Scorers.LowHealthScore(ThresholdPercent)
    return function()
        local hum = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if not hum then return 0 end
        
        local hpPercent = hum.Health / hum.MaxHealth
        if hpPercent > ThresholdPercent then return 0 end
        
        -- Càng thấp càng ưu tiên (Inverse)
        return 1 - (hpPercent / ThresholdPercent)
    end
end

-- Chấm điểm: Địch có đang bị Stun/Ragdoll không? (Dùng cho Combo)
function Scorers.TargetVulnerable()
    return function()
        local isStunned = Blackboard:Get("Target/IsStunned", false)
        return isStunned and 1.5 or 0.5 -- Boost điểm nếu địch bị stun
    end
end

--// 4. PRESET ACTIONS (CÁC HÀNH ĐỘNG CỤ THỂ) //--

-- [Action: CHASE] - Truy đuổi
local ChaseAct = Action.new("CHASE")
ChaseAct:AddScorer(function() 
    -- Luôn muốn chase nếu có Target và xa quá 5 stud
    local target = Blackboard:Get("Combat/Target")
    if not target then return 0 end
    return 0.8 
end)
function ChaseAct:Execute()
    Events.RequestMovement:Fire("CHASE")
end

-- [Action: ATTACK] - Tấn công
local AttackAct = Action.new("ATTACK")
AttackAct.Weight = 2.0 -- Ưu tiên cao hơn Chase
AttackAct:AddScorer(Scorers.DistanceScore(15)) -- Chỉ đánh khi gần < 15 stud
function AttackAct:Execute()
    Events.RequestAttack:Fire()
end
function AttackAct:Update(dt)
    -- Liên tục spam lệnh đánh khi đang trong trạng thái Attack
    Events.RequestAttack:Fire() 
end

-- [Action: RETREAT] - Bỏ chạy (Kite)
local RetreatAct = Action.new("RETREAT")
RetreatAct.Weight = 5.0 -- Ưu tiên cực cao nếu kích hoạt
RetreatAct:AddScorer(Scorers.LowHealthScore(0.3)) -- Kích hoạt khi máu < 30%
function RetreatAct:Execute()
    Events.RequestMovement:Fire("FLEE")
end

--// 5. SETUP & EXPORT //--
function Titan.Kernel:InjectBrain()
    local BrainModule = Brain
    
    -- Đăng ký các hành động vào não
    BrainModule:RegisterAction(ChaseAct)
    BrainModule:RegisterAction(AttackAct)
    BrainModule:RegisterAction(RetreatAct)
    
    self.Modules.Brain = BrainModule
    print("[TITAN] BRAIN ONLINE: Utility AI System Active.")
end

Titan.Scorers = Scorers
return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 4: PERCEPTION & MEMORY
    Content: Target Selector, State Analysis, Enemy Profiling
]]

local Titan = getgenv().TitanFramework
local Blackboard = Titan.Blackboard
local Events = Titan.Events
local Services = {
    Players = game:GetService("Players"),
    CollectionService = game:GetService("CollectionService")
}
local LocalPlayer = Services.Players.LocalPlayer

--// 1. PROFILER SYSTEM (HỆ THỐNG GHI NHỚ) //--
-- Lưu trữ dữ liệu hành vi của đối thủ
local Profiler = {
    _profiles = {}
}

function Profiler:GetProfile(Player)
    if not self._profiles[Player.UserId] then
        self._profiles[Player.UserId] = {
            TotalAttacks = 0,
            TotalBlocks = 0,
            LastSeenSkill = {},
            PlayStyle = "UNKNOWN"
        }
    end
    return self._profiles[Player.UserId]
end

function Profiler:RecordAction(Player, ActionType, SkillName)
    local profile = self:GetProfile(Player)
    
    if ActionType == "ATTACK" then
        profile.TotalAttacks = profile.TotalAttacks + 1
    elseif ActionType == "BLOCK" then
        profile.TotalBlocks = profile.TotalBlocks + 1
    elseif ActionType == "SKILL" and SkillName then
        profile.LastSeenSkill[SkillName] = tick()
    end
    
    -- Tính toán PlayStyle đơn giản
    if profile.TotalBlocks > profile.TotalAttacks * 2 then
        profile.PlayStyle = "TURTLE" -- Chuyên thủ
    elseif profile.TotalAttacks > profile.TotalBlocks * 3 then
        profile.PlayStyle = "BERSERKER" -- Chuyên công
    end
end

--// 2. PERCEPTION MODULE (HỆ THỐNG TRI GIÁC) //--
local Perception = {
    Target = nil,
    Range = 1000 -- Tầm quét tối đa
}

-- Phân tích sâu trạng thái của một nhân vật (Thay thế AnalyzeEnemyState cũ)
function Perception:AnalyzeEntity(Character)
    if not Character then return {} end
    local Humanoid = Character:FindFirstChild("Humanoid")
    if not Humanoid or Humanoid.Health <= 0 then return { Dead = true } end
    
    local State = {
        Dead = false,
        Stunned = false,
        Ragdolled = false,
        Blocking = false,
        HealthPct = Humanoid.Health / Humanoid.MaxHealth,
        Position = Character.PrimaryPart.Position
    }

    -- Detect Stun/Ragdoll dựa trên Attribute hoặc Animation (Tùy game)
    -- Đây là ví dụ logic phổ quát:
    if Character:GetAttribute("Stun") or Character:FindFirstChild("Stunned") then
        State.Stunned = true
    end
    
    -- Detect Block (Ví dụ check Animation hoặc Attribute)
    if Character:GetAttribute("Blocking") == true then 
        State.Blocking = true 
    end

    return State
end

-- Hàm tìm mục tiêu tốt nhất (Scoring System)
function Perception:ScanForTarget()
    local bestTarget = nil
    local maxScore = -math.huge
    local myPos = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart.Position

    if not myPos then return end

    for _, player in ipairs(Services.Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character.PrimaryPart then
            local hum = player.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                -- Tính điểm ưu tiên
                local dist = (player.Character.PrimaryPart.Position - myPos).Magnitude
                if dist <= self.Range then
                    local score = 0
                    
                    -- Tiêu chí 1: Khoảng cách (Gần = Tốt)
                    score = score - dist 
                    
                    -- Tiêu chí 2: Máu thấp (Dễ kill = Tốt)
                    score = score + (1 - (hum.Health / hum.MaxHealth)) * 100
                    
                    -- Tiêu chí 3: Đã từng bị mình đánh dấu (Sticky Target)
                    if self.Target == player then score = score + 50 end

                    if score > maxScore then
                        maxScore = score
                        bestTarget = player
                    end
                end
            end
        end
    end
    
    return bestTarget
end

function Perception:Update(dt)
    -- 1. Tìm mục tiêu (Không cần chạy mỗi frame, nhưng ở đây để đơn giản ta chạy luôn)
    -- Trong thực tế nên dùng Scheduler chạy 10Hz
    local newTarget = self:ScanForTarget()
    
    if newTarget ~= self.Target then
        self.Target = newTarget
        -- Báo cho toàn bộ hệ thống biết mục tiêu thay đổi
        if newTarget then
            Events.EnemySpotted:Fire(newTarget)
            print("[TITAN] New Target Locked:", newTarget.Name)
        else
            Events.EnemyLost:Fire()
        end
    end

    -- 2. Đẩy dữ liệu vào Blackboard để Brain đọc
    if self.Target and self.Target.Character then
        local state = self:AnalyzeEntity(self.Target.Character)
        local profile = Profiler:GetProfile(self.Target)
        
        Blackboard:Set("Combat/Target", self.Target)
        Blackboard:Set("Combat/TargetState", state)
        Blackboard:Set("Combat/TargetProfile", profile)
        
        -- Nếu địch đang thủ (Block), báo Brain biết
        if state.Blocking then
            Profiler:RecordAction(self.Target, "BLOCK")
        end
    else
        Blackboard:Set("Combat/Target", nil)
    end
end

--// 3. INTEGRATION //--
function Titan.Kernel:InjectPerception()
    self.Modules.Perception = Perception
    Titan.Profiler = Profiler
    print("[TITAN] PERCEPTION & MEMORY ONLINE.")
end

return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 5: COMBAT ENGINE
    Content: Skill DB, Prediction V2, Combat Loop
]]

local Titan = getgenv().TitanFramework
local Blackboard = Titan.Blackboard
local Events = Titan.Events
local Services = {
    VIM = game:GetService("VirtualInputManager"),
    RunService = game:GetService("RunService")
}

--// 1. PREDICTION MATH (TOÁN HỌC DỰ ĐOÁN) //--
local Prediction = {}

-- Dự đoán vị trí địch sau t giây
-- P: Vị trí hiện tại, V: Vận tốc hiện tại, t: Thời gian bay của skill
function Prediction:PredictPosition(Target, ProjectileSpeed, CastDelay)
    if not Target or not Target.Character then return Vector3.new(0,0,0) end
    
    local root = Target.Character.PrimaryPart
    local velocity = root.AssemblyLinearVelocity -- Vận tốc thật của Physics
    
    -- Tính khoảng cách
    local myPos = game.Players.LocalPlayer.Character.PrimaryPart.Position
    local distance = (root.Position - myPos).Magnitude
    
    -- Thời gian bay = Khoảng cách / Tốc độ + Độ trễ niệm
    local travelTime = (distance / ProjectileSpeed) + (CastDelay or 0)
    
    -- Công thức: P_future = P_current + V * t
    local futurePos = root.Position + (velocity * travelTime)
    
    -- Anti-Air logic: Nếu địch đang rơi tự do, giảm độ cao dự đoán
    if velocity.Y < -5 then
        futurePos = futurePos - Vector3.new(0, 2, 0)
    end
    
    return futurePos
end

--// 2. SKILL DATABASE (CẤU HÌNH KỸ NĂNG) //--
-- Phần này nên tách ra file config riêng, nhưng để demo ta để ở đây
local SkillDB = {
    ["MeleeSlash"] = {
        Key = Enum.KeyCode.Button1, -- Click chuột trái
        Type = "MELEE",
        Range = 8,
        Cooldown = 0.5
    },
    ["Skill_Z"] = {
        Key = Enum.KeyCode.Z,
        Type = "PROJECTILE",
        Range = 100,
        Speed = 150, -- Tốc độ bay của skill
        CastTime = 0.2,
        Cooldown = 5,
        Priority = 2 -- Ưu tiên thấp
    },
    ["Skill_X"] = {
        Key = Enum.KeyCode.X,
        Type = "INSTANT", -- Skill chọn mục tiêu/teleport
        Range = 40,
        Cooldown = 8,
        Priority = 5 -- Ưu tiên cao (Dùng để bắt đầu combo)
    }
}

--// 3. COMBAT MANAGER (QUẢN LÝ COMBAT) //--
local Combat = {
    Cooldowns = {},
    IsAttacking = false,
    LastAttackTime = 0
}

function Combat:IsOnCooldown(SkillName)
    local cdEnd = self.Cooldowns[SkillName] or 0
    return tick() < cdEnd
end

function Combat:CanCast(SkillName, TargetState, TargetDist)
    local skill = SkillDB[SkillName]
    if not skill then return false end
    
    -- 1. Check Cooldown
    if self:IsOnCooldown(SkillName) then return false end
    
    -- 2. Check Range
    if TargetDist > skill.Range then return false end
    
    -- 3. Check State (Risk Assessment)
    -- Không đánh thường vào địch đang Block/Counter
    if skill.Type == "MELEE" and (TargetState.Blocking or TargetState.Countering) then
        return false 
    end
    
    return true
end

function Combat:CastSkill(SkillName, Target)
    local skill = SkillDB[SkillName]
    if not skill then return end
    
    self.IsAttacking = true
    
    -- 1. Aiming (Nếu là skill định hướng)
    if skill.Type == "PROJECTILE" then
        local aimPos = Prediction:PredictPosition(Target, skill.Speed, skill.CastTime)
        -- Quay camera/nhân vật về hướng dự đoán
        local myRoot = game.Players.LocalPlayer.Character.PrimaryPart
        local lookCFrame = CFrame.new(myRoot.Position, Vector3.new(aimPos.X, myRoot.Position.Y, aimPos.Z))
        myRoot.CFrame = lookCFrame -- Hoặc dùng sự kiện Remote để aim
    end
    
    -- 2. Execute Input
    if skill.Key == Enum.KeyCode.Button1 then
        Services.VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.05)
        Services.VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    else
        Services.VIM:SendKeyEvent(true, skill.Key, false, game)
        task.wait(0.05)
        Services.VIM:SendKeyEvent(false, skill.Key, false, game)
    end
    
    -- 3. Set Cooldown
    self.Cooldowns[SkillName] = tick() + skill.Cooldown
    self.LastAttackTime = tick()
    
    print("[TITAN COMBAT] Casted:", SkillName)
    
    -- Reset trạng thái sau CastTime
    task.delay(skill.CastTime or 0.1, function()
        self.IsAttacking = false
    end)
end

-- Hàm này được gọi bởi Brain (thông qua Signal Bus)
function Combat:ExecuteOptimalMove()
    if self.IsAttacking then return end -- Đang đánh thì không spam
    
    local target = Blackboard:Get("Combat/Target")
    local state = Blackboard:Get("Combat/TargetState")
    
    if not target or not state then return end
    
    local myPos = game.Players.LocalPlayer.Character.PrimaryPart.Position
    local dist = (target.Character.PrimaryPart.Position - myPos).Magnitude
    
    -- Logic chọn skill: Ưu tiên skill Priority cao nhất thỏa mãn điều kiện
    local bestSkill = nil
    local maxPrio = -1
    
    for name, data in pairs(SkillDB) do
        if self:CanCast(name, state, dist) then
            if data.Priority and data.Priority > maxPrio then
                maxPrio = data.Priority
                bestSkill = name
            elseif not bestSkill then
                bestSkill = name -- Fallback
            end
        end
    end
    
    if bestSkill then
        self:CastSkill(bestSkill, target)
    end
end

--// 4. INTEGRATION //--
function Titan.Kernel:InjectCombat()
    self.Modules.Combat = Combat
    
    -- Lắng nghe lệnh từ Brain (Part 3)
    Events.RequestAttack:Connect(function()
        Combat:ExecuteOptimalMove()
    end)
    
    print("[TITAN] COMBAT SYSTEM ONLINE: Prediction V2 Ready.")
end

return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 6: ADVANCED LOCOMOTION
    Content: Pathfinding, Steering Behaviors, Anti-Stuck
]]

local Titan = getgenv().TitanFramework
local Blackboard = Titan.Blackboard
local Events = Titan.Events
local Services = {
    PathfindingService = game:GetService("PathfindingService"),
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService")
}
local LocalPlayer = Services.Players.LocalPlayer

--// 1. LOCOMOTION MODULE //--
local Locomotion = {
    CurrentMode = "IDLE", -- IDLE, CHASE, KITE, ORBIT
    Path = nil,
    Waypoints = {},
    CurrentWaypointIndex = 0,
    LastPosition = Vector3.new(0,0,0),
    StuckCount = 0,
    IsMoving = false
}

-- Cấu hình Pathfinding
local AgentParams = {
    AgentRadius = 2.0,
    AgentCanJump = true,
    WaypointSpacing = 4.0
}

--// 2. CORE MOVEMENT LOGIC //--

-- Di chuyển thông minh (Dùng MoveTo cho đường dài)
function Locomotion:PathfindTo(TargetPos)
    local myChar = LocalPlayer.Character
    if not myChar then return end
    
    -- Nếu gần đích (< 20 studs) và nhìn thấy trực tiếp -> Đi thẳng cho mượt
    local myPos = myChar.PrimaryPart.Position
    local dist = (TargetPos - myPos).Magnitude
    
    if dist < 20 then
        local human = myChar:FindFirstChild("Humanoid")
        if human then 
            human:MoveTo(TargetPos) 
            -- Reset path để tránh xung đột
            self.Path = nil
        end
        return
    end

    -- Nếu xa hoặc bị khuất -> Tính Path
    -- (Lưu ý: Chỉ tính lại path mỗi 0.5s để đỡ lag, không tính mỗi frame)
    if not self.Path or (tick() % 0.5 < 0.05) then
        local path = Services.PathfindingService:CreatePath(AgentParams)
        local success, _ = pcall(function()
            path:ComputeAsync(myPos, TargetPos)
        end)

        if success and path.Status == Enum.PathStatus.Success then
            self.Path = path
            self.Waypoints = path:GetWaypoints()
            self.CurrentWaypointIndex = 2 -- Bỏ qua điểm đầu tiên (vị trí hiện tại)
        end
    end

    -- Thực thi Path
    if self.Waypoints and self.CurrentWaypointIndex <= #self.Waypoints then
        local waypoint = self.Waypoints[self.CurrentWaypointIndex]
        local human = myChar:FindFirstChild("Humanoid")
        
        if human then
            human:MoveTo(waypoint.Position)
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                human.Jump = true
            end
            
            -- Check nếu đã tới waypoint
            if (myPos - waypoint.Position).Magnitude < 4 then
                self.CurrentWaypointIndex = self.CurrentWaypointIndex + 1
            end
        end
    end
end

-- Di chuyển chiến đấu (Combat Steering - Dùng MoveDirection)
-- Đây là phần quan trọng để "Kite" và "Orbit"
function Locomotion:CombatSteer(Target, Strategy)
    local myChar = LocalPlayer.Character
    local targetChar = Target.Character
    if not myChar or not targetChar then return end
    
    local myRoot = myChar.PrimaryPart
    local targetRoot = targetChar.PrimaryPart
    local hum = myChar:FindFirstChild("Humanoid")
    
    local toTarget = targetRoot.Position - myRoot.Position
    local dist = toTarget.Magnitude
    local dir = toTarget.Unit -- Vector hướng tới địch
    
    local moveDir = Vector3.new(0,0,0)
    
    if Strategy == "CHASE" then
        moveDir = dir
        
    elseif Strategy == "FLEE" then
        moveDir = -dir -- Chạy ngược lại
        
    elseif Strategy == "KITE" then
        local safeDist = 15 -- Khoảng cách thả diều
        if dist < safeDist - 2 then
            moveDir = -dir -- Lùi lại
        elseif dist > safeDist + 2 then
            moveDir = dir -- Tiến lên
        else
            -- Khoảng cách đẹp -> Orbit (Đi vòng tròn)
            -- Tích có hướng với trục Y (0,1,0) ra vector ngang
            moveDir = dir:Cross(Vector3.new(0, 1, 0)) 
        end
        
    elseif Strategy == "ORBIT" then
         -- Luôn đi vòng tròn
         moveDir = dir:Cross(Vector3.new(0, 1, 0)) 
    end
    
    -- Áp dụng Move (Mượt hơn MoveTo trong combat gần)
    if hum then
        hum:Move(moveDir)
        -- Luôn quay mặt về địch để đánh skill
        myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z))
    end
end

--// 3. ANTI-STUCK SYSTEM //--
function Locomotion:CheckStuck()
    local myChar = LocalPlayer.Character
    if not myChar then return end
    
    local currentPos = myChar.PrimaryPart.Position
    local delta = (currentPos - self.LastPosition).Magnitude
    
    -- Nếu đang lệnh di chuyển mà vị trí không đổi
    if self.IsMoving and delta < 0.5 then
        self.StuckCount = self.StuckCount + 1
    else
        self.StuckCount = 0 -- Reset nếu di chuyển tốt
    end
    
    self.LastPosition = currentPos
    
    -- Xử lý khi kẹt
    if self.StuckCount > 3 then -- Kẹt quá 1.5s (giả sử check mỗi 0.5s)
        print("[TITAN LOCOMOTION] Stuck Detected! Attempting unstuck...")
        local hum = myChar:FindFirstChild("Humanoid")
        if hum then
            hum.Jump = true -- Nhảy
            -- Hoặc di chuyển ngẫu nhiên
            hum:Move(Vector3.new(math.random()-0.5, 0, math.random()-0.5))
        end
        self.StuckCount = 0
    end
end

--// 4. UPDATE LOOP & INTEGRATION //--
function Locomotion:Update(dt)
    -- Lấy lệnh từ Blackboard (Do Brain đặt)
    -- Brain ở Part 3 gửi event RequestMovement, ta cần lưu trạng thái đó
end

function Titan.Kernel:InjectLocomotion()
    self.Modules.Locomotion = Locomotion
    
    -- Lắng nghe lệnh từ Brain
    Events.RequestMovement:Connect(function(Mode)
        Locomotion.CurrentMode = Mode
        Locomotion.IsMoving = (Mode ~= "IDLE")
    end)
    
    -- Đăng ký tác vụ Anti-Stuck vào Scheduler (Chạy mỗi 0.5s)
    Titan.Scheduler:RegisterTask("AntiStuck", 0.5, function()
        Locomotion:CheckStuck()
    end)
    
    -- Override Update Loop
    Services.RunService.Heartbeat:Connect(function()
        local target = Blackboard:Get("Combat/Target")
        local mode = Locomotion.CurrentMode
        
        if not target or mode == "IDLE" then 
            -- Nếu không làm gì, reset path
            return 
        end
        
        if mode == "CHASE" and target.Character then
            -- Nếu xa dùng Pathfinding, gần dùng Chase thường
            Locomotion:PathfindTo(target.Character.PrimaryPart.Position)
            
        elseif (mode == "KITE" or mode == "ORBIT" or mode == "FLEE") and target.Character then
            -- Dùng Combat Steering
            Locomotion:CombatSteer(target, mode)
        end
    end)
    
    print("[TITAN] LOCOMOTION SYSTEM ONLINE: Pathfinding & Steering Ready.")
end

return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 7: SQUAD & SWARM
    Content: Formation Math, Leader Following, Command Listener
]]

local Titan = getgenv().TitanFramework
local Blackboard = Titan.Blackboard
local Events = Titan.Events
local Services = {
    Players = game:GetService("Players"),
    TextChatService = game:GetService("TextChatService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage")
}
local LocalPlayer = Services.Players.LocalPlayer

--// 1. SQUAD MANAGER (QUẢN LÝ ĐỘI HÌNH) //--
local Squad = {
    IsLeader = false,
    LeaderName = nil, -- Tên người chơi cần follow (nếu mình là lính)
    Allies = {},      -- Danh sách đồng minh (để không đánh nhầm + giữ khoảng cách)
    CurrentFormation = "CIRCLE", -- CIRCLE, LINE, PHALANX
    MyIndex = 1       -- Số thứ tự của mình trong đội
}

-- Đăng ký đồng minh (Whitelist)
function Squad:AddAlly(PlayerName)
    if not table.find(self.Allies, PlayerName) then
        table.insert(self.Allies, PlayerName)
        print("[TITAN SQUAD] Ally Added:", PlayerName)
    end
end

function Squad:SetLeader(PlayerName)
    if PlayerName == LocalPlayer.Name then
        self.IsLeader = true
        self.LeaderName = nil
        print("[TITAN SQUAD] I am the Leader now.")
    else
        self.IsLeader = false
        self.LeaderName = PlayerName
        print("[TITAN SQUAD] Following Leader:", PlayerName)
    end
end

--// 2. FORMATION MATH (TOÁN HỌC ĐỘI HÌNH) //--
-- Tính toán vị trí đứng dựa trên số lượng đồng đội
function Squad:GetFormationPosition(TargetPos, TargetLookVector)
    if self.IsLeader then 
        -- Leader luôn tìm vị trí tốt nhất (Logic cũ)
        return nil 
    end

    local totalMembers = #self.Allies + 1 -- Tính cả bản thân
    local radius = 10 -- Bán kính vòng vây
    
    -- Tính góc đứng dựa trên Index của mình
    -- (360 độ / số thành viên) * số thứ tự của mình
    local angleStep = 360 / totalMembers
    local myAngle = math.rad(angleStep * self.MyIndex)
    
    local offsetX = math.cos(myAngle) * radius
    local offsetZ = math.sin(myAngle) * radius
    
    -- Vị trí mong muốn xung quanh mục tiêu
    local desiredPos = TargetPos + Vector3.new(offsetX, 0, offsetZ)
    
    return desiredPos
end

-- Tính vector né đồng đội (Separation)
function Squad:GetSeparationVector()
    local separationForce = Vector3.new(0,0,0)
    local count = 0
    local myPos = LocalPlayer.Character.PrimaryPart.Position
    
    for _, name in pairs(self.Allies) do
        local ally = Services.Players:FindFirstChild(name)
        if ally and ally.Character and ally.Character.PrimaryPart then
            local dist = (myPos - ally.Character.PrimaryPart.Position).Magnitude
            if dist < 5 then -- Nếu gần quá 5 stud
                -- Tạo lực đẩy ra xa
                local pushDir = (myPos - ally.Character.PrimaryPart.Position).Unit
                separationForce = separationForce + pushDir
                count = count + 1
            end
        end
    end
    
    if count > 0 then
        return separationForce * 2 -- Nhân hệ số lực đẩy
    end
    return Vector3.new(0,0,0)
end

--// 3. COMMAND SYSTEM (HỆ THỐNG RA LỆNH) //--
-- Lắng nghe chat để đồng bộ hành động
-- Cú pháp: "!titan [cmd] [arg]"
function Squad:ListenToCommands()
    Services.Players.PlayerChatted:Connect(function(type, player, message)
        -- Chỉ nghe lệnh từ Leader
        if player.Name ~= self.LeaderName and player.Name ~= LocalPlayer.Name then return end
        
        local args = string.split(message, " ")
        if args[1] == "!titan" then
            local cmd = args[2]
            
            if cmd == "attack" then
                -- !titan attack [EnemyName]
                local enemyName = args[3]
                local enemy = Services.Players:FindFirstChild(enemyName)
                if enemy then
                    Events.EnemySpotted:Fire(enemy) -- Ghi đè mục tiêu hiện tại
                    print("[TITAN SQUAD] Focus Fire on:", enemyName)
                end
                
            elseif cmd == "come" then
                -- !titan come (Gọi đệ về)
                Events.RequestMovement:Fire("CHASE")
                Titan.Blackboard:Set("Combat/Target", Services.Players:FindFirstChild(self.LeaderName))
            
            elseif cmd == "formation" then
                -- !titan formation CIRCLE
                self.CurrentFormation = args[3] or "CIRCLE"
            end
        end
    end)
end

--// 4. INTEGRATION WITH LOCOMOTION //--
-- Chúng ta cần Override lại logic di chuyển của Part 6 để thêm Separation
function Titan.Kernel:InjectSquad()
    self.Modules.Squad = Squad
    Squad:ListenToCommands()
    
    -- Hook vào Locomotion (Sửa đổi hàm Update của Part 6)
    -- Đây là kỹ thuật "Method Swizzling" hoặc "Hooking"
    local OldSteer = Titan.BaseModule.Locomotion and Titan.BaseModule.Locomotion.CombatSteer
    -- Lưu ý: Bạn cần đảm bảo Locomotion đã load trước khi chạy cái này
    
    if Titan.Modules.Locomotion then
        local Loco = Titan.Modules.Locomotion
        
        -- Override hàm tính toán hướng
        function Loco:ApplySquadSeparation(MoveDir)
            local sep = Squad:GetSeparationVector()
            return (MoveDir + sep).Unit -- Cộng vector di chuyển + vector né đồng đội
        end
        
        -- Logic: Nếu có FormationPos thì đi đến đó thay vì đi thẳng vào địch
        local OriginalPathfind = Loco.PathfindTo
        function Loco:PathfindTo(TargetPos)
            local formationPos = Squad:GetFormationPosition(TargetPos)
            if formationPos then
                -- Đi đến vị trí đội hình
                OriginalPathfind(self, formationPos)
            else
                -- Đi bình thường
                OriginalPathfind(self, TargetPos)
            end
        end
    end
    
    print("[TITAN] SQUAD MODULE ONLINE: Swarm Intelligence Active.")
end

return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 8: BOSS FRAMEWORK
    Content: Phase Manager, Mechanic Reader, Safe Zones
]]

local Titan = getgenv().TitanFramework
local Blackboard = Titan.Blackboard
local Events = Titan.Events
local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService")
}

--// 1. BOSS DATABASE (CẤU HÌNH BOSS) //--
-- Bạn cần điền ID thật của Game vào đây
local BossDatabase = {
    ["Training Dummy"] = { -- Ví dụ test
        Phases = {
            { Threshold = 0.5, Strategy = "AGGRESSIVE" }, -- Máu < 50% -> Đánh khô máu
            { Threshold = 0.1, Strategy = "EXECUTE" }     -- Máu < 10% -> Dồn skill kết liễu
        },
        Animations = {
            ["10469493270"] = { -- Ví dụ ID animation đánh mạnh
                Action = "RETREAT",
                Duration = 2.0 -- Né trong 2 giây
            },
            ["10469630000"] = { -- Ví dụ ID animation gồng block
                Action = "STOP_ATTACK",
                Duration = 3.0
            }
        }
    }
}

--// 2. BOSS MANAGER //--
local BossManager = {
    CurrentBoss = nil,
    CurrentConfig = nil,
    ActiveMechanic = nil -- Cơ chế đặc biệt đang diễn ra
}

function BossManager:IdentifyBoss(Target)
    if not Target or not Target.Parent then return end
    
    local name = Target.Name
    if BossDatabase[name] then
        self.CurrentBoss = Target
        self.CurrentConfig = BossDatabase[name]
        print("[TITAN BOSS] Boss Identified:", name)
        
        -- Hook vào Animation của Boss để đọc đòn
        self:HookAnimations(Target)
    else
        self.CurrentBoss = nil
        self.CurrentConfig = nil
    end
end

function BossManager:HookAnimations(BossChar)
    local humanoid = BossChar:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    -- Lắng nghe AnimationTrack
    humanoid.AnimationPlayed:Connect(function(track)
        if not self.CurrentConfig then return end
        
        local animId = track.Animation.AnimationId
        -- Lọc lấy ID số (thường dạng "rbxassetid://123...")
        local idNum = string.match(animId, "%d+")
        
        local mechanic = self.CurrentConfig.Animations[idNum] or self.CurrentConfig.Animations[animId]
        
        if mechanic then
            print("[TITAN BOSS] Telegraph Detected! Action:", mechanic.Action)
            self:TriggerMechanic(mechanic)
        end
    end)
end

function BossManager:TriggerMechanic(MechanicData)
    self.ActiveMechanic = MechanicData
    
    -- Ghi đè lệnh lên Blackboard để Brain (Part 3) và Locomotion (Part 6) thực thi ngay
    if MechanicData.Action == "RETREAT" then
        Events.RequestMovement:Fire("FLEE")
        -- Block luôn khả năng tấn công trong lúc né
        Titan.Modules.Combat.IsAttacking = true -- Fake trạng thái để không cast skill
        
    elseif MechanicData.Action == "STOP_ATTACK" then
        Titan.Modules.Combat.IsAttacking = true
        
    elseif MechanicData.Action == "BLOCK_NOW" then
        local VIM = game:GetService("VirtualInputManager")
        VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game) -- Giữ F
    end
    
    -- Reset sau khi hết Duration
    task.delay(MechanicData.Duration, function()
        self.ActiveMechanic = nil
        Titan.Modules.Combat.IsAttacking = false -- Mở khóa
        
        if MechanicData.Action == "BLOCK_NOW" then
             local VIM = game:GetService("VirtualInputManager")
             VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game) -- Thả F
        end
        
        -- Trả về trạng thái bình thường
        Events.RequestMovement:Fire("CHASE") 
        print("[TITAN BOSS] Mechanic Ended.")
    end)
end

function BossManager:CheckPhase()
    if not self.CurrentBoss or not self.CurrentConfig then return end
    
    local hum = self.CurrentBoss:FindFirstChild("Humanoid")
    if not hum then return end
    
    local hpPct = hum.Health / hum.MaxHealth
    
    -- Duyệt qua các phase đã config
    for _, phase in ipairs(self.CurrentConfig.Phases) do
        -- Nếu máu tụt xuống ngưỡng threshold
        if hpPct <= phase.Threshold and hpPct > (phase.Threshold - 0.1) then
            -- Chỉ áp dụng nếu chưa áp dụng (Logic đơn giản hóa)
            local currentStrategy = Blackboard:Get("Combat/Strategy")
            if currentStrategy ~= phase.Strategy then
                Blackboard:Set("Combat/Strategy", phase.Strategy)
                print("[TITAN BOSS] Phase Switch ->", phase.Strategy)
                
                -- Điều chỉnh hành vi Combat
                if phase.Strategy == "KITE_HARD" then
                    Events.RequestMovement:Fire("KITE")
                elseif phase.Strategy == "EXECUTE" then
                    Events.RequestMovement:Fire("CHASE")
                end
            end
        end
    end
end

--// 3. INTEGRATION //--
function Titan.Kernel:InjectBossFramework()
    self.Modules.BossManager = BossManager
    
    -- Lắng nghe khi Perception (Part 4) tìm thấy mục tiêu mới
    Events.EnemySpotted:Connect(function(Target)
        if Target and Target.Character then
            BossManager:IdentifyBoss(Target.Character)
        end
    end)
    
    -- Đăng ký Loop check Phase
    Titan.Scheduler:RegisterTask("BossPhaseCheck", 1.0, function()
        BossManager:CheckPhase()
    end)
    
    print("[TITAN] BOSS FRAMEWORK ONLINE: Adaptive AI Ready.")
end

return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 9: PLUGIN SYSTEM
    Content: Dynamic Loader, Hot Reload, Lifecycle Management
]]

local Titan = getgenv().TitanFramework
local Services = {
    HttpService = game:GetService("HttpService")
}

--// 1. PLUGIN MANAGER //--
local PluginManager = {
    _plugins = {},      -- Danh sách plugin đang chạy
    _configs = {}       -- Config riêng cho từng plugin
}

-- Template chuẩn cho một Plugin
local PluginTemplate = {
    Name = "Unknown",
    Version = "1.0",
    Author = "User",
    Init = function(self) end,
    Update = function(self, dt) end,
    Unload = function(self) end
}

-- Hàm tải Plugin từ Source Code (String)
function PluginManager:LoadSource(SourceCode, ConfigData)
    -- 1. Compile Code (Sandbox nhẹ)
    local func, err = loadstring(SourceCode)
    if not func then
        warn("[TITAN PLUGIN] Compile Error:", err)
        return false
    end
    
    -- 2. Execute để lấy Table trả về
    local success, pluginTable = pcall(func)
    if not success or type(pluginTable) ~= "table" then
        warn("[TITAN PLUGIN] Execution Error or Invalid Return:", pluginTable)
        return false
    end
    
    -- 3. Validate Interface
    if not pluginTable.Name then
        warn("[TITAN PLUGIN] Plugin missing Name!")
        return false
    end
    
    -- Kế thừa các hàm mặc định nếu thiếu
    setmetatable(pluginTable, {__index = PluginTemplate})
    
    -- 4. Unload phiên bản cũ nếu đang chạy (Hot Reload logic)
    if self._plugins[pluginTable.Name] then
        print("[TITAN PLUGIN] Reloading:", pluginTable.Name)
        self:Unload(pluginTable.Name)
    end
    
    -- 5. Initialize
    pluginTable.Config = ConfigData or {} -- Inject Config
    
    local initSuccess, initErr = pcall(function()
        pluginTable:Init(Titan) -- Truyền Titan Core vào để Plugin dùng
    end)
    
    if initSuccess then
        self._plugins[pluginTable.Name] = pluginTable
        print("[TITAN PLUGIN] Loaded Successfully:", pluginTable.Name)
        return true
    else
        warn("[TITAN PLUGIN] Init Failed:", pluginTable.Name, initErr)
        return false
    end
end

-- Hàm tải từ URL (Dành cho update online)
function PluginManager:LoadUrl(Url)
    print("[TITAN PLUGIN] Fetching form URL:", Url)
    local success, source = pcall(function()
        return game:HttpGet(Url)
    end)
    
    if success then
        return self:LoadSource(source)
    else
        warn("[TITAN PLUGIN] HTTP Failed:", source)
    end
end

-- Hàm gỡ bỏ Plugin (Cleanup)
function PluginManager:Unload(PluginName)
    local plugin = self._plugins[PluginName]
    if plugin then
        -- Gọi hàm dọn dẹp của Plugin
        pcall(function() plugin:Unload() end)
        self._plugins[PluginName] = nil
        print("[TITAN PLUGIN] Unloaded:", PluginName)
    end
end

-- Hàm Update chạy trong vòng lặp chính
function PluginManager:UpdateAll(dt)
    for name, plugin in pairs(self._plugins) do
        if plugin.Update then
            -- Bọc trong pcall để 1 plugin lỗi không làm crash cả hệ thống
            local success, err = pcall(function()
                plugin:Update(dt)
            end)
            if not success then
                warn("[TITAN PLUGIN] Runtime Error in", name, ":", err)
                -- Tự động unload plugin bị lỗi để bảo vệ hệ thống
                self:Unload(name)
            end
        end
    end
end

--// 2. EXAMPLE PLUGIN (VÍ DỤ MỘT FILE PLUGIN GAME CỤ THỂ) //--
-- Đây là nội dung giả lập của một file "BladeBall.lua" riêng biệt
local ExampleGamePlugin = [[
    local Plugin = {}
    Plugin.Name = "BladeBall_Logic"
    
    function Plugin:Init(Core)
        self.Core = Core
        print(">> BladeBall Plugin Initialized!")
        
        -- Cấu hình lại SkillDB của Core
        Core.Modules.Combat.SkillDB = {
            ["Block"] = { Key = Enum.KeyCode.F, Range = 20, Type = "MELEE" }
        }
        
        -- Đăng ký Event riêng
        self.Connection = Core.Events.EnemySpotted:Connect(function(Target)
            print("BladeBall Plugin detected enemy:", Target.Name)
        end)
    end
    
    function Plugin:Update(dt)
        -- Logic riêng mỗi frame (ví dụ Auto Parry)
    end
    
    function Plugin:Unload()
        print(">> BladeBall Plugin Cleaning up...")
        if self.Connection then self.Connection:Disconnect() end
        -- Reset lại config gốc nếu cần
    end
    
    return Plugin
]]

--// 3. INTEGRATION //--
function Titan.Kernel:InjectPluginSystem()
    self.Modules.PluginManager = PluginManager
    
    -- Hook vào vòng lặp chính của Kernel (đã tạo ở Part 1)
    -- Chúng ta mở rộng hàm Update của Kernel
    local oldHeartbeat = nil -- Giả sử logic cũ
    -- Thực tế ta chỉ cần thêm dòng này vào Loop trong Part 2:
    -- Titan.Modules.PluginManager:UpdateAll(dt)
    
    -- Test thử load plugin ví dụ
    PluginManager:LoadSource(ExampleGamePlugin)
    
    print("[TITAN] PLUGIN SYSTEM ONLINE: Hot-Reload Ready.")
end

-- Cập nhật lại Scheduler để chạy Plugin Update (Nếu chưa có trong Loop chính)
Titan.Scheduler:RegisterTask("PluginUpdater", 0, function() 
    -- 0 nghĩa là chạy mỗi frame, nhưng Scheduler của chúng ta ở Part 2 
    -- thiết kế cho Low Freq. Tốt nhất là gọi trực tiếp trong Heartbeat.
end)

return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 10: DEV TOOLS
    Content: Visual Debugger, Brain Inspector, Drawing API Wrapper
]]

local Titan = getgenv().TitanFramework
local Blackboard = Titan.Blackboard
local Services = {
    RunService = game:GetService("RunService"),
    Players = game:GetService("Players"),
    CoreGui = game:GetService("CoreGui")
}
local LocalPlayer = Services.Players.LocalPlayer

--// 1. DRAWING WRAPPER (AN TOÀN HÓA) //--
-- Giúp script không bị crash nếu Executor không hỗ trợ Drawing API
local DrawLib = {
    Items = {} -- Quản lý các object đã vẽ để xóa khi tắt
}

function DrawLib:Create(Type, Properties)
    if not Drawing then return nil end -- Fallback nếu không có Drawing API
    
    local item = Drawing.new(Type)
    for k, v in pairs(Properties) do
        item[k] = v
    end
    table.insert(self.Items, item)
    return item
end

function DrawLib:Clear()
    for _, item in pairs(self.Items) do
        if item.Remove then item:Remove() end
        if item.Destroy then item:Destroy() end
    end
    self.Items = {}
end

--// 2. DEV TOOLS MODULE //--
local DevTools = {
    Enabled = true,
    Visuals = {
        TargetLine = nil,
        PathPoints = {},
        PredictCircle = nil,
        StatusText = nil,
        BrainLog = nil
    }
}

function DevTools:Init()
    -- Khởi tạo các đối tượng vẽ (ẩn đi, khi update mới hiện)
    self.Visuals.TargetLine = DrawLib:Create("Line", {
        Thickness = 2, Color = Color3.fromRGB(255, 50, 50), Transparency = 1
    })
    
    self.Visuals.PredictCircle = DrawLib:Create("Circle", {
        Radius = 5, Color = Color3.fromRGB(0, 255, 255), Thickness = 2, Filled = false
    })
    
    self.Visuals.StatusText = DrawLib:Create("Text", {
        Size = 18, Center = true, Outline = true, Color = Color3.new(1,1,1),
        Position = Vector2.new(Services.Workspace.CurrentCamera.ViewportSize.X / 2, 100)
    })

    -- Brain Log (Danh sách điểm số hành động)
    self.Visuals.BrainLog = DrawLib:Create("Text", {
        Size = 14, Center = false, Outline = true, Color = Color3.fromRGB(200, 200, 200),
        Position = Vector2.new(50, 300) -- Góc trái
    })
    
    print("[TITAN] DEV TOOLS ONLINE: Debug Overlay Initialized.")
end

-- Hàm cập nhật Visualization mỗi frame render
function DevTools:UpdateRender()
    if not self.Enabled then 
        DrawLib:Clear()
        return 
    end
    
    local cam = Services.Workspace.CurrentCamera
    local myChar = LocalPlayer.Character
    local target = Blackboard:Get("Combat/Target")
    
    -- 1. Vẽ đường nối tới Target
    if myChar and target and target.Character then
        local myRoot = myChar:FindFirstChild("HumanoidRootPart")
        local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
        
        if myRoot and tRoot then
            local myPos, myVis = cam:WorldToViewportPoint(myRoot.Position)
            local tPos, tVis = cam:WorldToViewportPoint(tRoot.Position)
            
            if myVis and tVis then
                self.Visuals.TargetLine.From = Vector2.new(myPos.X, myPos.Y)
                self.Visuals.TargetLine.To = Vector2.new(tPos.X, tPos.Y)
                self.Visuals.TargetLine.Visible = true
            else
                self.Visuals.TargetLine.Visible = false
            end
        end
    else
        self.Visuals.TargetLine.Visible = false
    end
    
    -- 2. Vẽ vị trí dự đoán (Prediction Visualization)
    -- Giả sử ta lấy dữ liệu từ module Combat (Part 5)
    -- Để làm được điều này, Combat module cần expose biến `LastPredictedPos`
    local combatMod = Titan.Modules.Combat
    if combatMod and combatMod.LastPredictedPos then
        local pPos, pVis = cam:WorldToViewportPoint(combatMod.LastPredictedPos)
        if pVis then
            self.Visuals.PredictCircle.Position = Vector2.new(pPos.X, pPos.Y)
            self.Visuals.PredictCircle.Visible = true
        else
            self.Visuals.PredictCircle.Visible = false
        end
    else
        self.Visuals.PredictCircle.Visible = false
    end
    
    -- 3. Hiển thị Trạng thái & Brain Logic
    local brain = Titan.Modules.Brain
    local loco = Titan.Modules.Locomotion
    local statusStr = string.format(
        "STATE: %s | ACTION: %s | FPS: %d", 
        loco and loco.CurrentMode or "N/A",
        brain and brain.CurrentAction and brain.CurrentAction.Name or "THINKING",
        1 / Services.RunService.RenderStepped:Wait()
    )
    self.Visuals.StatusText.Text = statusStr
    
    -- 4. Hiển thị Decision Log (Tại sao chọn hành động này?)
    if brain and brain.LastScores then
        local logStr = "--- BRAIN DECISION LOG ---\n"
        -- Sắp xếp và hiển thị điểm số
        for name, score in pairs(brain.LastScores) do
            local colorCode = score > 0.5 and "[+]" or "[-]"
            logStr = logStr .. string.format("%s %s: %.2f\n", colorCode, name, score)
        end
        self.Visuals.BrainLog.Text = logStr
        self.Visuals.BrainLog.Visible = true
    end
end

--// 3. INTEGRATION WITH BRAIN //--
-- Cần quay lại Part 3 (Brain) để thêm chức năng export điểm số ra ngoài cho DevTools đọc
function Titan.Kernel:InjectDevTools()
    self.Modules.DevTools = DevTools
    DevTools:Init()
    
    -- Cập nhật Brain để lưu log (Monkey Patching)
    if self.Modules.Brain then
        local oldThink = self.Modules.Brain.Think
        self.Modules.Brain.LastScores = {} -- Bảng lưu điểm số debug
        
        -- Override hàm Think để bắt lấy điểm số
        self.Modules.Brain.Think = function(brainSelf, dt)
            -- Gọi hàm cũ
            oldThink(brainSelf, dt)
            
            -- Sau khi tính toán, lưu lại điểm số vào LastScores
            local scores = {}
            for _, action in ipairs(brainSelf.Actions) do
                -- Lưu ý: Hàm CalculateScore có thể tốn CPU nếu gọi lại lần 2
                -- Tốt nhất là sửa Part 3 để lưu score ngay lúc tính
                -- Ở đây ta gọi lại giả lập (chấp nhận tốn CPU khi Debug)
                scores[action.Name] = action:CalculateScore()
            end
            brainSelf.LastScores = scores
        end
    end
    
    -- Kết nối Render Loop (Dùng RenderStepped cho Visual mượt mà)
    Services.RunService.RenderStepped:Connect(function()
        DevTools:UpdateRender()
    end)
    
    print("[TITAN] DEV TOOLS: Visualization Active.")
end

return Titan
--[[
    TITAN AI FRAMEWORK v2.0 - PART 11: NETWORK & SERVER API
    Content: Remote Wrapper, Ping Compensation, Hybrid Executor
]]

local Titan = getgenv().TitanFramework
local Services = {
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Stats = game:GetService("Stats"),
    Players = game:GetService("Players")
}

--// 1. NETWORK UTILS (CÔNG CỤ MẠNG) //--
local Network = {
    Ping = 0,
    RemoteCache = {}, -- Cache địa chỉ Remote để không phải find nhiều lần
    Mappings = {}     -- Map từ Skill Name -> Remote + Args
}

-- Cập nhật Ping liên tục
function Network:UpdatePing()
    -- Lấy Ping thực tế (đơn vị: giây)
    -- Stats.Network.ServerStatsItem["Data Ping"]:GetValue() trả về ms
    local pingMs = Services.Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    self.Ping = pingMs / 1000
end

-- Tính toán độ trễ bù trừ (Latency Compensation)
function Network:GetLatencyFactor()
    -- Hệ số an toàn: Ping * 1.5 + FrameTime
    return (self.Ping * 1.5) + (1/60)
end

--// 2. REMOTE WRAPPER //--
-- Hàm tìm Remote an toàn
function Network:GetRemote(Path)
    if self.RemoteCache[Path] then return self.RemoteCache[Path] end
    
    local parts = string.split(Path, "/")
    local current = game
    
    for i, name in ipairs(parts) do
        if current then
            current = current:FindFirstChild(name)
        end
    end
    
    if current and (current:IsA("RemoteEvent") or current:IsA("RemoteFunction")) then
        self.RemoteCache[Path] = current
        return current
    end
    return nil
end

-- Đăng ký Mapping cho game cụ thể (Thường dùng trong Plugin Part 9)
-- SkillName: "Fireball"
-- RemotePath: "ReplicatedStorage/Remotes/SkillZ"
-- ArgPacker: Hàm đóng gói tham số
function Network:MapSkill(SkillName, RemotePath, ArgPacker)
    self.Mappings[SkillName] = {
        Path = RemotePath,
        Packer = ArgPacker
    }
end

-- Thực thi Skill (Hybrid Mode)
function Network:ExecuteSkill(SkillName, TargetPos)
    local mapping = self.Mappings[SkillName]
    
    -- CÁCH 1: REMOTE METHOD (Ưu tiên)
    if mapping then
        local remote = self:GetRemote(mapping.Path)
        if remote then
            -- Tính toán tham số
            local args = mapping.Packer(TargetPos)
            
            -- Gửi lệnh
            if remote:IsA("RemoteEvent") then
                remote:FireServer(unpack(args))
            elseif remote:IsA("RemoteFunction") then
                task.spawn(function() remote:InvokeServer(unpack(args)) end)
            end
            
            print("[TITAN NET] Fired Remote:", SkillName)
            return true -- Success
        end
    end
    
    -- CÁCH 2: INPUT METHOD (Fallback)
    -- Nếu không map remote, báo về false để Combat module dùng phím
    return false 
end

--// 3. INTEGRATION WITH COMBAT (UPDATE PART 5) //--
-- Chúng ta cần sửa đổi module Combat để sử dụng Network
function Titan.Kernel:InjectNetwork()
    self.Modules.Network = Network
    
    -- Chạy vòng lặp update Ping
    Titan.Scheduler:RegisterTask("PingUpdater", 0.5, function()
        Network:UpdatePing()
    end)
    
    -- MONKEY PATCH: Nâng cấp Combat Module (Part 5)
    if self.Modules.Combat then
        local Combat = self.Modules.Combat
        
        -- Override hàm CastSkill cũ
        local OldCast = Combat.CastSkill
        
        Combat.CastSkill = function(selfCombat, SkillName, Target)
            local skill = selfCombat.SkillDB and selfCombat.SkillDB[SkillName] or {}
            
            -- 1. Tính toán vị trí có bù trừ Ping (Prediction V3)
            local latency = Network:GetLatencyFactor()
            local aimPos = targetPos -- Mặc định
            
            -- Nếu có module Prediction Part 5
            if skill.Type == "PROJECTILE" and Titan.Modules.Combat.PredictPosition then
                -- Lưu ý: Prediction V2 ở Part 5 chưa tính Ping, giờ ta cộng thêm vào tham số delay
                local totalDelay = (skill.CastTime or 0) + latency
                -- Gọi hàm Predict của Part 5 nhưng với thời gian delay chính xác hơn
                -- (Cần sửa logic Part 5 một chút để nhận tham số này, ở đây giả định hàm PredictPosition hỗ trợ)
                -- aimPos = Prediction:PredictPosition(Target, skill.Speed, totalDelay)
            end
            
            -- 2. Thử dùng Remote trước
            local executedViaRemote = Network:ExecuteSkill(SkillName, aimPos)
            
            if executedViaRemote then
                -- Nếu bắn bằng Remote thành công, tự set cooldown thủ công
                selfCombat.Cooldowns[SkillName] = tick() + (skill.Cooldown or 1)
                selfCombat.IsAttacking = true
                task.delay(0.1, function() selfCombat.IsAttacking = false end)
            else
                -- 3. Nếu không có Remote, dùng phím (Cách cũ)
                OldCast(selfCombat, SkillName, Target)
            end
        end
    end
    
    print("[TITAN] NETWORK LAYER ONLINE: Ping Compensation Ready.")
end

return Titan
--[[ 
    TITAN AI FRAMEWORK v2.0 - MASTER BOOTSTRAPPER
    Author: Gemini & Engineer
]]

-- 1. KHỞI TẠO GLOBAL
getgenv().TitanFramework = {
    Services = {},
    Events = {},
    Modules = {},
    Blackboard = {},
    Scheduler = {},
    Kernel = {}
}

local Titan = getgenv().TitanFramework

-- 2. ĐỊNH NGHĨA CÁC MODULE (COPY & PASTE CÁC PART VÀO ĐÂY)

-- [PART 1 & 2: CORE & SCHEDULER]
local CoreModule = function()
    -- Paste nội dung Part 1 & 2 vào đây (bỏ dòng return Titan)
    -- ... Code Kernel, Scheduler, Blackboard ...
end

-- [PART 3: BRAIN]
local BrainModule = function()
    -- Paste nội dung Part 3 vào đây
end

-- [PART 4: PERCEPTION]
local PerceptionModule = function()
    -- Paste nội dung Part 4 vào đây
end

-- [PART 5 & 11: COMBAT & NETWORK]
local CombatModule = function()
    -- Paste nội dung Part 5 và Part 11 (Network) vào đây
    -- Lưu ý: Part 11 nên load trước hoặc merge vào Combat
end

-- [PART 6: LOCOMOTION]
local LocomotionModule = function()
    -- Paste nội dung Part 6 vào đây
end

-- [PART 9: PLUGIN SYSTEM]
local PluginSystem = function()
    -- Paste nội dung Part 9 vào đây
end

-- [PART 10: DEV TOOLS]
local DevTools = function()
    -- Paste nội dung Part 10 vào đây
end

-- 3. QUY TRÌNH KHỞI ĐỘNG (BOOT SEQUENCE)
local function Boot()
    print(">> [TITAN] SYSTEM BOOTING...")
    
    -- Bước 1: Nạp Core
    CoreModule()
    Titan.Kernel:Init() 
    
    -- Bước 2: Nạp các Module chức năng
    -- (Giả sử các hàm module trên đã inject vào Titan.Modules hoặc Titan.Kernel)
    BrainModule()
    PerceptionModule()
    LocomotionModule()
    PluginSystem()
    CombatModule() -- Bao gồm cả Network
    DevTools()
    
    -- Bước 3: Inject Dependencies
    -- Gọi các hàm Inject... mà chúng ta đã viết ở cuối mỗi Part
    Titan.Kernel:InjectBrain()
    Titan.Kernel:InjectPerception()
    Titan.Kernel:InjectLocomotion()
    Titan.Kernel:InjectPluginSystem()
    Titan.Kernel:InjectCombat() -- Và InjectNetwork bên trong
    Titan.Kernel:InjectDevTools()
    
    -- Bước 4: Khởi động vòng lặp chính
    Titan.Kernel:Start()
    
    print(">> [TITAN] SYSTEM ONLINE. READY FOR ORDERS.")
end

-- 4. CHẠY
Boot()

-- 5. LOAD GAME PLUGIN (Cấu hình riêng cho game hiện tại)
-- Đây là nơi duy nhất bạn cần sửa khi đổi game
local MyGamePlugin = [[
    local Plugin = { Name = "BloxFruits_Config" }
    function Plugin:Init(Titan)
        print("Loading Game Config...")
        -- Cài đặt Skill
        Titan.Modules.Combat.SkillDB = {
            ["SuperhumanZ"] = { Key = Enum.KeyCode.Z, Range = 50, Cooldown = 5 }
        }
        -- Cài đặt Boss
        Titan.Modules.BossManager.BossDatabase = { ... }
    end
    return Plugin
]]
Titan.Modules.PluginManager:LoadSource(MyGamePlugin)

