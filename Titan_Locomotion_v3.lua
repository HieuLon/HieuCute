--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 1: CORE ARCHITECTURE & BOOTSTRAPPER
    Author: Principal Architect
    License: Proprietary
]]

--// 0. ENVIRONMENT SAFETY & TYPE DEFINITIONS //--
local Titan = {
    Version = "3.0.0-PRO",
    IsLoaded = false,
    Services = {},
    Modules = {},
    Enums = {},
    Configs = {},
    UIBridge = nil -- Dành cho Part 10
}

-- Type Checking (Luau) giả lập để code trong sáng hơn
type Module = {
    Name: string,
    Priority: number,
    Init: (self: any, kernel: any) -> (),
    Start: (self: any) -> (),
    Update: (self: any, dt: number) -> (),
    Stop: (self: any) -> ()
}

--// 1. CENTRALIZED LOGGER (HỆ THỐNG LOG CHUYÊN NGHIỆP) //--
-- Giúp debug trên UI Console sau này
local Logger = {
    Logs = {} -- Lưu lại history để đẩy lên UI Dashboard
}

function Logger:Log(Type, Source, Msg)
    local timestamp = os.date("%H:%M:%S")
    local formattedMsg = string.format("[%s] [%s] [%s]: %s", timestamp, Type, Source, tostring(Msg))
    
    -- Lưu vào bộ nhớ đệm (Ring Buffer - tối đa 100 dòng)
    table.insert(self.Logs, 1, {Type = Type, Msg = formattedMsg})
    if #self.Logs > 100 then table.remove(self.Logs) end
    
    -- Output ra Console thật
    if Type == "INFO" then
        print(formattedMsg)
    elseif Type == "WARN" then
        warn(formattedMsg)
    elseif Type == "ERROR" then
        warn("🛑 " .. formattedMsg) -- Dùng warn để nổi bật hoặc rconsoleprint nếu có
    end
    
    -- Bắn event cho UI (nếu UI đã load)
    if Titan.Events and Titan.Events.OnLogAdded then
        Titan.Events.OnLogAdded:Fire(Type, formattedMsg)
    end
end

Titan.Logger = Logger

--// 2. ENUMS & CONSTANTS //--
Titan.Enums = {
    ModulePriority = {
        CRITICAL = 0,   -- Core systems (Signal, Scheduler)
        HIGH = 10,      -- Perception, Memory
        NORMAL = 20,    -- Brain, Decision
        LOW = 30,       -- Action execution
        BACKGROUND = 50 -- Analytics, Cleanup
    },
    SystemState = {
        BOOTING = "BOOTING",
        RUNNING = "RUNNING",
        PAUSED = "PAUSED",
        ERROR = "ERROR"
    }
}

--// 3. THE KERNEL (TRÁI TIM MỚI) //--
local Kernel = {
    State = Titan.Enums.SystemState.BOOTING,
    _modulesSorted = {},
    _janitor = nil -- Sẽ inject ở Part 2
}

-- Đăng ký Module với Priority để kiểm soát thứ tự khởi chạy
function Kernel:RegisterModule(ModuleTbl: Module)
    if not ModuleTbl.Name then
        Logger:Log("ERROR", "Kernel", "Module missing Name property!")
        return
    end
    
    ModuleTbl.Priority = ModuleTbl.Priority or Titan.Enums.ModulePriority.NORMAL
    Titan.Modules[ModuleTbl.Name] = ModuleTbl
    Logger:Log("INFO", "Kernel", "Registered Module: " .. ModuleTbl.Name)
end

function Kernel:GetModule(Name)
    return Titan.Modules[Name]
end

-- Boot Sequence: Init -> Start -> Loop
function Kernel:Boot()
    Logger:Log("INFO", "Kernel", ">> TITAN V3 SYSTEM BOOTING... <<")
    
    -- 1. Sort Modules by Priority
    for _, mod in pairs(Titan.Modules) do
        table.insert(self._modulesSorted, mod)
    end
    table.sort(self._modulesSorted, function(a, b) return a.Priority < b.Priority end)
    
    -- 2. Initialize Phase (Load Configs, Pre-alloc)
    Logger:Log("INFO", "Kernel", "Phase 1: Initialization")
    for _, mod in ipairs(self._modulesSorted) do
        if mod.Init then
            local success, err = pcall(function() mod:Init(Titan) end)
            if not success then Logger:Log("ERROR", mod.Name, "Init Failed: " .. tostring(err)) end
        end
    end
    
    -- 3. Start Phase (Connect Events, Start Threads)
    Logger:Log("INFO", "Kernel", "Phase 2: Starting Services")
    for _, mod in ipairs(self._modulesSorted) do
        if mod.Start then
            task.spawn(function()
                local success, err = pcall(function() mod:Start() end)
                if not success then Logger:Log("ERROR", mod.Name, "Start Failed: " .. tostring(err)) end
            end)
        end
    end
    
    self.State = Titan.Enums.SystemState.RUNNING
    Logger:Log("INFO", "Kernel", ">> SYSTEM ONLINE. READY. <<")
    
    -- 4. Start Heartbeat Loop
    local RunService = game:GetService("RunService")
    RunService.Heartbeat:Connect(function(dt)
        if self.State ~= Titan.Enums.SystemState.RUNNING then return end
        
        -- Loop qua các module cần Update
        for _, mod in ipairs(self._modulesSorted) do
            if mod.Update then
                -- Safety Wrapper cho từng frame (có thể bỏ pcall nếu muốn hiệu năng cao, nhưng giữ an toàn)
                -- Ở bản Production cao cấp, ta dùng XPcall để catch error 1 lần rồi disable module đó
                local success, err = pcall(mod.Update, mod, dt) 
                if not success then
                    Logger:Log("ERROR", mod.Name, "Runtime Error: " .. tostring(err))
                    self.State = Titan.Enums.SystemState.ERROR
                end
            end
        end
    end)
end

function Kernel:Shutdown()
    Logger:Log("WARN", "Kernel", "Shutting down system...")
    for _, mod in ipairs(self._modulesSorted) do
        if mod.Stop then pcall(mod.Stop, mod) end
    end
    self.State = Titan.Enums.SystemState.BOOTING
    Titan.IsLoaded = false
end

Titan.Kernel = Kernel

--// 4. GLOBAL EXPORT //--
getgenv().Titan = Titan

Titan.Blackboard = Blackboard
Titan.Brain = Brain
Titan.Config = Config
Titan.Squad = Titan.Squad or {}

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 2: CORE ENGINE LIBRARIES
    Components: Signal, Janitor, Blackboard, Scheduler
]]

local Titan = getgenv().Titan or {}
Titan.Libs = {} -- Chứa các thư viện tiện ích

--// 1. SIGNAL SYSTEM (Sự kiện nội bộ tốc độ cao) //--
-- Class này giúp các module nói chuyện với nhau mà không cần biết nhau (Decoupling)
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(callback)
    if not callback then error("Signal:Connect(nil)", 2) end
    local listener = { callback = callback, signal = self }
    table.insert(self._listeners, listener)
    
    -- Trả về object để disconnect
    return {
        Disconnect = function()
            if not listener.signal then return end
            for i, v in ipairs(listener.signal._listeners) do
                if v == listener then
                    table.remove(listener.signal._listeners, i)
                    break
                end
            end
            listener.signal = nil
        end
    }
end

function Signal:Fire(...)
    for _, listener in ipairs(self._listeners) do
        -- Sử dụng task.spawn để lỗi trong 1 listener không chặn các listener khác
        task.spawn(listener.callback, ...)
    end
end

function Signal:Wait()
    local running = coroutine.running()
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        task.spawn(running, ...)
    end)
    return coroutine.yield()
end

function Signal:Destroy()
    self._listeners = nil
end

Titan.Libs.Signal = Signal

--// 2. JANITOR (Quản lý rác thải bộ nhớ) //--
-- Dùng để dọn dẹp connections khi module bị tắt hoặc reset
local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
    return setmetatable({ _objects = {} }, Janitor)
end

function Janitor:Add(object, methodName)
    table.insert(self._objects, { object = object, methodName = methodName or "Destroy" })
    return object
end

function Janitor:Cleanup()
    for _, item in ipairs(self._objects) do
        local obj = item.object
        local method = item.methodName
        
        if type(obj) == "function" then
            obj()
        elseif typeof(obj) == "RBXScriptConnection" then
            obj:Disconnect()
        elseif type(obj) == "table" and obj[method] then
            obj[method](obj)
        elseif typeof(obj) == "Instance" then
            obj:Destroy()
        end
    end
    self._objects = {}
end

function Janitor:Destroy()
    self:Cleanup()
end

Titan.Libs.Janitor = Janitor

--// 3. BLACKBOARD V3 (Reactive Memory - CỐT LÕI CHO UI) //--
-- Đây là nơi UI và AI giao tiếp.
-- UI thay đổi config -> Blackboard update -> Bắn Event -> AI thay đổi hành vi.
local Blackboard = {}
Blackboard.__index = Blackboard

function Blackboard.new()
    local self = setmetatable({}, Blackboard)
    self._data = {}
    self._listeners = {} -- Map<Key, Signal>
    return self
end

-- Lấy dữ liệu an toàn
function Blackboard:Get(key, defaultVal)
    local val = self._data[key]
    if val == nil then return defaultVal end
    return val
end

-- Ghi dữ liệu và bắn event thông báo
function Blackboard:Set(key, value)
    local oldValue = self._data[key]
    
    -- Chỉ update nếu giá trị thực sự thay đổi (Tối ưu performance)
    if oldValue ~= value then
        self._data[key] = value
        
        -- Thông báo cho ai đang lắng nghe key này (Ví dụ: UI đang hiện thanh máu)
        if self._listeners[key] then
            self._listeners[key]:Fire(value, oldValue)
        end
        
        -- Log debug cho dev (chỉ log những key quan trọng để tránh spam)
        if key == "CurrentTarget" or key == "CombatState" then
             Titan.Logger:Log("INFO", "Blackboard", string.format("Set '%s' -> %s", key, tostring(value)))
        end
    end
end

-- Đăng ký lắng nghe thay đổi của 1 key cụ thể
function Blackboard:OnChange(key, callback)
    if not self._listeners[key] then
        self._listeners[key] = Titan.Libs.Signal.new()
    end
    return self._listeners[key]:Connect(callback)
end

-- Lấy toàn bộ data (Dùng cho hàm Save Config)
function Blackboard:Dump()
    return self._data
end

Titan.Libs.Blackboard = Blackboard

--// 4. SCHEDULER (Bộ điều phối nhịp) //--
-- Giúp giảm lag bằng cách phân phối tải
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
    return setmetatable({ _tasks = {} }, Scheduler)
end

-- Chạy task mỗi 'interval' giây
function Scheduler:Every(interval, callback, taskName)
    table.insert(self._tasks, {
        Interval = interval,
        Callback = callback,
        LastRun = 0,
        Name = taskName or "Unknown"
    })
end

