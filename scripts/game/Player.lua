-- ============================================================================
-- Player.lua - 玩家数据 + 更新 + 绘制
-- ============================================================================

local Renderer     = require "game.Renderer"
local Input        = require "game.InputHandler"
local Tween        = require "lib.Tween"
local Xingye       = require "game.characters.Xingye"
local Chenxi       = require "game.characters.Chenxi"
local ChenxiCtrl   = require "game.characters.ChenxiController"
local SkillState   = require "game.SkillState"
local ConfigLoader = require "config.ConfigLoader"

local M = {}

-- ——— 角色切换系统 ———
local CHARACTER_XINGYE = "xingye"
local CHARACTER_CHENXI = "chenxi"
local activeCharacter_ = CHARACTER_XINGYE
local chenxiUnlocked_  = true  -- 默认解锁（调试用）
local switchAnim_ = { active = false, timer = 0, from = "", to = "" }
local SWITCH_ANIM_DURATION = 0.3

-- 地图边距（与 Renderer.drawMapBoundary 一致）
local MAP_MARGIN = 28

-- ——— 配置（从 JSON 加载） ———
local function loadCFG()
    local data = ConfigLoader.load("config/characters/protagonist.json")
    if not data then
        print("[Player] WARN: 无法加载角色配置，使用兜底值")
        return {
            radius = 18, grazeRadius = 42, speed = 280, maxHp = 100,
            energy = { max = 3.0, regenRate = 1.0, btCostRate = 1.0, minToStart = 1.0, cooldown = 0 },
            stealRadiusBase = 18, stealRadiusByLevel = { 48, 64, 96 },
            stealSlowFactor = 0.85, stealDeflectDeg = 5,
            orbitRadius = 48, orbitRadiusStep = 22, orbitPerLayer = 12,
            orbitAngularSpeed = 2.4, orbitDamage = 1,
        }
    end
    return data.base
end

local CFG = loadCFG()

---@type table
local data = {}

local W_, H_ = 0, 0

-- BT 结束回调列表
local btEndCallbacks_ = {}