-- Hàm này cần được gọi trong vòng lặp Heartbeat của Kernel
function Scheduler:Update(dt)
    local now = tick()
    for _, taskInfo in ipairs(self._tasks) do
        if now - taskInfo.LastRun >= taskInfo.Interval then
            taskInfo.LastRun = now
            -- Error handling cho từng task con
            local s, e = pcall(taskInfo.Callback)
            if not s then
                Titan.Logger:Log("WARN", "Scheduler", "Task failed ["..taskInfo.Name.."]: " .. tostring(e))
            end
        end
    end
end

Titan.Libs.Scheduler = Scheduler

--// 5. INTEGRATION INTO KERNEL //--
-- Tự động inject các thư viện này vào Kernel để module khác sử dụng

local function InjectCoreEngine()
    -- Khởi tạo Blackboard toàn cục
    Titan.Blackboard = Titan.Libs.Blackboard.new()
    
    -- Khởi tạo Scheduler toàn cục
    Titan.Scheduler = Titan.Libs.Scheduler.new()
    
    -- Khởi tạo System Janitor (dọn dẹp khi tắt Titan)
    Titan.Kernel._janitor = Titan.Libs.Janitor.new()
    
    -- Đăng ký Scheduler vào vòng lặp chính của Kernel
    -- Ta đăng ký nó như một Module ưu tiên cao
    Titan.Kernel:RegisterModule({
        Name = "System_Scheduler",
        Priority = Titan.Enums.ModulePriority.CRITICAL, -- Chạy đầu tiên
        Update = function(self, dt)
            Titan.Scheduler:Update(dt)
        end
    })
    
    -- Thiết lập các biến mặc định quan trọng cho Blackboard
    Titan.Blackboard:Set("IsActive", true) -- Nút bật tắt tổng
    Titan.Blackboard:Set("CurrentTarget", nil)
    Titan.Blackboard:Set("FPS", 0)
    
    Titan.Logger:Log("INFO", "Core", "Engine Libraries Injected Successfully.")
end

InjectCoreEngine()

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 3: THE BRAIN (UTILITY AI SYSTEM)
    
    Architecture: Utility-based Scoring System
    Features:
    - Modular Evaluators (Plug & Play decisions)
    - Inertia/Hysteresis (Chống hiện tượng bot đổi ý liên tục gây giật)
    - Debug Data Stream (Gửi dữ liệu suy nghĩ ra UI Dashboard)
]]

local Titan = getgenv().Titan
local Brain = {
    Evaluators = {}, -- Danh sách các hành động có thể làm
    CurrentAction = nil,
    Params = {
        ThinkInterval = 0.1, -- Suy nghĩ mỗi 0.1s (10Hz)
        Inertia = 1.2,       -- Điểm số hành động mới phải cao hơn hành động cũ 20% mới được đổi (Chống jitter)
    }
}

--// 1. EVALUATOR CLASS (Đơn vị suy nghĩ cơ bản) //--
-- Mỗi Evaluator đại diện cho 1 hành động: "Attack", "Retreat", "Rest"
local Evaluator = {}
Evaluator.__index = Evaluator

function Evaluator.new(name, weight)
    local self = setmetatable({}, Evaluator)
    self.Name = name
    self.Weight = weight or 1.0 -- Độ ưu tiên cơ bản
    self.Considerations = {} -- Các hàm tính điểm con
    return self
end

-- Thêm một yếu tố cân nhắc. Ví dụ: "Máu càng thấp điểm càng cao"
-- curveFunc: input(0-1) -> output(0-1)
function Evaluator:AddConsideration(name, inputFunc, curveFunc)
    table.insert(self.Considerations, {
        Name = name,
        Input = inputFunc,
        Curve = curveFunc or function(x) return x end -- Mặc định tuyến tính
    })
end

function Evaluator:Evaluate(blackboard)
    local finalScore = self.Weight
    
    for _, cons in ipairs(self.Considerations) do
        local rawVal = cons.Input(blackboard) -- Lấy giá trị (vd: % máu)
        local score = cons.Curve(rawVal)      -- Quy đổi ra điểm
        
        -- Nếu bất kỳ điều kiện nào trả về 0, hành động này vô nghĩa
        if score <= 0 then return 0 end
        
        finalScore = finalScore * score
    end
    
    return finalScore
end

function Evaluator:Execute(blackboard)
    -- Abstract method: Module con sẽ override hàm này
    Titan.Logger:Log("WARN", "Brain", "Execute not implemented for " .. self.Name)
end

--// 2. BRAIN CORE LOGIC //--

function Brain:RegisterEvaluator(evaluator)
    table.insert(self.Evaluators, evaluator)
    Titan.Logger:Log("INFO", "Brain", "Registered Action: " .. evaluator.Name)
end

function Brain:Decide()
    local blackboard = Titan.Blackboard
    local bestScore = -1
    local bestAction = nil
    
    -- Table chứa điểm số để gửi ra UI Debug
    local debugScores = {} 

    -- 1. Tính điểm tất cả hành động
    for _, eval in ipairs(self.Evaluators) do
        local score = eval:Evaluate(blackboard)
        
        -- Logic quán tính (Stickiness): 
        -- Nếu đang làm hành động A, thì hành động B muốn chiếm quyền phải có điểm cao hơn A * Inertia
        if self.CurrentAction and self.CurrentAction.Name == eval.Name then
            score = score * self.Params.Inertia
        end
        
        debugScores[eval.Name] = math.floor(score * 100) / 100 -- Làm tròn 2 số lẻ
        
        if score > bestScore then
            bestScore = score
            bestAction = eval
        end
    end
    
    -- 2. Cập nhật Blackboard để UI hiển thị
    blackboard:Set("Brain_DebugScores", debugScores)
    
    -- 3. Thực thi hành động tốt nhất
    if bestAction and bestAction ~= self.CurrentAction then
        -- Chuyển đổi hành động
        local prevName = self.CurrentAction and self.CurrentAction.Name or "None"
        Titan.Logger:Log("INFO", "Brain", string.format("Switch Decision: [%s] -> [%s] (Score: %.2f)", prevName, bestAction.Name, bestScore))
        
        self.CurrentAction = bestAction
        blackboard:Set("CurrentDecision", bestAction.Name) -- UI sẽ bắt event này để hiện text
    end
    
    -- 4. Gọi hàm Execute của hành động chiến thắng
    if self.CurrentAction then
        -- Pcall để đảm bảo logic hành động không làm crash não
        local s, e = pcall(function() self.CurrentAction:Execute(blackboard) end)
        if not s then Titan.Logger:Log("ERROR", "Brain", "Exec Error: " .. tostring(e)) end
    end
end

--// 3. COMMON CURVES (Thư viện toán học cho não) //--
Brain.Curves = {
    Linear = function(x) return x end,
    Inverse = function(x) return 1 - x end, -- Càng nhiều càng thấp (vd: Khoảng cách)
    -- Logistic: Tăng đột ngột ở ngưỡng (vd: Máu < 30% thì điểm tăng vọt)
    Logistic = function(x, steepness, offset) 
        steepness = steepness or 10
        offset = offset or 0.5
        return 1 / (1 + math.exp(-steepness * (x - offset)))
    end
}

--// 4. MODULE INTERFACE //--

function Brain:Init(titanKernel)
    self.Kernel = titanKernel
    Titan.Brain = self
    Titan.Classes = Titan.Classes or {}
    Titan.Classes.Evaluator = Evaluator -- Export class để Plugin dùng
end

function Brain:Start()
    -- Sử dụng Scheduler đã làm ở Part 2
    -- Không chạy mỗi frame, chỉ chạy 10 lần/giây để tiết kiệm CPU
    Titan.Scheduler:Every(self.Params.ThinkInterval, function()
        if Titan.Blackboard:Get("IsActive", true) then
            self:Decide()
        end
    end, "Brain_ThinkProcess")
end

-- Inject vào hệ thống
Titan.Kernel:RegisterModule({
    Name = "Core_Brain",
    Priority = Titan.Enums.ModulePriority.NORMAL,
    Init = function(self, k) Brain:Init(k) end,
    Start = function(self) Brain:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 4: PERCEPTION & MEMORY
    
    Features:
    - Smart Target Selector (Weighted Scoring)
    - Tactical Memory (Nhớ vị trí địch khi mất tầm nhìn)
    - Entity Analytics (DPS Tracker)
    - UI Data Binding
]]

local Titan = getgenv().Titan
local Perception = {
    Params = {
        ScanRange = 1000,
        ScanInterval = 0.2, -- 5Hz (Quét địch 5 lần/giây để tối ưu)
        TargetStickiness = 10, -- Điểm cộng cho mục tiêu hiện tại (để không đổi mục tiêu liên tục)
    },
    Memory = {}, -- Lưu trữ thông tin từng Entity: { LastPos, HealthHistory, IsVisible }
    CurrentTarget = nil
}

--// 1. HELPER: ENTITY VALIDATION //--
local function IsValidEnemy(char)
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    
    if not hum or not root then return false end
    if hum.Health <= 0 then return false end
    
    -- Kiểm tra ForceField hoặc Team (Cần update logic Team check tùy game)
    local ff = char:FindFirstChildOfClass("ForceField")
    if ff and ff.Visible then return false end
    
    return true
end

--// 2. TARGET SCORING SYSTEM //--
-- Chấm điểm kẻ địch để chọn người ngon ăn nhất
function Perception:CalculateScore(char, root, hum)
    local MyRoot = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not MyRoot then return 0 end

    local dist = (root.Position - MyRoot.Position).Magnitude
    
    -- Nếu ngoài tầm quét -> Bỏ qua
    if dist > self.Params.ScanRange then return -1 end

    -- Công thức điểm: (1000 / Khoảng cách) + (500 / %Máu)
    local distScore = (1000 / math.max(1, dist)) * 1.5
    local healthScore = (1 - (hum.Health / hum.MaxHealth)) * 200 -- Máu càng thấp điểm càng cao
    
    local totalScore = distScore + healthScore
    
    -- Ưu tiên mục tiêu đang đánh dở (Anti-flicker)
    if self.CurrentTarget and self.CurrentTarget == char then
        totalScore = totalScore + self.Params.TargetStickiness
    end

    return totalScore
end

--// 3. MAIN SCANNING LOOP //--
function Perception:Scan()
    local bestTarget = nil
    local maxScore = -1
    local enemiesList = {} -- Dùng cho UI hiển thị danh sách địch

    -- Lấy danh sách cần quét (Players hoặc NPCs folder)
    local potentialTargets = game.Players:GetPlayers()
    
    for _, plr in ipairs(potentialTargets) do
        if plr ~= game.Players.LocalPlayer then
            local char = plr.Character
            if IsValidEnemy(char) then
                local root = char.HumanoidRootPart
                local hum = char.Humanoid
                
                local score = self:CalculateScore(char, root, hum)
                
                if score > 0 then
                    table.insert(enemiesList, {Name = plr.Name, Score = score, Dist = (root.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude})
                    
                    if score > maxScore then
                        maxScore = score
                        bestTarget = char
                    end
                    
                    -- Update Memory
                    self:UpdateMemory(plr.Name, char)
                end
            end
        end
    end

    -- Update Logic
    if bestTarget ~= self.CurrentTarget then
        self.CurrentTarget = bestTarget
        Titan.Blackboard:Set("CurrentTarget", bestTarget) -- Báo cho Brain và Combat biết
        Titan.Logger:Log("INFO", "Perception", "Locked Target: " .. (bestTarget and bestTarget.Name or "None"))
    end
    
    -- Gửi dữ liệu ra Blackboard cho UI Dashboard vẽ ESP hoặc List
    Titan.Blackboard:Set("NearbyEnemies", enemiesList)
end

--// 4. MEMORY & ANALYTICS //--
-- Hàm này chạy mỗi frame để tính toán chi tiết cho Target hiện tại
function Perception:TrackTarget(dt)
    local target = self.CurrentTarget
    if not target or not IsValidEnemy(target) then 
        self.CurrentTarget = nil
        Titan.Blackboard:Set("CurrentTarget", nil)
        Titan.Blackboard:Set("TargetInfo", nil) -- Clear UI
        return 
    end

    local root = target.HumanoidRootPart
    local hum = target.Humanoid
    local myRoot = game.Players.LocalPlayer.Character.HumanoidRootPart

    -- Tính toán vận tốc thực (để module Combat dự đoán đường đạn)
    local velocity = root.AssemblyLinearVelocity
    local distance = (root.Position - myRoot.Position).Magnitude
    
    -- Đóng gói dữ liệu chiến thuật
    local tacticalData = {
        Position = root.Position,
        Velocity = velocity,
        Distance = distance,
        Health = hum.Health,
        MaxHealth = hum.MaxHealth,
        IsMoving = velocity.Magnitude > 0.1,
        PredictedPos_1s = root.Position + (velocity * 1) -- Dự đoán vị trí sau 1s
    }

    -- Cập nhật vào Blackboard (Ghi đè liên tục - High Frequency)
    Titan.Blackboard:Set("TargetInfo", tacticalData)
    
    -- UI Dashboard Data (Dữ liệu hiển thị đẹp)
    Titan.Blackboard:Set("UI_CombatStatus", {
        TargetName = target.Name,
        TargetHP = math.floor(hum.Health),
        Dist = math.floor(distance) .. "m",
        ThreatLevel = (distance < 20 and "HIGH") or (distance < 50 and "MED") or "LOW"
    })
end

function Perception:UpdateMemory(id, char)
    -- Lưu vị trí cuối cùng nhìn thấy
    if not self.Memory[id] then self.Memory[id] = {} end
    self.Memory[id].LastSeen = os.time()
    self.Memory[id].LastPos = char.HumanoidRootPart.Position
end

--// 5. LIFECYCLE //--
function Perception:Init(kernel)
    Titan.Perception = self
end

function Perception:Start()
    -- Task 1: Quét diện rộng (Tần suất thấp: 0.2s)
    Titan.Scheduler:Every(self.Params.ScanInterval, function()
        if Titan.Blackboard:Get("IsActive") then
            self:Scan()
        end
    end, "Perception_Scan")

    -- Task 2: Track Target chi tiết (Tần suất cao: Mỗi frame)
    -- Dùng RunService để đảm bảo mượt mà cho AimBot/Prediction
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        if Titan.Blackboard:Get("IsActive") then
            self:TrackTarget(dt)
        end
    end)
end

Titan.Kernel:RegisterModule({
    Name = "Core_Perception",
    Priority = Titan.Enums.ModulePriority.HIGH, -- Chạy trước Brain
    Init = function(self, k) Perception:Init(k) end,
    Start = function(self) Perception:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 5: COMBAT & PREDICTION ENGINE
    
    Features:
    - Linear Trajectory Prediction (Dự đoán đường đạn tuyến tính)
    - Latency Compensation (Bù lag ping)
    - Skill Manager (Quản lý hồi chiêu & Tầm xa)
    - Aim Assistant (Camera Lock)
    - UI Data Stream (Gửi trạng thái Skill ra Dashboard)
]]

local Titan = getgenv().Titan
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Combat = {
    Params = {
        PredictionFactor = 1.0, -- Hệ số dự đoán (Tăng nếu ping cao)
        AimSmoothness = 0.2,    -- 0: Khóa cứng, 1: Rất chậm
        AutoLook = true,        -- Tự quay mặt vào địch
        AttackRange = 50,       -- Range mặc định (sẽ override bởi Plugin)
    },
    State = {
        IsAttacking = false,
        LastAttackTime = 0,
        Cooldowns = {}, -- { ["SkillZ"] = timestamp_ready }
        CurrentWeapon = "Melee"
    }
}

--// 1. MATH CORE: PREDICTION ENGINE //--
-- Tính toán vị trí bắn dựa trên Ping và Vận tốc địch
function Combat:GetPredictedPos(targetRoot, projectileSpeed)
    if not targetRoot then return Vector3.new(0,0,0) end
    
    local targetPos = targetRoot.Position
    local targetVel = targetRoot.AssemblyLinearVelocity
    
    -- Lấy Ping hiện tại để bù trễ
    local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    
    -- Nếu đạn tức thời (Raycast/Hitscan), chỉ cần bù Ping
    if not projectileSpeed or projectileSpeed <= 0 then
        return targetPos + (targetVel * ping * self.Params.PredictionFactor)
    end
    
    -- Nếu đạn có tốc độ bay (Projectile), tính thời gian bay
    local dist = (targetPos - Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
    local timeToImpact = (dist / projectileSpeed) + ping
    
    -- Công thức: Vị trí tương lai = Vị trí hiện tại + (Vận tốc * Thời gian)
    local predicted = targetPos + (targetVel * timeToImpact * self.Params.PredictionFactor)
    
    return predicted
end

--// 2. MOTOR: AIM ASSISTANT //--
function Combat:AimAt(position)
    if not self.Params.AutoLook then return end
    
    local localChar = Players.LocalPlayer.Character
    if not localChar then return end
    
    local root = localChar:FindFirstChild("HumanoidRootPart")
    if root then
        -- Tính toán CFrame mới
        local lookCFrame = CFrame.new(root.Position, Vector3.new(position.X, root.Position.Y, position.Z))
        
        -- Interpolation (Làm mượt chuyển động xoay để tránh bị Anti-Cheat phát hiện)
        -- Sử dụng Tween hoặc Lerp. Ở đây dùng Lerp cho nhẹ.
        root.CFrame = root.CFrame:Lerp(lookCFrame, 1 - self.Params.AimSmoothness)
    end
end

--// 3. SKILL MANAGER //--
-- Kiểm tra xem skill có sẵn sàng không (Cooldown, Stun, Mana...)
function Combat:CanUseSkill(skillName)
    local now = tick()
    local readyTime = self.State.Cooldowns[skillName] or 0
    
    -- Debug UI: Gửi trạng thái hồi chiêu
    Titan.Blackboard:Set("SkillStatus_"..skillName, math.max(0, math.floor(readyTime - now)))
    
    return now >= readyTime
end

function Combat:SetCooldown(skillName, duration)
    self.State.Cooldowns[skillName] = tick() + duration
    -- Update UI ngay lập tức
    Titan.Blackboard:Set("SkillStatus_"..skillName, duration) 
end

--// 4. MAIN COMBAT LOOP //--
-- Được gọi bởi Brain khi quyết định là "ATTACK"
function Combat:ExecuteCombatLogic(blackboard)
    local target = blackboard:Get("CurrentTarget")
    if not target then return end
    
    local targetInfo = blackboard:Get("TargetInfo") -- Lấy data từ Perception (Part 4)
    if not targetInfo then return end

    -- 1. Aim Logic
    -- Giả sử Projectile Speed = 300 (phổ biến trong game RPG). Plugin sẽ override số này.
    local aimPos = self:GetPredictedPos(target.HumanoidRootPart, 300)
    self:AimAt(aimPos)

    -- 2. Range Check & Execution
    local myPos = Players.LocalPlayer.Character.HumanoidRootPart.Position
    local dist = (aimPos - myPos).Magnitude
    
    -- Gửi info ra Dashboard
    blackboard:Set("UI_CombatDebug", {
        State = "ENGAGING",
        AimingAt = aimPos,
        Distance = math.floor(dist)
    })

    -- Logic chọn skill cơ bản (Plugin sẽ mở rộng phần này)
    if dist <= self.Params.AttackRange then
        -- Hook để Plugin game cụ thể chèn logic skill vào (Dependency Injection)
        if self.OnAttackRequest then
            self.OnAttackRequest(target, dist)
        else
            -- Fallback logic: Click chuột trái
            if self:CanUseSkill("M1") then
                -- Giả lập click (Chỉ demo, Production sẽ dùng VirtualInputManager)
                -- game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,true,game,1)
                -- game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,false,game,1)
                
                Titan.Logger:Log("INFO", "Combat", "Attacking Target: " .. target.Name)
                self:SetCooldown("M1", 0.5) -- Giả sử đánh thường delay 0.5s
            end
        end
    else
        -- Nếu xa quá -> Brain nên chuyển sang trạng thái "CHASE"
        -- Ở đây Combat module chỉ báo cáo lại là "OUT_OF_RANGE"
        blackboard:Set("CombatCondition", "OUT_OF_RANGE")
    end
end

--// 5. LIFECYCLE & INTEGRATION //--
function Combat:Init(kernel)
    Titan.Combat = self
    -- Đăng ký Evaluator chiến đấu vào Brain (Part 3)
    local CombatEval = Titan.Classes.Evaluator.new("Combat", 1.5) -- Priority cao hơn Idle
    
    -- Điều kiện: Có target và Target còn sống
    CombatEval:AddConsideration("HasTarget", function(bb)
        return bb:Get("CurrentTarget") and 1 or 0
    end)
    
    CombatEval.Execute = function(self_eval, bb)
        Combat:ExecuteCombatLogic(bb)
    end
    
    Titan.Brain:RegisterEvaluator(CombatEval)
end

function Combat:Start()
    -- Lắng nghe config từ UI Dashboard
    Titan.Blackboard:OnChange("Config_AttackRange", function(val)
        self.Params.AttackRange = val
    end)
    
    Titan.Blackboard:OnChange("Config_AimSmooth", function(val)
        self.Params.AimSmoothness = val
    end)
end

Titan.Kernel:RegisterModule({
    Name = "Core_Combat",
    Priority = Titan.Enums.ModulePriority.NORMAL,
    Init = function(self, k) Combat:Init(k) end,
    Start = function(self) Combat:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 6: LOCOMOTION & PHYSICS ENGINE
    
    Features:
    - Smart Pathfinding (A* Wrapper with Waypoints)
    - Anti-Stuck System (Auto Jump/Unstuck)
    - Combat Strafe & Kiting (Di chuyển chiến thuật)
    - UI Debug Visualization (Vẽ đường đi lên màn hình)
]]