--- 注册 BT 结束回调（D线光束释放等）
---@param fn fun()
function M.onBTEnd(fn)
    btEndCallbacks_[#btEndCallbacks_ + 1] = fn
end

--- 内部：触发所有 BT 结束回调
local function fireBTEnd()
    for _, fn in ipairs(btEndCallbacks_) do
        fn()
    end
end

function M.init(_W, _H)
    W_ = _W
    H_ = _H
    M.reset(_W, _H)
end

function M.reset(_W, _H)
    W_ = _W or W_
    H_ = _H or H_
    data = {
        x             = W_ * 0.5,
        y             = H_ * 0.5,
        radius        = CFG.radius,
        grazeRadius   = CFG.grazeRadius,
        stealRadius   = CFG.stealRadiusBase,  -- 动态: 受B线等级影响
        hp            = CFG.maxHp,
        maxHp         = CFG.maxHp,
        energy        = CFG.energy.max,
        energyCooldown = 0,
        bulletTimeActive = false,
        orbitAngle    = 0,
        orbitDamage   = CFG.orbitDamage,
        killCount     = 0,   -- 仅统计轨道子弹击杀
        coins         = 0,
        lastMoveAngle = 0,   -- 最后移动方向（弧度），用于自动瞄准 fallback
        -- 升级加成
        speedMult     = 1.0,
        orbitDamageMult = 1.0,
        energyRegenMult = 1.0,
        energyCostMult  = 1.0,
        energyMaxMult   = 1.0,
        -- 视觉动画
        hitFlash      = 0,
        btPulse       = 0,
        age           = 0,
        -- 伪3D偏转
        dir           = 1,        -- 整体朝向 1=右 -1=左
        face_yaw      = 0,        -- 当前偏转量(0~0.6)
        face_target_yaw = 0,      -- 目标偏转量
    }
    print("[Player] 重置完毕，位置:", data.x, data.y)
end

function M.getData()
    return data
end

function M.getCFG()
    return CFG
end

function M.update(dt)
    -- 0. 角色切换动画更新
    if switchAnim_.active then
        switchAnim_.timer = switchAnim_.timer + dt
        if switchAnim_.timer >= SWITCH_ANIM_DURATION then
            switchAnim_.active = false
            switchAnim_.timer = 0
        end
    end

    -- 0.5. 角色切换输入检测（Tab键）
    if Input.isSwitchPressed and Input.isSwitchPressed() then
        M.switchCharacter()
    end

    -- 1. B线偷取范围更新（仅星夜有效）
    if activeCharacter_ == CHARACTER_XINGYE then
        local bLevel = SkillState.getLevel("steal")
        if bLevel > 0 and CFG.stealRadiusByLevel[bLevel] then
            data.stealRadius = CFG.stealRadiusByLevel[bLevel]
        else
            data.stealRadius = CFG.stealRadiusBase
        end
    end

    -- 2. 移动（发射时不再强制停步）
    -- 鼠标/触摸：拖拽多少像素就移动多少像素（1:1，方便擦弹精确控制）
    local mdx, mdy = Input.dragDelta()
    data.x = data.x + mdx
    data.y = data.y + mdy

    -- 键盘 WASD/方向键：速度已在 InputHandler 中按 dt 缩放
    local kdx, kdy = Input.keyboardDelta()
    data.x = data.x + kdx
    data.y = data.y + kdy

    -- 记录最后移动方向（有位移时更新）
    local totalDx = mdx + kdx
    local totalDy = mdy + kdy
    if totalDx * totalDx + totalDy * totalDy > 0.5 then
        data.lastMoveAngle = math.atan(totalDy, totalDx)
    end

    -- 3. 边界限制
    local margin = MAP_MARGIN + data.radius
    data.x = math.max(margin, math.min(W_ - margin, data.x))
    data.y = math.max(margin, math.min(H_ - margin, data.y))

    -- 4. 能量系统（分角色处理）
    if activeCharacter_ == CHARACTER_XINGYE then
        -- 星夜：标准BT能量
        local enCFG = CFG.energy
        local energyMax = enCFG.max * (data.energyMaxMult or 1)
        if data.bulletTimeActive then
            data.energy = data.energy - enCFG.btCostRate * (data.energyCostMult or 1) * dt
            if data.energy <= 0 then
                data.energy = 0
                data.bulletTimeActive = false
                data.energyCooldown   = enCFG.cooldown
                fireBTEnd()
                print("[Player] 子弹时间: 能量耗尽，进入冷却")
            end
        else
            -- 自然恢复
            if data.energyCooldown > 0 then
                data.energyCooldown = data.energyCooldown - dt
            else
                data.energy = math.min(energyMax,
                    data.energy + enCFG.regenRate * (data.energyRegenMult or 1) * dt)
            end
            -- 检测开启子弹时间
            if Input.isBulletTimeHeld()
                and data.energy >= enCFG.minToStart
                and data.energyCooldown <= 0 then
                data.bulletTimeActive = true
                print("[Player] 子弹时间: 开启")
            end
        end
    else
        -- 晨曦：ChenxiCtrl 管理能量和BT
        ChenxiCtrl.update(dt, data)
        -- 同步BT状态到 data（供外部读取）
        data.bulletTimeActive = ChenxiCtrl.isBTActive()
    end

    -- 5. 轨道角度旋转
    data.orbitAngle = data.orbitAngle
        + CFG.orbitAngularSpeed * dt

    -- 6. 视觉动画衰减
    data.hitFlash = math.max(0, data.hitFlash - dt * 3.0)
    data.btPulse  = data.btPulse + dt * 3.0
    data.age      = data.age + dt

    -- 7. 伪3D朝向 & 偏转
    if totalDx > 0.5 then
        if data.dir ~= 1 then
            data.face_yaw = 0  -- 方向切换时重置偏转，避免镜像跳变
        end
        data.dir = 1
        data.face_target_yaw = 0.6
    elseif totalDx < -0.5 then
        if data.dir ~= -1 then
            data.face_yaw = 0  -- 方向切换时重置偏转，避免镜像跳变
        end
        data.dir = -1
        data.face_target_yaw = 0.6
    else
        data.face_target_yaw = 0.0  -- 静止时回正
    end
    data.face_yaw = data.face_yaw + (data.face_target_yaw - data.face_yaw) * math.min(1.0, dt * 6)
end

-- 受伤
function M.takeDamage(dmg)
    if data.bulletTimeActive then return end  -- 无敌
    data.hp = math.max(0, data.hp - dmg)
    data.hitFlash = 1.0
    print("[Player] 受伤 -" .. dmg .. " HP剩余:" .. data.hp)
end

-- 治疗
function M.heal(amount)
    data.hp = math.min(data.maxHp, data.hp + amount)
end

-- 加能量
function M.addEnergy(amount)
    local energyMax = CFG.energy.max * (data.energyMaxMult or 1)
    data.energy = math.min(energyMax, data.energy + amount)
end

-- 夺取子弹（动画由 BulletManager 处理，这里只触发视觉）
function M.onSteal()
    data.btPulse = 0  -- 脉冲重置
end

-- 加金币
function M.addCoins(n)
    data.coins = data.coins + n
end

-- ——— 自动瞄准系统 ———
local LOCK_RADIUS = 260  -- 自动锁定半径（逻辑像素）
local LOCK_STICKY_TIME = 0.15  -- 锁定粘滞时间（秒），防抖动切换
local lockTarget_ = nil  -- 当前锁定的敌人引用
local lockTimer_  = 0    -- 粘滞计时器

function M.getLockRadius()
    return LOCK_RADIUS
end

-- 获取当前发射方向（自动瞄准：近程锁敌，远程用移动方向）
-- 返回 angle(弧度), lockedEnemy(table|nil)
function M.getFireDirection()
    -- 防御：Player 尚未初始化时返回默认方向
    if not data.x then
        return 0, nil
    end

    local EnemyMgr = require("game.EnemyManager")
    local enemies = EnemyMgr.getEnemies()

    -- 寻找锁定范围内最近的敌人
    local bestEnemy = nil
    local bestDist  = LOCK_RADIUS

    for _, e in ipairs(enemies) do
        if not e.dead then
            local dx = e.x - data.x
            local dy = e.y - data.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < bestDist then
                bestDist  = dist
                bestEnemy = e
            end
        end
    end

    -- 粘滞逻辑：如果当前有锁定目标且仍在范围内，短时间内不切换
    if lockTarget_ and not lockTarget_.dead and lockTarget_.x then
        local dx = lockTarget_.x - data.x
        local dy = lockTarget_.y - data.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < LOCK_RADIUS * 1.2 then  -- 稍微宽松一点防止边缘抖动
            if bestEnemy ~= lockTarget_ then
                lockTimer_ = lockTimer_ - (1.0 / 60.0)  -- 近似每帧
                if lockTimer_ > 0 then
                    bestEnemy = lockTarget_  -- 维持当前目标
                else
                    lockTimer_ = LOCK_STICKY_TIME
                    lockTarget_ = bestEnemy
                end
            else
                lockTimer_ = LOCK_STICKY_TIME
            end
        else
            -- 当前目标超出范围，立即切换
            lockTarget_ = bestEnemy
            lockTimer_  = LOCK_STICKY_TIME
        end
    else
        lockTarget_ = bestEnemy
        lockTimer_  = LOCK_STICKY_TIME
    end

    if bestEnemy then
        local angle = math.atan(bestEnemy.y - data.y, bestEnemy.x - data.x)
        return angle, bestEnemy
    end

    -- 无敌人在范围内，使用最后移动方向
    return data.lastMoveAngle, nil
end

-- 轨道击杀计数（由 EnemyManager 调用）
function M.addOrbitKill()
    data.killCount = data.killCount + 1
end

function M.getKillCount()
    return data.killCount
end

-- ——— 角色切换系统 API ———

--- 获取当前激活角色
---@return string "xingye"|"chenxi"
function M.getActiveCharacter()
    return activeCharacter_
end

--- 晨曦是否已解锁
function M.isChenxiUnlocked()
    return chenxiUnlocked_
end

--- 解锁晨曦（局内触发，如达成某条件后）
function M.unlockChenxi()
    if not chenxiUnlocked_ then
        chenxiUnlocked_ = true
        print("[Player] 晨曦已解锁！按 Tab 切换角色")
    end
end

--- 切换角色
function M.switchCharacter()
    if not chenxiUnlocked_ then return end
    if switchAnim_.active then return end  -- 切换动画播放中不可再切

    local from = activeCharacter_
    local to
    if activeCharacter_ == CHARACTER_XINGYE then
        to = CHARACTER_CHENXI
        -- 切入晨曦时通知控制器
        ChenxiCtrl.onSwitchIn()
    else
        to = CHARACTER_XINGYE
        -- 切出晨曦时通知控制器
        ChenxiCtrl.onSwitchOut()
    end

    activeCharacter_ = to
    switchAnim_.active = true
    switchAnim_.timer = 0
    switchAnim_.from = from
    switchAnim_.to = to
    print("[Player] 角色切换:", from, "→", to)
end

--- 获取晨曦控制器引用（供 main.lua 交互用）
function M.getChenxiCtrl()
    return ChenxiCtrl
end

--- 获取切换动画状态（供绘制用）
function M.getSwitchAnim()
    return switchAnim_
end



function M.draw(vg)
    local p = data

    -- 切换闪烁动画
    if switchAnim_.active then
        local t = switchAnim_.timer / SWITCH_ANIM_DURATION
        -- 闪白效果
        local flashAlpha = 0
        if t < 0.3 then
            flashAlpha = t / 0.3  -- 淡入
        elseif t < 0.7 then
            flashAlpha = 1.0      -- 持续
        else
            flashAlpha = 1.0 - (t - 0.7) / 0.3  -- 淡出
        end
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, p.radius + 6)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, flashAlpha * 0.6))
        nvgFill(vg)
    end

    -- 子弹时间光晕（颜色分角色）
    if p.bulletTimeActive then
        local pulse = math.abs(math.sin(p.btPulse))
        local glowR = p.radius + 10 + pulse * 8
        local gr, gg, gb  -- 光晕颜色
        if activeCharacter_ == CHARACTER_CHENXI then
            gr, gg, gb = 1.0, 0.75, 0.2  -- 金色
        else
            gr, gg, gb = 0.3, 0.9, 1.0   -- 青色
        end
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, glowR)
        nvgFillColor(vg, nvgRGBAf(gr, gg, gb, 0.15 + pulse * 0.1))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, glowR)
        nvgStrokeColor(vg, nvgRGBAf(gr, gg, gb, 0.5 + pulse * 0.3))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 绘制角色（根据当前激活角色）
    if activeCharacter_ == CHARACTER_CHENXI then
        Chenxi.draw(vg, p.x, p.y, p.radius, p.hitFlash, p.age, p.dir, p.face_yaw)
    else
        Xingye.draw(vg, p.x, p.y, p.radius, p.hitFlash, p.age, p.dir, p.face_yaw)
    end

    -- 能量环（颜色分角色）
    if activeCharacter_ == CHARACTER_CHENXI then
        -- 晨曦能量环：金色系
        local cxEnergy = ChenxiCtrl.getEnergy()
        local cxMax    = ChenxiCtrl.getEnergyMax()
        drawChenxiEnergyRing(vg, p.x, p.y, p.radius + 8, cxEnergy, cxMax,
            ChenxiCtrl.isBTActive())
    else
        -- 星夜能量环：青色系
        local enMax = CFG.energy.max * (p.energyMaxMult or 1)
        drawEnergyRing(vg, p.x, p.y, p.radius + 8, p.energy, enMax,
            p.bulletTimeActive, p.energyCooldown)
    end

    -- 自动锁定范围（白色虚线圆环，仅星夜射击模式显示）
    if activeCharacter_ == CHARACTER_XINGYE then
        drawLockRangeCircle(vg, p.x, p.y, LOCK_RADIUS)
    end