local Titan = getgenv().Titan
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Locomotion = {
    Params = {
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        StuckThreshold = 0.5, -- Nếu trong 0.5s mà di chuyển < 1 stud -> Kẹt
        KitingDistance = 25,  -- Khoảng cách giữ an toàn
    },
    State = {
        IsMoving = false,
        CurrentPath = nil,
        Waypoints = {},
        CurrentWaypointIndex = 1,
        LastPos = Vector3.new(0,0,0),
        LastPosTime = 0,
        IsStuck = false
    }
}

--// 1. CORE MOVEMENT WRAPPER //--
function Locomotion:MoveToPosition(targetPos)
    local char = Players.LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid:MoveTo(targetPos)
    end
end

function Locomotion:Stop()
    local char = Players.LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid:MoveTo(char.HumanoidRootPart.Position) -- Move to self to stop
        self.State.IsMoving = false
        self.State.Waypoints = {}
    end
end

function Locomotion:Jump()
    local char = Players.LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.Jump = true
    end
end

--// 2. ANTI-STUCK MONITOR //--
-- Chạy ngầm để kiểm tra bot có đang đâm đầu vào tường không
function Locomotion:CheckStuck(dt)
    if not self.State.IsMoving then return end
    
    local char = Players.LocalPlayer.Character
    if not char then return end
    
    local currentPos = char.HumanoidRootPart.Position
    local now = tick()
    
    -- Kiểm tra mỗi 0.5s
    if now - self.State.LastPosTime > self.Params.StuckThreshold then
        local dist = (currentPos - self.State.LastPos).Magnitude
        
        -- Nếu đang cố di chuyển mà khoảng cách đi được < 1 stud -> Kẹt
        if dist < 1.0 then
            Titan.Logger:Log("WARN", "Locomotion", "Stuck detected! Attempting unstuck...")
            self.State.IsStuck = true
            self:Jump() -- Nhảy để thoát kẹt
            
            -- Nếu vẫn kẹt, thử đi lùi hoặc random hướng (Advanced Logic here)
            if dist < 0.1 then
                 -- Force lùi lại 1 chút
                 local backDir = (char.HumanoidRootPart.CFrame.LookVector * -5)
                 self:MoveToPosition(currentPos + backDir)
            end
        else
            self.State.IsStuck = false
        end
        
        self.State.LastPos = currentPos
        self.State.LastPosTime = now
    end
end

--// 3. PATHFINDING ENGINE (LONG DISTANCE) //--
function Locomotion:PathTo(targetPos)
    local char = Players.LocalPlayer.Character
    if not char then return end
    
    -- Tạo đường đi
    local path = PathfindingService:CreatePath({
        AgentRadius = self.Params.AgentRadius,
        AgentHeight = self.Params.AgentHeight,
        AgentCanJump = self.Params.AgentCanJump
    })
    
    local success, errorMessage = pcall(function()
        path:ComputeAsync(char.HumanoidRootPart.Position, targetPos)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        self.State.Waypoints = path:GetWaypoints()
        self.State.CurrentWaypointIndex = 2 -- Bỏ qua điểm đầu tiên (vị trí hiện tại)
        self.State.IsMoving = true
        
        -- Vẽ đường đi lên UI Debug (Nếu bật)
        Titan.Blackboard:Set("Debug_PathWaypoints", self.State.Waypoints)
    else
        Titan.Logger:Log("WARN", "Locomotion", "Path compute failed: " .. tostring(errorMessage))
        -- Fallback: Đi thẳng luôn (hy vọng không có tường)
        self:MoveToPosition(targetPos)
    end
end

-- Logic bám theo Waypoints mỗi frame
function Locomotion:FollowPath(dt)
    if not self.State.IsMoving or #self.State.Waypoints == 0 then return end
    
    local char = Players.LocalPlayer.Character
    local root = char.HumanoidRootPart
    local human = char.Humanoid
    
    -- Lấy điểm đến tiếp theo
    if self.State.CurrentWaypointIndex > #self.State.Waypoints then
        self:Stop() -- Đã đến đích
        return
    end
    
    local nextPoint = self.State.Waypoints[self.State.CurrentWaypointIndex]
    local distToPoint = (root.Position - nextPoint.Position).Magnitude
    
    -- Nếu đã đến gần điểm waypoint (còn 4 studs) -> Chuyển sang điểm tiếp theo
    if distToPoint < 4 then
        self.State.CurrentWaypointIndex = self.State.CurrentWaypointIndex + 1
        if nextPoint.Action == Enum.PathWaypointAction.Jump then
            human.Jump = true
        end
    else
        human:MoveTo(nextPoint.Position)
    end
end

--// 4. COMBAT MOVEMENT (KITING & STRAFING) //--
-- Được gọi bởi Combat Module khi đang đánh nhau
function Locomotion:CombatStrafe(target)
    if not target then return end
    
    local root = Players.LocalPlayer.Character.HumanoidRootPart
    local tRoot = target.HumanoidRootPart
    local dist = (root.Position - tRoot.Position).Magnitude
    
    -- 1. Kiting Logic (Giữ khoảng cách)
    if dist < self.Params.KitingDistance - 5 then
        -- Quá gần -> Lùi lại
        local retreatDir = (root.Position - tRoot.Position).Unit
        local dest = root.Position + (retreatDir * 10)
        self:MoveToPosition(dest)
        Titan.Blackboard:Set("MoveState", "RETREAT")
        
    elseif dist > self.Params.KitingDistance + 5 then
        -- Quá xa -> Áp sát
        self:MoveToPosition(tRoot.Position)
        Titan.Blackboard:Set("MoveState", "CHASE")
        
    else
        -- Khoảng cách đẹp -> Đi vòng quanh (Circle Strafe)
        -- Logic toán học: Vector pháp tuyến
        local dir = (tRoot.Position - root.Position).Unit
        local rightVector = dir:Cross(Vector3.new(0, 1, 0)) -- Vector vuông góc bên phải
        
        -- Random hướng trái phải để địch khó aim
        local strafeDir = rightVector
        if tick() % 2 > 1 then strafeDir = -rightVector end -- Đổi hướng mỗi giây
        
        self:MoveToPosition(root.Position + (strafeDir * 5))
        Titan.Blackboard:Set("MoveState", "STRAFE")
    end
    
    self.State.IsMoving = true
end

--// 5. LIFECYCLE //--
function Locomotion:Init(kernel)
    Titan.Locomotion = self
end

function Locomotion:Start()
    -- Vòng lặp vật lý (Heartbeat)
    RunService.Heartbeat:Connect(function(dt)
        if not Titan.Blackboard:Get("IsActive") then return end
        
        -- Ưu tiên 1: Combat Movement (Nếu đang đánh nhau thì bỏ qua Pathfinding)
        local combatState = Titan.Blackboard:Get("CombatState") -- "ENGAGING" hoặc "IDLE"
        local target = Titan.Blackboard:Get("CurrentTarget")
        
        if target and combatState == "ENGAGING" then
            self:CombatStrafe(target)
            self:CheckStuck(dt) -- Vẫn check kẹt khi combat
        else
            -- Ưu tiên 2: Navigation Movement
            self:FollowPath(dt)
            self:CheckStuck(dt)
        end
    end)
    
    -- Lắng nghe config UI
    Titan.Blackboard:OnChange("Config_KitingDist", function(val)
        self.Params.KitingDistance = val
    end)
end

Titan.Kernel:RegisterModule({
    Name = "Core_Locomotion",
    Priority = Titan.Enums.ModulePriority.LOW, -- Chạy sau Combat
    Init = function(self, k) Locomotion:Init(k) end,
    Start = function(self) Locomotion:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 7: HIVE MIND (MULTI-AGENT SWARM SYSTEM)
    
    Architecture: Master-Slave (Leader-Follower)
    Features:
    - Squad Role Management (Leader/Member)
    - Formation Mathematics (Đội hình V, Circle, Line)
    - Command Propagation (Truyền lệnh tập trung)
    - Shared Target Logic (Focus Fire)
]]

local Titan = getgenv().Titan
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local HiveMind = {
    Config = {
        Role = "ALONE", -- "LEADER", "FOLLOWER", "ALONE"
        SquadID = "TITAN_SQUAD_1",
        SyncInterval = 0.5, -- Đồng bộ 2 lần/giây
        LeaderName = "" -- Tên người chơi làm Leader
    },
    State = {
        SquadMembers = {}, -- Danh sách thành viên (Chỉ Leader mới cần biết)
        CurrentFormation = "CIRCLE",
        MyFormationOffset = Vector3.new(0,0,0) -- Vị trí đứng của mình so với Leader
    }
}

--// 1. COMMUNICATION LAYER (NETWORK ADAPTER) //--
-- Đây là lớp trừu tượng. Ở bản Production, bạn sẽ thay thế bằng WebSocket hoặc readfile/writefile
local Network = {}

function Network:Send(data)
    -- [TODO] Implement WebSocket/File logic here.
    -- Ví dụ giả lập: In ra console hoặc lưu vào file chung
    local packet = HttpService:JSONEncode(data)
    
    -- Simulation: Nếu là script chạy trên cùng PC, ta có thể dùng makefolder/writefile
    -- pcall(writefile, "Titan_Comm_"..HiveMind.Config.SquadID..".json", packet)
    
    -- Ở đây tôi dùng Event giả lập để demo logic
    if HiveMind.OnPacketReceived then
        HiveMind.OnPacketReceived(data)
    end
end

function Network:Receive()
    -- [TODO] Đọc file hoặc nhận WebSocket message
    -- return decodedData
end

--// 2. FORMATION MATHEMATICS //--
-- Tính toán vị trí đứng cho đệ tử dựa trên vị trí sư phụ
local Formation = {}

function Formation:GetOffset(index, totalMembers, type)
    if type == "CIRCLE" then
        local radius = 10
        local angle = (360 / totalMembers) * index
        local rad = math.rad(angle)
        return Vector3.new(math.cos(rad) * radius, 0, math.sin(rad) * radius)
        
    elseif type == "V_SHAPE" then
        local row = math.ceil(index / 2)
        local side = (index % 2 == 0) and 1 or -1 -- Trái hoặc phải
        return Vector3.new(side * row * 5, 0, -row * 5)
        
    elseif type == "LINE" then
        return Vector3.new((index - (totalMembers/2)) * 6, 0, 0)
    end
    return Vector3.new(0,0,5) -- Mặc định đứng sau lưng
end

--// 3. CORE LOGIC: LEADER //--
function HiveMind:LeaderUpdate()
    if self.Config.Role ~= "LEADER" then return end
    
    -- 1. Xác định mục tiêu chung
    local target = Titan.Blackboard:Get("CurrentTarget")
    local cmdType = target and "ATTACK" or "FOLLOW"
    local cmdData = {}
    
    if target then
        cmdData.TargetName = target.Name
        cmdData.TargetPos = {X=target.HumanoidRootPart.Position.X, Y=target.HumanoidRootPart.Position.Y, Z=target.HumanoidRootPart.Position.Z}
    else
        local myPos = Players.LocalPlayer.Character.HumanoidRootPart.Position
        cmdData.LeaderPos = {X=myPos.X, Y=myPos.Y, Z=myPos.Z}
    end
    
    -- 2. Gửi lệnh cho toàn bộ Squad
    Network:Send({
        Sender = Players.LocalPlayer.Name,
        Type = cmdType,
        Data = cmdData,
        Timestamp = os.time()
    })
    
    -- UI Update
    Titan.Blackboard:Set("SquadStatus", "LEADER: Commanding " .. #self.State.SquadMembers .. " units")
end

--// 4. CORE LOGIC: FOLLOWER //--
function HiveMind:FollowerUpdate()
    if self.Config.Role ~= "FOLLOWER" then return end
    
    -- Giả sử đã nhận được Packet từ Network (Logic giả lập)
    -- Trong thực tế, hàm này sẽ được gọi từ sự kiện OnMessage của WebSocket
    
    -- Logic Override Brain:
    -- Nếu là Follower, ta tắt bớt não của bot đi, chỉ nghe lời Leader
    
    -- Ví dụ xử lý lệnh nhận được:
    local lastCmd = Titan.Blackboard:Get("LastSquadCommand")
    if not lastCmd then return end
    
    if lastCmd.Type == "ATTACK" then
        -- Tìm target theo tên mà Leader gửi
        local enemy = game.Players:FindFirstChild(lastCmd.Data.TargetName) 
        or game.Workspace:FindFirstChild(lastCmd.Data.TargetName, true) -- Scan recursive
        
        if enemy then
            Titan.Blackboard:Set("CurrentTarget", enemy) -- Override Target của Perception
            Titan.Blackboard:Set("SquadStatus", "ASSISTING: " .. enemy.Name)
        end
        
    elseif lastCmd.Type == "FOLLOW" then
        -- Di chuyển đến vị trí Leader + Offset đội hình
        local leaderPos = Vector3.new(lastCmd.Data.LeaderPos.X, lastCmd.Data.LeaderPos.Y, lastCmd.Data.LeaderPos.Z)
        local dest = leaderPos + self.State.MyFormationOffset
        
        Titan.Locomotion:MoveToPosition(dest)
        Titan.Blackboard:Set("SquadStatus", "FOLLOWING LEADER")
    end
end

--// 5. INTEGRATION //--
function HiveMind:SetRole(role, leaderName)
    self.Config.Role = role
    self.Config.LeaderName = leaderName or ""
    
    if role == "FOLLOWER" then
        -- Tắt module Perception tự quét để tránh đánh linh tinh
        -- Titan.Perception.Params.ScanRange = 0 
        Titan.Logger:Log("INFO", "HiveMind", "Switched to FOLLOWER Mode. Awaiting orders.")
    elseif role == "LEADER" then
        Titan.Logger:Log("INFO", "HiveMind", "Switched to LEADER Mode. Commanding swarm.")
    end
    
    Titan.Blackboard:Set("MyRole", role)
end

function HiveMind:Init(kernel)
    Titan.HiveMind = self
    
    -- Đăng ký các biến cho UI config
    Titan.Blackboard:Set("Squad_Formation", "CIRCLE")
    Titan.Blackboard:OnChange("Squad_Formation", function(val)
        self.State.CurrentFormation = val
    end)
end

function HiveMind:Start()
    Titan.Scheduler:Every(self.Config.SyncInterval, function()
        if self.Config.Role == "LEADER" then
            self:LeaderUpdate()
        elseif self.Config.Role == "FOLLOWER" then
            self:FollowerUpdate()
        end
    end, "HiveMind_Sync")
end

Titan.Kernel:RegisterModule({
    Name = "Core_HiveMind",
    Priority = Titan.Enums.ModulePriority.BACKGROUND,
    Init = function(self, k) HiveMind:Init(k) end,
    Start = function(self) HiveMind:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 8: BOSS & PVE MECHANICS
    
    Features:
    - AoE Avoidance (Tự động né vòng đỏ/skill diện rộng)
    - Boss Phase Manager (Xử lý khiên, cutscene)
    - Auto Dungeon (Tự tìm đường sang phòng tiếp theo)
    - Safe Spot Finder (Tìm vị trí an toàn gần nhất)
]]

local Titan = getgenv().Titan
local Workspace = game:GetService("Workspace")

local BossAI = {
    Params = {
        AoEKeywords = {"Zone", "Area", "Telegraph", "Lava", "Trap"}, -- Tên part cần né
        AoEColor = Color3.fromRGB(255, 0, 0), -- Màu sắc cảnh báo (thường là đỏ)
        DodgeReactionTime = 0.1, -- Phản xạ né
        BossNames = {"Raid Boss", "Admin", "Event Boss"}, -- List tên Boss
    },
    State = {
        IsUnderThreat = false,
        CurrentBoss = nil,
        CurrentPhase = 1,
        NearestSafeSpot = nil
    }
}

--// 1. DANGER DETECTION (CẢM BIẾN NGUY HIỂM) //--
function BossAI:IsDangerousPart(part)
    if not part or not part:IsA("BasePart") then return false end
    
    -- Check 1: Tên part chứa từ khóa (Keyword Scan)
    for _, key in ipairs(self.Params.AoEKeywords) do
        if string.find(part.Name, key) then return true end
    end
    
    -- Check 2: Màu sắc cảnh báo (Color Scan)
    -- Nhiều game dùng part neon đỏ để báo hiệu
    if part.Color == self.Params.AoEColor and part.Transparency < 1 then
        return true
    end
    
    -- Check 3: Collidable (Thường AoE là CanCollide = false)
    if part.CanCollide == false and part.Name == "Hitbox" then
        return true
    end
    
    return false
end

function BossAI:ScanDangers()
    local myRoot = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    
    local escapeVector = Vector3.new(0,0,0)
    local dangerCount = 0
    
    -- Quét các part xung quanh trong bán kính 20 studs
    -- Sử dụng OverlapParams để tối ưu hiệu năng thay vì loop toàn map
    local overlapParams = OverlapParams.new()
    overlapParams.FilterDescendantsInstances = {game.Players.LocalPlayer.Character}
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local parts = Workspace:GetPartBoundsInRadius(myRoot.Position, 20, overlapParams)
    
    for _, part in ipairs(parts) do
        if self:IsDangerousPart(part) then
            dangerCount = dangerCount + 1
            
            -- Tính vector né: Hướng từ tâm AoE ra ngoài
            -- Vector = MyPos - DangerPartPos
            local fleeDir = (myRoot.Position - part.Position).Unit * 15 -- Chạy xa 15 studs
            escapeVector = escapeVector + fleeDir
            
            -- Vẽ debug UI (Part 10 sẽ hiển thị cái này)
            Titan.Blackboard:Set("Debug_DangerZone", part.Position)
        end
    end
    
    if dangerCount > 0 then
        self.State.IsUnderThreat = true
        -- GHI ĐÈ SUY NGHĨ: Gửi lệnh khẩn cấp vào Blackboard
        Titan.Blackboard:Set("EmergencyEvade", myRoot.Position + escapeVector)
        Titan.Logger:Log("WARN", "BossAI", "DETECTED AOE! EVADING...")
    else
        self.State.IsUnderThreat = false
        Titan.Blackboard:Set("EmergencyEvade", nil)
        Titan.Blackboard:Set("Debug_DangerZone", nil)
    end
end

--// 2. BOSS PHASE LOGIC //--
-- Xử lý các trạng thái đặc biệt của Boss (Vd: Bất tử thì không đánh)
function BossAI:AnalyzeBossState(bossModel)
    if not bossModel then return end
    
    local hum = bossModel:FindFirstChild("Humanoid")
    if not hum then return end
    
    -- Check Shield/Invincible (Thường game dùng ForceField)
    if bossModel:FindFirstChildOfClass("ForceField") then
        Titan.Blackboard:Set("TargetInvincible", true)
        -- Nếu Boss bất tử -> Tự động chuyển sang đánh lính (Mobs)
        Titan.Logger:Log("INFO", "BossAI", "Boss has shield. Switching priority.")
    else
        Titan.Blackboard:Set("TargetInvincible", false)
    end
    
    -- Check Animation (Vd: Boss giơ tay lên trời -> Sắp có Skill to)
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            -- Plugin Game cụ thể sẽ cung cấp ID animation nguy hiểm
            if Titan.Configs.DangerousAnims and Titan.Configs.DangerousAnims[track.Animation.AnimationId] then
                Titan.Blackboard:Set("BossCastingBigSkill", true)
                -- Lùi lại ngay
                Titan.Locomotion:CombatStrafe(bossModel) -- Force lùi
            end
        end
    end
end

--// 3. AUTO DUNGEON (ROOM NAVIGATION) //--
-- Logic đi từ phòng A sang phòng B sau khi dọn quái
function BossAI:DungeonNavigator()
    local currentState = Titan.Blackboard:Get("CombatState")
    
    -- Nếu không còn quái (IDLE) và đang trong chế độ Dungeon
    if currentState == "IDLE" and Titan.Blackboard:Get("Mode") == "DUNGEON" then
        -- Tìm cổng/cửa tiếp theo
        local nextGate = Workspace:FindFirstChild("NextRoomGate", true) -- Tên object tùy game
        
        if nextGate then
            Titan.Logger:Log("INFO", "Dungeon", "Moving to next room...")
            Titan.Locomotion:PathTo(nextGate.Position)
        end
    end
end

--// 4. INTEGRATION HOOK //--
function BossAI:Init(kernel)
    Titan.BossAI = self
    
    -- Inject Logic vào Brain (Priority cực cao: Survival)
    local EvasionEval = Titan.Classes.Evaluator.new("EvadeAoE", 10.0) -- Priority 10 (Cao hơn cả Attack 1.5)
    
    EvasionEval:AddConsideration("InDanger", function(bb)
        return bb:Get("EmergencyEvade") and 1 or 0
    end, Titan.Brain.Curves.Linear)
    
    EvasionEval.Execute = function(self_eval, bb)
        local safePos = bb:Get("EmergencyEvade")
        if safePos then
            -- Bypass Pathfinding, chạy thẳng (MoveDirection) để nhanh nhất
            Titan.Locomotion:MoveToPosition(safePos)
            Titan.Locomotion:Jump() -- Nhảy để tránh kẹt
        end
    end
    
    Titan.Brain:RegisterEvaluator(EvasionEval)
end

function BossAI:Start()
    -- Scan nguy hiểm liên tục (Mỗi 0.1s)
    Titan.Scheduler:Every(0.1, function()
        if Titan.Blackboard:Get("IsActive") then
            self:ScanDangers()
            
            -- Nếu có target là Boss, phân tích trạng thái
            local target = Titan.Blackboard:Get("CurrentTarget")
            if target and table.find(self.Params.BossNames, target.Name) then
                self:AnalyzeBossState(target)
            end
            
            -- Logic Dungeon
            self:DungeonNavigator()
        end
    end, "BossAI_Loop")
    
    -- Config UI Listeners
    Titan.Blackboard:OnChange("Config_BossNames", function(val)
        -- Parse string "Boss1, Boss2" thành table
        self.Params.BossNames = string.split(val, ",")
    end)
end

Titan.Kernel:RegisterModule({
    Name = "Core_BossAI",
    Priority = Titan.Enums.ModulePriority.HIGH, -- Chạy trước Combat
    Init = function(self, k) BossAI:Init(k) end,
    Start = function(self) BossAI:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 9: PLUGIN SYSTEM & HOT-LOADING
    
    Architecture: Dependency Injection
    Features:
    - PlaceId Auto-Detection
    - Sandbox Execution (Pcall wrappings)
    - Standardized API for External Developers
]]

local Titan = getgenv().Titan
local HttpService = game:GetService("HttpService")

local PluginSystem = {
    CurrentPlugin = nil,
    LoadedPlugins = {},
    -- Database mapping PlaceId -> Plugin Name
    GameDatabase = {
        [2753915549] = "BloxFruits",
        [4442272183] = "BloxFruits",
        [7449423635] = "BloxFruits",
        [6872274481] = "Bedwars",
        -- Thêm ID game khác vào đây
    },
    DefaultPlugin = "Universal_Generic"
}

--// 1. THE SANDBOX API (Hàm cung cấp cho người viết Plugin) //--
-- Plugin sẽ không gọi thẳng vào Core, mà gọi qua API này để an toàn
local TitanAPI = {}

function TitanAPI:SetTargetFilter(filterFunc)
    -- Override logic chọn địch của Perception
    Titan.Perception.CustomTargetCheck = filterFunc
end

function TitanAPI:SetAttackLogic(attackFunc)
    -- Override logic đánh của Combat
    Titan.Combat.OnAttackRequest = attackFunc
end

function TitanAPI:SetMovementLogic(moveFunc)
    -- Override logic di chuyển
    Titan.Locomotion.OnCustomMove = moveFunc
end

function TitanAPI:RegisterSkill(key, cooldown, range, isHold)
    -- Đăng ký thông số skill vào hệ thống quản lý Cooldown
    Titan.Combat.State.Cooldowns[key] = 0 -- Reset
    -- Lưu metadata để UI hiển thị
    if not Titan.Combat.SkillDatabase then Titan.Combat.SkillDatabase = {} end
    Titan.Combat.SkillDatabase[key] = {Range = range, Cooldown = cooldown}
end

--// 2. PLUGIN LOADER ENGINE //--

function PluginSystem:LoadPlugin(pluginName)
    Titan.Logger:Log("WARN", "PluginSystem", "Attempting to load plugin: " .. pluginName)
    
    -- Reset các override cũ
    Titan.Perception.CustomTargetCheck = nil
    Titan.Combat.OnAttackRequest = nil
    
    -- Giả lập việc load code (Trong thực tế sẽ dùng loadstring(game:HttpGet(...)))
    -- Ở đây ta sẽ check trong thư viện nội bộ
    local pluginModule = self.LoadedPlugins[pluginName]
    
    if not pluginModule then
        Titan.Logger:Log("ERROR", "PluginSystem", "Plugin not found: " .. pluginName .. ". Loading Universal fallback.")
        pluginModule = self.LoadedPlugins["Universal_Generic"]
    end
    
    -- Execute Plugin trong môi trường an toàn
    local success, err = pcall(function()
        -- Inject TitanAPI vào plugin để nó sử dụng
        pluginModule:Init(TitanAPI, Titan)
        self.CurrentPlugin = pluginModule
        Titan.Blackboard:Set("CurrentGameMode", pluginModule.Name)
    end)
    
    if success then
        Titan.Logger:Log("INFO", "PluginSystem", ">> PLUGIN LOADED SUCCESSFULLY: " .. pluginModule.Name)
        -- Thông báo cho UI cập nhật
        Titan.Blackboard:Set("UI_Notification", {Title = "System", Msg = "Loaded: " .. pluginModule.Name, Duration = 3})
    else
        Titan.Logger:Log("ERROR", "PluginSystem", "CRITICAL: Plugin Crash! " .. tostring(err))
    end
end

function PluginSystem:AutoDetect()
    local placeId = game.PlaceId
    local detectedName = self.GameDatabase[placeId]
    
    if detectedName then
        Titan.Logger:Log("INFO", "PluginSystem", "Auto-detected game: " .. detectedName)
        self:LoadPlugin(detectedName)
    else
        Titan.Logger:Log("WARN", "PluginSystem", "Unknown Game ID ("..placeId.."). Loading Universal.")
        self:LoadPlugin(self.DefaultPlugin)
    end
end

--// 3. INTERNAL PLUGIN REPOSITORY (Ví dụ mẫu) //--

-- [PLUGIN MẪU 1]: Universal (Dùng cho mọi game)
PluginSystem.LoadedPlugins["Universal_Generic"] = {
    Name = "Universal Mode",
    Init = function(self, API, Core)
        -- Logic mặc định: Click chuột
        API:SetAttackLogic(function(target, dist)
            if dist < 10 then
                -- Giả lập click chuột trái
                game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,true,game,1)
                game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,false,game,1)
                Core.Combat:SetCooldown("M1", 0.1)
            end
        end)
    end
}