end

-- 绘制正六边形（带描边）
function drawHexagon(vg, cx, cy, r, fr, fg, fb, sr, sg, sb)
    nvgBeginPath(vg)
    for i = 0, 5 do
        local a = i * math.pi / 3 - math.pi / 6
        local px = cx + math.cos(a) * r
        local py = cy + math.sin(a) * r
        if i == 0 then
            nvgMoveTo(vg, px, py)
        else
            nvgLineTo(vg, px, py)
        end
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(fr, fg, fb, 1.0))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(0.4, 0.85, 1.0, 0.9))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)
end

-- 绘制能量环（双色：基础青色 + 溢出紫色）
function drawEnergyRing(vg, cx, cy, r, energy, energyMax, btActive, cooldown)
    local baseMax = CFG.energy.max          -- 初始上限（3秒）
    local ratio = energy / energyMax        -- 归一化 0~1
    local fullArc = math.pi * 2

    -- 背景环（暗灰满圈）
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, r, -math.pi * 0.5, math.pi * 1.5, NVG_CW)
    nvgStrokeColor(vg, nvgRGBAf(0.2, 0.2, 0.3, 0.5))
    nvgStrokeWidth(vg, 3.5)
    nvgStroke(vg)

    if ratio < 0.01 then return end

    -- 颜色选择
    local er, eg, eb, ea
    if cooldown > 0 then
        local flicker = 0.4 + math.abs(math.sin(cooldown * 8)) * 0.3
        er, eg, eb, ea = 0.35, 0.35, 0.4, flicker
    elseif btActive then
        er, eg, eb, ea = 0.3, 1.0, 0.9, 1.0
    elseif ratio < 0.33 then
        er, eg, eb, ea = 0.8, 0.4, 0.1, 0.8
    else
        er, eg, eb, ea = 0.3, 0.85, 0.95, 0.9
    end

    -- 计算基础段和溢出段
    local baseRatio = baseMax / energyMax   -- 基础容量占满圈的比例
    local baseFill = math.min(ratio, baseRatio) / baseRatio  -- 基础段填充 0~1
    local baseArc = baseFill * baseRatio * fullArc

    -- 绘制基础段（青色）
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, r, -math.pi * 0.5, -math.pi * 0.5 + baseArc, NVG_CW)
    nvgStrokeColor(vg, nvgRGBAf(er, eg, eb, ea))
    nvgStrokeWidth(vg, 3.5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 溢出段（紫色，仅在有升级且能量超过基础上限时显示）
    if energyMax > baseMax and energy > baseMax then
        local overflowRatio = (energy - baseMax) / (energyMax - baseMax)  -- 溢出部分填充 0~1
        local overflowArc = overflowRatio * (1 - baseRatio) * fullArc
        local startAngle = -math.pi * 0.5 + baseRatio * fullArc
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r, startAngle, startAngle + overflowArc, NVG_CW)
        -- 紫色：BT激活时更亮
        local pa = btActive and 1.0 or 0.85
        nvgStrokeColor(vg, nvgRGBAf(0.7, 0.3, 1.0, pa))
        nvgStrokeWidth(vg, 3.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    end
end

-- 绘制晨曦能量环（三段式金色系）
function drawChenxiEnergyRing(vg, cx, cy, r, energy, energyMax, btActive)
    local ratio = energy / energyMax
    local fullArc = math.pi * 2

    -- 背景环（暗灰满圈）
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, r, -math.pi * 0.5, math.pi * 1.5, NVG_CW)
    nvgStrokeColor(vg, nvgRGBAf(0.2, 0.2, 0.3, 0.5))
    nvgStrokeWidth(vg, 3.5)
    nvgStroke(vg)

    if ratio < 0.01 then return end

    -- 获取能量段
    local segName = ChenxiCtrl.getEnergySegment()

    -- 颜色根据段位变化
    local er, eg, eb, ea
    if btActive then
        -- BT激活：明亮金色
        er, eg, eb, ea = 1.0, 0.85, 0.3, 1.0
    elseif segName == "full" then
        -- 满能量段：亮金
        er, eg, eb, ea = 1.0, 0.75, 0.2, 0.95
    elseif segName == "normal" then
        -- 标准段：琥珀
        er, eg, eb, ea = 0.9, 0.6, 0.15, 0.85
    else
        -- 衰减段：暗橙
        er, eg, eb, ea = 0.7, 0.4, 0.1, 0.7
    end

    -- 绘制能量弧
    local arc = ratio * fullArc
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, r, -math.pi * 0.5, -math.pi * 0.5 + arc, NVG_CW)
    nvgStrokeColor(vg, nvgRGBAf(er, eg, eb, ea))
    nvgStrokeWidth(vg, 3.5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 段位分界线标记（30%和60%处的刻度）
    local thresholds = { 0.3, 0.6 }
    for _, th in ipairs(thresholds) do
        local a = -math.pi * 0.5 + th * fullArc
        local ix = cx + math.cos(a) * (r - 4)
        local iy = cy + math.sin(a) * (r - 4)
        local ox = cx + math.cos(a) * (r + 4)
        local oy = cy + math.sin(a) * (r + 4)
        nvgBeginPath(vg)
        nvgMoveTo(vg, ix, iy)
        nvgLineTo(vg, ox, oy)
        nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.4))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