-- [PLUGIN MẪU 2]: Blox Fruits Logic (Minh họa)
PluginSystem.LoadedPlugins["BloxFruits"] = {
    Name = "Blox Fruits Pro",
    Init = function(self, API, Core)
        -- 1. Setup Skill
        API:RegisterSkill("Z", 5, 40) -- Key Z, CD 5s, Range 40
        API:RegisterSkill("X", 8, 60)
        
        -- 2. Override Target Check (Chỉ đánh NPC có QuestMarker)
        API:SetTargetFilter(function(char)
            if char:FindFirstChild("QuestMark") then return true end
            -- Mặc định trả về true để đánh tất cả nếu không tìm thấy mark
            return true 
        end)
        
        -- 3. Override Attack Logic
        API:SetAttackLogic(function(target, dist)
            local Combat = Core.Combat
            
            -- Combo logic: Z -> X -> Click
            if Combat:CanUseSkill("Z") and dist < 40 then
                game:GetService("VirtualInputManager"):SendKeyEvent(true, "Z", false, game)
                task.wait(0.1)
                game:GetService("VirtualInputManager"):SendKeyEvent(false, "Z", false, game)
                Combat:SetCooldown("Z", 5)
                return
            end
            
            if Combat:CanUseSkill("X") and dist < 60 then
                game:GetService("VirtualInputManager"):SendKeyEvent(true, "X", false, game)
                task.wait(0.1) -- Hold X xíu
                game:GetService("VirtualInputManager"):SendKeyEvent(false, "X", false, game)
                Combat:SetCooldown("X", 8)
                return
            end
            
            -- Spam click đánh thường
            game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,true,game,1)
            game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,false,game,1)
            Combat:SetCooldown("M1", 0.2)
        end)
    end
}


--// 4. INTEGRATION //--
function PluginSystem:Init(kernel)
    Titan.PluginSystem = self
end

function PluginSystem:Start()
    -- Delay nhẹ để đảm bảo mọi module khác đã sẵn sàng
    task.delay(1, function()
        self:AutoDetect()
    end)
    
    -- Lắng nghe sự kiện đổi Plugin từ UI Dashboard
    Titan.Blackboard:OnChange("Config_LoadPlugin", function(pluginName)
        self:LoadPlugin(pluginName)
    end)
end

Titan.Kernel:RegisterModule({
    Name = "Core_PluginSystem",
    Priority = Titan.Enums.ModulePriority.BACKGROUND,
    Init = function(self, k) PluginSystem:Init(k) end,
    Start = function(self) PluginSystem:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 10: REACTIVE UI DASHBOARD (Frontend)
    
    Library: Fluent UI (External Loadstring)
    Pattern: MVVM (Model-View-ViewModel) via Blackboard
]]

local Titan = getgenv().Titan
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local UI = {
    Window = nil,
    Tabs = {},
    Elements = {} -- Lưu tham chiếu để update code
}

--// 1. UI CONSTRUCTION //--
function UI:Build()
    self.Window = Fluent:CreateWindow({
        Title = "TITAN AI FRAMEWORK v3.0",
        SubTitle = "by Gemini | " .. (Titan.PluginSystem.CurrentPlugin and Titan.PluginSystem.CurrentPlugin.Name or "Universal"),
        TabWidth = 160,
        Size = UDim2.fromOffset(580, 460),
        Acrylic = true, 
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl 
    })

    -- >> TAB: DASHBOARD (Thông số Realtime)
    local TabDash = self.Window:AddTab({ Title = "Dashboard", Icon = "home" })
    
    self.Elements.Status = TabDash:AddParagraph({
        Title = "System Status",
        Content = "State: IDLE\nFPS: 60\nPing: 50ms"
    })
    
    self.Elements.TargetInfo = TabDash:AddParagraph({
        Title = "Current Target",
        Content = "Name: None\nDist: 0m\nHealth: 0%"
    })

    self.Elements.LogConsole = TabDash:AddParagraph({
        Title = "Live Logs",
        Content = "[System]: Ready..."
    })

    -- >> TAB: COMBAT (Điều khiển Part 5)
    local TabCombat = self.Window:AddTab({ Title = "Combat AI", Icon = "swords" })
    
    self.Elements.MasterSwitch = TabCombat:AddToggle("MasterSwitch", {Title = "Master Active", Default = false })
    
    TabCombat:AddSection("Targeting")
    
    self.Elements.AttackRange = TabCombat:AddSlider("AttackRange", {
        Title = "Attack Range",
        Description = "Khoảng cách bắt đầu tấn công",
        Default = 50,
        Min = 10,
        Max = 500,
        Rounding = 1,
    })
    
    self.Elements.AimSmooth = TabCombat:AddSlider("AimSmooth", {
        Title = "Aim Smoothness",
        Description = "0 = Legit, 1 = Rage (Lock)",
        Default = 0.2,
        Min = 0,
        Max = 1,
        Rounding = 2,
    })

    -- >> TAB: SETTINGS (Cấu hình Part 2 & 9)
    local TabSettings = self.Window:AddTab({ Title = "Settings", Icon = "settings" })
    
    -- Plugin Selector
    local plugins = {}
    for name, _ in pairs(Titan.PluginSystem.LoadedPlugins) do table.insert(plugins, name) end
    
    self.Elements.PluginSelect = TabSettings:AddDropdown("PluginSelect", {
        Title = "Game Plugin",
        Values = plugins,
        Multi = false,
        Default = "Universal_Generic",
    })
    
    self.Elements.HiveRole = TabSettings:AddDropdown("HiveRole", {
        Title = "Hive Mind Role",
        Values = {"ALONE", "LEADER", "FOLLOWER"},
        Multi = false,
        Default = "ALONE",
    })

    self.Tabs = { Dash = TabDash, Combat = TabCombat, Settings = TabSettings }
end

--// 2. BINDINGS (Kết nối UI với Blackboard) //--
-- Đây là phần quan trọng nhất: Map Event UI -> Event Backend
function UI:BindEvents()
    -- A. UI -> BACKEND (Người dùng bấm nút)
    
    -- 1. Master Switch
    self.Elements.MasterSwitch:OnChanged(function()
        local val = self.Elements.MasterSwitch.Value
        Titan.Blackboard:Set("IsActive", val)
        if val then 
            Titan.Logger:Log("INFO", "UI", "TITAN SYSTEM ACTIVATED")
        else
            Titan.Logger:Log("WARN", "UI", "TITAN SYSTEM PAUSED")
        end
    end)
    
    -- 2. Range Slider
    self.Elements.AttackRange:OnChanged(function()
        Titan.Blackboard:Set("Config_AttackRange", self.Elements.AttackRange.Value)
    end)
    
    -- 3. Aim Smooth
    self.Elements.AimSmooth:OnChanged(function()
        Titan.Blackboard:Set("Config_AimSmooth", self.Elements.AimSmooth.Value)
    end)
    
    -- 4. Plugin Select
    self.Elements.PluginSelect:OnChanged(function()
        Titan.Blackboard:Set("Config_LoadPlugin", self.Elements.PluginSelect.Value)
    end)
    
    -- 5. Hive Role
    self.Elements.HiveRole:OnChanged(function()
        Titan.HiveMind:SetRole(self.Elements.HiveRole.Value)
    end)

    -- B. BACKEND -> UI (Hệ thống tự cập nhật màn hình)
    
    -- 1. Cập nhật Status mỗi khi Blackboard đổi "CombatState"
    Titan.Blackboard:OnChange("CombatState", function(state)
        local ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
        local fps = math.floor(workspace:GetRealPhysicsFPS())
        self.Elements.Status:SetDesc(string.format("State: %s\nFPS: %d | Ping: %dms", state, fps, ping))
    end)
    
    -- 2. Cập nhật Target Info (Từ Part 4 Perception)
    Titan.Blackboard:OnChange("UI_CombatStatus", function(data)
        if data then
            self.Elements.TargetInfo:SetTitle("Locked: " .. data.TargetName)
            self.Elements.TargetInfo:SetDesc(string.format("HP: %s\nDist: %s\nThreat: %s", data.TargetHP, data.Dist, data.ThreatLevel))
        else
            self.Elements.TargetInfo:SetTitle("No Target")
            self.Elements.TargetInfo:SetDesc("Scanning...")
        end
    end)
    
    -- 3. Cập nhật Console Log (Từ Part 1 Logger)
    -- Ta cần inject function vào Logger
    local logHistory = {}
    Titan.Logger.OnLog = function(level, cat, msg)
        local timeStr = os.date("%H:%M:%S")
        local color = (level == "ERROR" and "🔴") or (level == "WARN" and "🟡") or "🔵"
        local line = string.format("[%s] %s [%s]: %s", timeStr, color, cat, msg)
        
        table.insert(logHistory, 1, line) -- Thêm vào đầu
        if #logHistory > 10 then table.remove(logHistory) end -- Giữ 10 dòng
        
        -- Update UI
        if UI.Elements.LogConsole then
            UI.Elements.LogConsole:SetDesc(table.concat(logHistory, "\n"))
        end
    end
end

--// 3. LIFECYCLE //--
function UI:Init(kernel)
    Titan.UI = self
    self:Build()
    self:BindEvents()
    
    -- Chọn tab mặc định
    self.Window:SelectTab(1)
    
    -- Thông báo chào mừng
    Fluent:Notify({
        Title = "Titan AI Loaded",
        Content = "Framework v3.0 initialized successfully.",
        Duration = 5
    })
end

function UI:Start()
    -- Không cần loop, Fluent tự quản lý rendering
end

Titan.Kernel:RegisterModule({
    Name = "Core_UI",
    Priority = Titan.Enums.ModulePriority.LOW, -- Load cuối cùng
    Init = function(self, k) UI:Init(k) end,
    Start = function(self) UI:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 11: SECURITY, BYPASS & DATA PERSISTENCE
    
    Features:
    - HWID Authentication (Giả lập)
    - Anti-Cheat Monitor (Phát hiện lag spike bất thường)
    - Humanoid State Protection (Chống kick khi bay)
    - Config Manager (Save/Load profiles)
]]

local Titan = getgenv().Titan
local HttpService = game:GetService("HttpService")

local Security = {
    Config = {
        AutoSaveInterval = 60, -- Tự lưu mỗi 60s
        ObfuscationMode = true,
        AntiKick = true
    }
}

--// 1. DATA PERSISTENCE (SAVE/LOAD SYSTEM) //--
-- Sử dụng writefile/readfile của Executor
local ConfigManager = {}
ConfigManager.Folder = "Titan_Framework_v3"
ConfigManager.File = "DefaultConfig.json"

function ConfigManager:Init()
    -- Tạo folder nếu chưa có
    if not isfolder(ConfigManager.Folder) then
        makefolder(ConfigManager.Folder)
    end
end

function ConfigManager:Save()
    local data = Titan.Blackboard:Dump()
    
    -- Lọc bớt các dữ liệu runtime (như mục tiêu hiện tại) không cần lưu
    local saveableData = {
        Plugin = Titan.Blackboard:Get("Config_LoadPlugin"),
        Range = Titan.Blackboard:Get("Config_AttackRange"),
        Smooth = Titan.Blackboard:Get("Config_AimSmooth"),
        HiveRole = Titan.Blackboard:Get("MyRole"),
        -- Thêm các config khác
    }
    
    local json = HttpService:JSONEncode(saveableData)
    writefile(self.Folder .. "/" .. self.File, json)
    Titan.Logger:Log("INFO", "System", "Config Saved Successfully.")
end

function ConfigManager:Load()
    local path = self.Folder .. "/" .. self.File
    if isfile(path) then
        local content = readfile(path)
        local success, data = pcall(function() return HttpService:JSONDecode(content) end)
        
        if success and data then
            -- Restore Config
            if data.Range then Titan.Blackboard:Set("Config_AttackRange", data.Range) end
            if data.Smooth then Titan.Blackboard:Set("Config_AimSmooth", data.Smooth) end
            if data.Plugin then 
                -- Delay load plugin để hệ thống sẵn sàng
                task.delay(1, function() Titan.PluginSystem:LoadPlugin(data.Plugin) end)
            end
            Titan.Logger:Log("INFO", "System", "Config Loaded.")
            return true
        end
    end
    return false
end

--// 2. ANTI-CHEAT BYPASS ENGINE //--
local AntiCheat = {}

function AntiCheat:StartMonitor()
    -- 1. Anti-AFK (Tránh bị kick do treo máy 20p)
    game:GetService("Players").LocalPlayer.Idled:Connect(function()
        game:GetService("VirtualUser"):Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        game:GetService("VirtualUser"):Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        Titan.Logger:Log("INFO", "Security", "Anti-AFK Triggered.")
    end)
    
    -- 2. State Protection (Chống kick khi NoClip/Fly)
    -- Nếu game check HumanoidState, ta sẽ spoof nó
    local char = game.Players.LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.StateChanged:Connect(function(old, new)
            -- Nếu game phát hiện đang bay (Physics) mà mình không dùng skill -> Force về Falling
            if new == Enum.HumanoidStateType.PlatformStanding and not Titan.Combat.State.IsAttacking then
                -- Logic bypass tùy game (Placeholder)
            end
        end)
    end
    
    -- 3. Error Trap (Chặn error report gửi về dev game)
    -- ScriptContext.Error:Connect(function(msg, stack, script)
    --     -- Chặn không cho game gửi log lỗi của Titan lên server
    -- end)
end

--// 3. INTEGRATION //--
function Security:Init(kernel)
    Titan.Security = self
    Titan.ConfigManager = ConfigManager
    
    ConfigManager:Init()
end

function Security:Start()
    AntiCheat:StartMonitor()
    
    -- Load config cũ
    ConfigManager:Load()
    
    -- Auto-Save loop
    Titan.Scheduler:Every(self.Config.AutoSaveInterval, function()
        ConfigManager:Save()
    end, "System_AutoSave")
    
    -- Save khi tắt
    game.OnClose = function()
        ConfigManager:Save()
    end
end

Titan.Kernel:RegisterModule({
    Name = "Core_Security",
    Priority = Titan.Enums.ModulePriority.CRITICAL, -- Load rất sớm hoặc rất muộn tùy chiến thuật
    Init = function(self, k) Security:Init(k) end,
    Start = function(self) Security:Start() end
})

return Titan
--[[
    TITAN AI FRAMEWORK v3.0 [PRODUCTION GRADE]
    PART 13: VISUAL DEBUGGER & BLACKBOARD INSPECTOR
    
    Features:
    - 3D Visualizer (Vẽ vòng tròn tầm đánh, đường nối mục tiêu)
    - Decision Tree Viewer (Hiển thị điểm số từng hành động trên đầu nhân vật)
    - Blackboard Inspector (Xem data thô thời gian thực)
]]

local Titan = getgenv().Titan
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Camera = workspace.CurrentCamera

local Debugger = {
    Enabled = false,
    Drawings = {}, -- Quản lý các object vẽ (Line, Circle, Text)
    InspectorUI = nil
}

--// 1. DRAWING API WRAPPER (Visual ESP) //--
local function NewDrawing(type, props)
    local d = Drawing.new(type)
    for k, v in pairs(props) do d[k] = v end
    return d
end

function Debugger:SetupVisuals()
    -- 1. Vòng tròn tầm đánh (Attack Range)
    self.Drawings.RangeCircle = NewDrawing("Circle", {
        Color = Color3.fromRGB(0, 255, 0),
        Thickness = 1,
        NumSides = 64,
        Radius = 50,
        Visible = false
    })

    -- 2. Đường nối mục tiêu (Target Tracer)
    self.Drawings.TargetLine = NewDrawing("Line", {
        Color = Color3.fromRGB(255, 0, 0),
        Thickness = 1.5,
        Transparency = 1,
        Visible = false
    })

    -- 3. Text hiển thị suy nghĩ (Brain State)
    self.Drawings.BrainText = NewDrawing("Text", {
        Text = "THINKING...",
        Size = 18,
        Center = true,
        Outline = true,
        Color = Color3.fromRGB(255, 255, 0),
        Visible = false
    })
end