end

-- 绘制粗胶囊段虚线圆环（锁定范围）
function drawLockRangeCircle(vg, cx, cy, radius)
    local segments = 16
    local gapRatio = 0.45  -- 间隔占比
    local arcLen = (math.pi * 2) / segments
    local drawLen = arcLen * (1 - gapRatio)
    local thickness = 4.5  -- 胶囊粗度

    nvgLineCap(vg, NVG_ROUND)  -- 圆头 = 胶囊形状
    nvgStrokeColor(vg, nvgRGBAf(1.0, 1.0, 1.0, 0.2))
    nvgStrokeWidth(vg, thickness)

    for i = 0, segments - 1 do
        local startA = i * arcLen - math.pi * 0.5
        local endA   = startA + drawLen
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, radius, startA, endA, NVG_CW)
        nvgStroke(vg)
    end
end

-- 绘制胶囊段虚线直线（从 sx,sy 到 ex,ey）
-- 用于发射方向指示、锁定激光等
function drawCapsuleDashLine(vg, sx, sy, ex, ey, color, thickness, dashLen, gapLen)
    thickness = thickness or 5
    dashLen   = dashLen or 12
    gapLen    = gapLen or 8

    local dx = ex - sx
    local dy = ey - sy
    local totalLen = math.sqrt(dx * dx + dy * dy)
    if totalLen < 1 then return end

    local nx = dx / totalLen
    local ny = dy / totalLen
    local step = dashLen + gapLen

    nvgLineCap(vg, NVG_ROUND)
    nvgStrokeColor(vg, color)
    nvgStrokeWidth(vg, thickness)

    local pos = 0
    while pos < totalLen do
        local segEnd = math.min(pos + dashLen, totalLen)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + nx * pos, sy + ny * pos)
        nvgLineTo(vg, sx + nx * segEnd, sy + ny * segEnd)
        nvgStroke(vg)
        pos = pos + step
    end
end

-- 绘制胶囊风格箭头（方向指示器末端）
function drawCapsuleArrow(vg, tipX, tipY, angle, color, size)
    size = size or 10
    local thickness = size * 0.7

    -- 箭头两条短斜线（粗圆头）
    local armAngle = 2.6  -- 约 150° 张开
    local armLen   = size

    nvgLineCap(vg, NVG_ROUND)
    nvgStrokeColor(vg, color)
    nvgStrokeWidth(vg, thickness)

    -- 左臂
    nvgBeginPath(vg)
    nvgMoveTo(vg, tipX, tipY)
    nvgLineTo(vg,
        tipX + math.cos(angle + armAngle) * armLen,
        tipY + math.sin(angle + armAngle) * armLen)
    nvgStroke(vg)

    -- 右臂
    nvgBeginPath(vg)
    nvgMoveTo(vg, tipX, tipY)
    nvgLineTo(vg,
        tipX + math.cos(angle - armAngle) * armLen,
        tipY + math.sin(angle - armAngle) * armLen)
    nvgStroke(vg)
end

return M