function Debugger:UpdateVisuals()
    if not self.Enabled then 
        for _, d in pairs(self.Drawings) do d.Visible = false end
        return 
    end

    local myRoot = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    -- Update Range Circle
    local range = Titan.Blackboard:Get("Config_AttackRange", 50)
    local screenPos, onScreen = Camera:WorldToViewportPoint(myRoot.Position)
    
    if onScreen then
        self.Drawings.RangeCircle.Visible = true
        self.Drawings.RangeCircle.Position = Vector2.new(screenPos.X, screenPos.Y)
        -- Công thức tính bán kính trên màn hình dựa trên FOV và khoảng cách (Ước lượng)
        self.Drawings.RangeCircle.Radius = (range * 500) / screenPos.Z 
    else
        self.Drawings.RangeCircle.Visible = false
    end

    -- Update Target Line
    local target = Titan.Blackboard:Get("CurrentTarget")
    if target and target:FindFirstChild("HumanoidRootPart") then
        local tPos, tOnScreen = Camera:WorldToViewportPoint(target.HumanoidRootPart.Position)
        if onScreen and tOnScreen then
            self.Drawings.TargetLine.Visible = true
            self.Drawings.TargetLine.From = Vector2.new(screenPos.X, screenPos.Y)
            self.Drawings.TargetLine.To = Vector2.new(tPos.X, tPos.Y)
        else
            self.Drawings.TargetLine.Visible = false
        end
    else
        self.Drawings.TargetLine.Visible = false
    end

    -- Update Brain Text (Decision Viewer)
    local currentAction = Titan.Blackboard:Get("CurrentDecision", "Idle")
    local scores = Titan.Blackboard:Get("Brain_DebugScores", {})
    
    -- Format text: "State: ATTACK | Score: 1.5"
    local debugText = string.format("[STATE]: %s", string.upper(currentAction))
    
    -- Thêm chi tiết điểm số (Decision Tree Viewer đơn giản hóa)
    for action, score in pairs(scores) do
        if action ~= currentAction then
            debugText = debugText .. string.format("\n%s: %.2f", action, score)
        end
    end
    
    self.Drawings.BrainText.Visible = true
    self.Drawings.BrainText.Position = Vector2.new(screenPos.X, screenPos.Y - 50) -- Hiện trên đầu
    self.Drawings.BrainText.Text = debugText
end

--// 2. BLACKBOARD VIEWER (UI INSPECTOR) //--
-- Tạo một cửa sổ GUI riêng để soi biến số
function Debugger:CreateInspector()
    if self.InspectorUI then return end
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "TitanInspector"
    ScreenGui.Parent = CoreGui
    
    local Frame = Instance.new("ScrollingFrame")
    Frame.Name = "BlackboardList"
    Frame.Size = UDim2.new(0, 250, 0, 400)
    Frame.Position = UDim2.new(1, -260, 0.5, -200) -- Bên phải màn hình
    Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Frame.BackgroundTransparency = 0.5
    Frame.BorderSizePixel = 0
    Frame.Parent = ScreenGui
    
    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Parent = Frame
    UIListLayout.SortOrder = Enum.SortOrder.Name
    
    self.InspectorUI = {Gui = ScreenGui, Frame = Frame, Labels = {}}
    
    -- Update loop cho UI
    Titan.Scheduler:Every(0.5, function()
        if not self.Enabled then 
            ScreenGui.Enabled = false
            return 
        end
        ScreenGui.Enabled = true
        
        local data = Titan.Blackboard:Dump()
        
        -- Tạo hoặc update label cho từng key
        for key, val in pairs(data) do
            local valStr = tostring(val)
            if type(val) == "table" then valStr = "{Table...}" end
            if type(val) == "userdata" then valStr = tostring(val) end
            
            local text = string.format(" %s: %s", key, valStr)
            
            if not self.InspectorUI.Labels[key] then
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, 0, 0, 20)
                lbl.BackgroundTransparency = 1
                lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Parent = Frame
                self.InspectorUI.Labels[key] = lbl
            end
            
            self.InspectorUI.Labels[key].Text = text
            
            -- Highlight màu nếu key là Target hoặc State
            if key == "CurrentDecision" then 
                self.InspectorUI.Labels[key].TextColor3 = Color3.fromRGB(0, 255, 0)
            else
                self.InspectorUI.Labels[key].TextColor3 = Color3.fromRGB(200, 200, 200)
            end
        end
    end, "Debug_InspectorUpdate")
end

--// 3. INTEGRATION //--
function Debugger:Init(kernel)
    Titan.Debugger = self
    self:SetupVisuals()
    self:CreateInspector()
    
    -- Thêm Toggle vào UI chính (Inject vào Settings Tab của Part 10)
    -- Do UI Fluent đã load xong, ta có thể truy cập Titan.UI.Tabs.Settings
    task.delay(2, function()
        if Titan.UI and Titan.UI.Tabs and Titan.UI.Tabs.Settings then
             Titan.UI.Tabs.Settings:AddToggle("DebugMode", {Title = "Enable Debug Mode", Default = false }):OnChanged(function(v)
                self.Enabled = v
             end)
        end
    end)
end

function Debugger:Start()
    RunService.RenderStepped:Connect(function()
        self:UpdateVisuals()
    end)
end

Titan.Kernel:RegisterModule({
    Name = "DevTools_Debugger",
    Priority = Titan.Enums.ModulePriority.BACKGROUND,
    Init = function(self, k) Debugger:Init(k) end,
    Start = function(self) Debugger:Start() end
})

return Titan
--------------------------------------------------
-- TITAN AI : PROFESSIONAL CONTROL DASHBOARD
--------------------------------------------------

task.spawn(function()

    --------------------------------------------------
    -- WAIT GAME LOAD
    --------------------------------------------------
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    --------------------------------------------------
    -- VERIFY FRAMEWORK
    --------------------------------------------------
    if not getgenv().Titan then
        warn("[TitanUI] Titan Framework not found")
        return
    end

    local Titan = getgenv().Titan

    --------------------------------------------------
    -- SAFE LOAD UI LIB
    --------------------------------------------------
    local success, Rayfield = pcall(function()
        return loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/shlexware/Rayfield/main/source"
        ))()
    end)

    if not success then
        warn("[TitanUI] Failed to load Rayfield")
        return
    end


    --------------------------------------------------
    -- MAIN WINDOW
    --------------------------------------------------
    local Window = Rayfield:CreateWindow({

        Name = "Titan AI Framework",
        LoadingTitle = "Titan System",
        LoadingSubtitle = "Combat Automation Suite",

        ConfigurationSaving = {
            Enabled = true,
            FolderName = "TitanFramework",
            FileName = "Dashboard"
        },

        Discord = {
            Enabled = false
        },

        KeySystem = false
    })


    --------------------------------------------------
    -- GLOBAL STATES
    --------------------------------------------------
    local State = {
        Enabled = true,
        Aggression = 0.5,
        Range = 30,
        Delay = 0.2
    }


    --------------------------------------------------
    -- MAIN TAB
    --------------------------------------------------
    local MainTab = Window:CreateTab("Main", 4483362458)

    MainTab:CreateToggle({
        Name = "Enable AI Core",
        CurrentValue = true,
        Callback = function(v)

            State.Enabled = v

            if Titan.Blackboard then
                Titan.Blackboard:Set("SystemEnabled", v)
            end

        end
    })


    MainTab:CreateParagraph({
        Title = "System Status",
        Content = "Titan AI Core Running"
    })


    --------------------------------------------------
    -- COMBAT TAB
    --------------------------------------------------
    local CombatTab = Window:CreateTab("Combat", 4483362458)


    CombatTab:CreateSlider({

        Name = "Combat Range",

        Range = {5, 150},

        Increment = 1,

        CurrentValue = 30,

        Callback = function(v)

            State.Range = v

            if Titan.Config then
                Titan.Config.Range = v
            end

        end
    })


    CombatTab:CreateSlider({

        Name = "Attack Delay",

        Range = {0, 1},

        Increment = 0.01,

        CurrentValue = 0.2,

        Callback = function(v)

            State.Delay = v

            if Titan.Config then
                Titan.Config.Delay = v
            end

        end
    })


    CombatTab:CreateSlider({

        Name = "Aggression Level",

        Range = {0, 1},

        Increment = 0.05,

        CurrentValue = 0.5,

        Callback = function(v)

            State.Aggression = v

            if Titan.Brain then
                Titan.Brain.Aggression = v
            end

        end
    })


    CombatTab:CreateDropdown({

        Name = "Combat Mode",

        Options = {
            "Passive",
            "Balanced",
            "Aggressive",
            "Rage"
        },

        CurrentOption = "Balanced",

        Callback = function(v)

            if Titan.Brain then
                Titan.Brain.Mode = v
            end

        end
    })


    --------------------------------------------------
    -- SQUAD TAB
    --------------------------------------------------
    local SquadTab = Window:CreateTab("Squad", 4483362458)


    SquadTab:CreateDropdown({

        Name = "Formation",

        Options = {
            "Line",
            "Circle",
            "Wedge",
            "Surround"
        },

        CurrentOption = "Circle",

        Callback = function(v)

            if Titan.Squad then
                Titan.Squad.Formation = v
            end

        end
    })


    SquadTab:CreateToggle({

        Name = "Focus Fire",

        CurrentValue = true,

        Callback = function(v)

            if Titan.Squad then
                Titan.Squad.Focus = v
            end

        end
    })


    --------------------------------------------------
    -- CONFIG TAB
    --------------------------------------------------
    local ConfigTab = Window:CreateTab("Config", 4483362458)


    ConfigTab:CreateButton({

        Name = "Save Profile",

        Callback = function()
            Rayfield:SaveConfiguration()
        end
    })


    ConfigTab:CreateButton({

        Name = "Load Profile",

        Callback = function()
            Rayfield:LoadConfiguration()
        end
    })


    ConfigTab:CreateButton({

        Name = "Auto Tune System",

        Callback = function()

            if Titan.AutoTune then
                Titan:AutoTune()
            end

        end
    })


    --------------------------------------------------
    -- DEBUG TAB
    --------------------------------------------------
    local DebugTab = Window:CreateTab("Debug", 4483362458)


    DebugTab:CreateButton({

        Name = "Dump Blackboard",

        Callback = function()

            if not Titan.Blackboard then
                warn("No Blackboard")
                return
            end

            warn("===== BLACKBOARD =====")

            for k,v in pairs(Titan.Blackboard._data) do
                print(k,v)
            end

        end
    })


    DebugTab:CreateButton({

        Name = "Reload Framework",

        Callback = function()

            Rayfield:Destroy()

            loadstring(game:HttpGet(
                "https://raw.githubusercontent.com/HieuLon/HieuCute/main/Titan_Locomotion_v3.lua"
            ))()

        end
    })


    --------------------------------------------------
    -- MONITOR TAB
    --------------------------------------------------
    local MonitorTab = Window:CreateTab("Monitor", 4483362458)


    local Status = MonitorTab:CreateParagraph({
        Title = "Live Monitor",
        Content = "Initializing..."
    })


    task.spawn(function()

        while task.wait(1) do

            if not getgenv().Titan then
                Status:Set("System Offline")
                continue
            end

            local txt = ""

            if Titan.Blackboard then
                txt ..= "Target: " .. tostring(Titan.Blackboard:Get("Target")) .. "\n"
                txt ..= "State: " .. tostring(Titan.Blackboard:Get("State")) .. "\n"
            end

            if Titan.Brain then
                txt ..= "Mode: " .. tostring(Titan.Brain.Mode) .. "\n"
            end

            Status:Set(txt)

        end

    end)


    --------------------------------------------------
    -- READY
    --------------------------------------------------
    Rayfield:Notify({
        Title = "Titan AI",
        Content = "Dashboard Loaded",
        Duration = 4
    })


end)
