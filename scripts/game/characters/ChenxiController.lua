-- ============================================================================
-- ChenxiController.lua - 晨曦战斗逻辑控制器
-- 管理：基础斩击、强化斩击(能量分段)、充能转化、清弹回能、收尾攻击
-- ============================================================================

local SkillState   = require "game.SkillState"
local ConfigLoader = require "config.ConfigLoader"
local Input        = require "game.InputHandler"

local M = {}

-- ——— 配置 ———
local function loadCFG()
    local data = ConfigLoader.load("config/characters/chenxi.json")
    if not data then
        print("[ChenxiCtrl] WARN: 无法加载配置，使用兜底值")
        return {
            energy = { max = 1.0, regenRate = 0, btCostRate = 0.18, minToStart = 0.15, cooldown = 0 },
            slash = { baseDamage = 3, cooldownPerEnemy = 0.5, arcDeg = 60, range = 32, knockback = 12 },
            enhancedSlash = {
                segments = {
                    full   = { threshold = 0.6, mult = 3.0, cost = 0.08 },
                    normal = { threshold = 0.3, mult = 2.0, cost = 0.05 },
                    decay  = { threshold = 0.0, mult = 1.3, cost = 0.02 },
                },
                arcDeg = 90, range = 42, knockback = 22,
            },
            chargeConvert = { autoOnSwitch = 4, manualInterval = 0.2, autoChargeSpeedMult = 0.5, chargeRetryInterval = 0.1, energyPerBullet = 0.08 },
            burnPath = { minDist = 8 },
            clearBullet = { energyPerClear = 0.02 },
            finisher = { maxSlashCount = 30 },
        }
    end
    return data.base
end

local CFG = loadCFG()

-- ——— 运行时状态 ———
local state = {}

function M.init()
    M.reset()
end

function M.reset()
    state = {
        -- 能量
        energy          = 0,
        energyCooldown  = 0,
        btActive        = false,

        -- 斩击
        slashCooldowns  = {},  -- { [enemyId] = remainingCooldown }
        btSlashCount    = 0,   -- BT内斩击累计（收尾攻击用）

        -- 充能
        chargeTimer     = 0,   -- 手动充能间隔计时
        autoChargeLeft  = 0,   -- 切换时自动充能剩余颗数

        -- 收尾攻击
        finisherPending = false, -- BT结束时触发
        finisherCount   = 0,     -- 收尾攻击用的斩击计数快照

        -- S-1连击
        comboTarget     = nil,
        comboCount      = 0,
        comboTimer      = 0,

        -- S-3灼痕路径
        burnPaths       = {},  -- { {x, y, time}, ... }
        burnPathActive  = false,
        burnPathTimer   = 0,
    }
    print("[ChenxiCtrl] 重置完毕")
end

-- ——— 读取接口 ———

function M.getState()
    return state
end

function M.getEnergy()
    return state.energy
end

function M.getEnergyMax()
    return CFG.energy.max
end

function M.isBTActive()
    return state.btActive
end

function M.getBTSlashCount()
    return state.btSlashCount
end

--- 获取当前能量段信息
---@return string segName, number mult, number cost
function M.getEnergySegment()
    local segs = CFG.enhancedSlash.segments
    local e = state.energy
    if e > segs.full.threshold then
        return "full", segs.full.mult, segs.full.cost
    elseif e > segs.normal.threshold then
        return "normal", segs.normal.mult, segs.normal.cost
    else
        return "decay", segs.decay.mult, segs.decay.cost
    end
end

--- 获取当前斩击范围（BT=强化范围, 非BT=基础范围）
---@return number
function M.getSlashRange()
    if state.btActive then
        return CFG.enhancedSlash.range
    else
        return CFG.slash.range
    end
end

--- 获取当前击退距离（BT=强化击退, 非BT=基础击退）
---@return number
function M.getKnockback()
    if state.btActive then
        return CFG.enhancedSlash.knockback
    else
        return CFG.slash.knockback
    end
end

--- 获取当前斩击形态的基础倍率
---@return number
function M.getSlashFormMult()
    local formId = SkillState.getFormId("cx_slash")
    local skills = ConfigLoader.load("config/characters/chenxi.json")
    if skills and skills.skills and skills.skills.cx_slash and skills.skills.cx_slash[formId] then
        return skills.skills.cx_slash[formId].baseMult or 1.0
    end
    return 1.0
end

--- 获取收尾攻击形态的配置数据
---@param formId string "verdict"|"thousand"|"flash"
---@return table|nil config
function M.getFinisherConfig(formId)
    local skills = ConfigLoader.load("config/characters/chenxi.json")
    if skills and skills.skills and skills.skills.cx_finisher and skills.skills.cx_finisher[formId] then
        return skills.skills.cx_finisher[formId]
    end
    return nil
end

--- 获取基础斩击伤害（供收尾攻击公式使用）
---@return number
function M.getBaseDamage()
    return CFG.slash.baseDamage
end

-- ——— 核心逻辑 ———

--- 主更新（每帧调用，仅晨曦激活时）
---@param dt number
---@param playerData table Player.getData() 引用
function M.update(dt, playerData)
    -- 斩击冷却衰减
    for eid, cd in pairs(state.slashCooldowns) do
        state.slashCooldowns[eid] = cd - dt
        if state.slashCooldowns[eid] <= 0 then
            state.slashCooldowns[eid] = nil
        end
    end

    -- 连击计时衰减（S-1）
    if state.comboCount > 0 then
        state.comboTimer = state.comboTimer - dt
        if state.comboTimer <= 0 then
            state.comboCount = 0
            state.comboTarget = nil
        end
    end

    -- 自动充能（切换时消耗轨道弹）
    if state.autoChargeLeft > 0 then
        state.chargeTimer = state.chargeTimer - dt
        if state.chargeTimer <= 0 then
            local consumed = M._consumeOrbitBullet()
            if consumed then
                state.energy = math.min(CFG.energy.max, state.energy + CFG.chargeConvert.energyPerBullet)
                state.autoChargeLeft = state.autoChargeLeft - 1
                state.chargeTimer = CFG.chargeConvert.manualInterval * (CFG.chargeConvert.autoChargeSpeedMult or 0.5)
            else
                state.autoChargeLeft = 0  -- 没弹了
            end
        end
    end

    -- 持续自动充能（有轨道弹时自动消耗转化，原手动充能改为自动）
    if state.autoChargeLeft <= 0 then
        state.chargeTimer = state.chargeTimer - dt
        if state.chargeTimer <= 0 then
            local consumed = M._consumeOrbitBullet()
            if consumed then
                state.energy = math.min(CFG.energy.max, state.energy + CFG.chargeConvert.energyPerBullet)
                state.chargeTimer = CFG.chargeConvert.manualInterval
            else
                state.chargeTimer = CFG.chargeConvert.chargeRetryInterval or 0.1
            end
        end
    end

    -- BT能量消耗
    if state.btActive then
        state.energy = state.energy - CFG.energy.btCostRate * dt
        if state.energy <= 0 then
            state.energy = 0
            M._endBT()
        end
    else
        -- 检测BT开启
        if Input.isBulletTimeHeld()
            and state.energy >= CFG.energy.minToStart
            and state.energyCooldown <= 0 then
            state.btActive = true
            state.btSlashCount = 0
            print("[ChenxiCtrl] BT开启, 能量:", string.format("%.2f", state.energy))
        end
        -- 冷却
        if state.energyCooldown > 0 then
            state.energyCooldown = state.energyCooldown - dt
        end
    end

    -- S-3灼痕路径记录（BT内记录移动点）
    if state.btActive and SkillState.getFormId("cx_slash") == "burnpath" then
        -- 每帧记录位置（由 main.lua 碰撞检测外部调用 recordBurnPoint）
        state.burnPathActive = true
    end

    -- S-3灼痕BT后倒计时
    if state.burnPathActive and not state.btActive then
        local level = SkillState.getLevel("cx_slash")
        local duration = CFG.enhancedSlash and 3.0 or 3.0  -- 从技能配置取
        -- 获取灼痕持续时间
        local skills = ConfigLoader.load("config/characters/chenxi.json")
        if skills and skills.skills then
            local form = skills.skills.cx_slash.burnpath
            if form then
                duration = form.pathDurationAfterBT or 3.0
                if level >= 2 and form.levelBonus and form.levelBonus["2"] then
                    duration = form.levelBonus["2"].pathDurationAfterBT or duration
                end
                if level >= 4 and form.levelBonus and form.levelBonus["4"] then
                    duration = form.levelBonus["4"].pathDurationAfterBT or duration
                end
            end
        end
        state.burnPathTimer = state.burnPathTimer + dt
        if state.burnPathTimer >= duration then
            state.burnPaths = {}
            state.burnPathActive = false
            state.burnPathTimer = 0
        end
    end
end

--- 尝试对敌人执行斩击（碰撞时由 main.lua 调用）
--- 非BT: 基础斩击（中等伤害、标准冷却、无消耗）
--- BT内: 强化斩击（高伤害=基础×能量段×形态、长冷却、消耗能量）
---@param enemy table 敌人数据
---@param playerData table 玩家数据
---@return number damage 实际伤害（0=冷却中）
function M.trySlash(enemy, playerData)
    local eid = enemy.id or tostring(enemy)
    -- 冷却检查
    if state.slashCooldowns[eid] then
        return 0
    end

    local baseDmg = CFG.slash.baseDamage
    local finalMult = 1.0

    if state.btActive then
        -- === 强化斩击（BT内）===
        -- 冷却更长，防止高倍率下秒杀
        local cd = CFG.slash.btCooldownPerEnemy or CFG.slash.cooldownPerEnemy
        state.slashCooldowns[eid] = cd

        local _, segMult, segCost = M.getEnergySegment()
        local formMult = M.getSlashFormMult()
        finalMult = segMult * formMult

        -- 扣能量
        state.energy = math.max(0, state.energy - segCost)

        -- 计数
        state.btSlashCount = math.min(state.btSlashCount + 1, CFG.finisher.maxSlashCount)

        -- S-1连击系统
        if SkillState.getFormId("cx_slash") == "endless" then
            M._updateCombo(enemy)
            finalMult = finalMult * M._getComboMult()
        end

        -- 能量耗尽检查
        if state.energy <= 0 then
            M._endBT()
        end
    else
        -- === 基础斩击（非BT）===
        -- 低伤害（配置 nonBtDamage），标准冷却，无消耗（保底过渡手段）
        state.slashCooldowns[eid] = CFG.slash.cooldownPerEnemy
        local damage = CFG.slash.nonBtDamage or 1
        print(string.format("[ChenxiCtrl] 基础斩击! dmg=%d BT=false", damage))
        return damage
    end

    local damage = baseDmg * finalMult
    print(string.format("[ChenxiCtrl] 斩击! dmg=%.1f (base=%d mult=%.2f) BT=%s count=%d energy=%.2f",
        damage, baseDmg, finalMult, tostring(state.btActive), state.btSlashCount, state.energy))
    return damage
end

--- 清除子弹回能（BT内碰到敌方子弹时由 main.lua 调用）
function M.onClearBullet()
    if state.btActive then
        state.energy = math.min(CFG.energy.max, state.energy + CFG.clearBullet.energyPerClear)
    end
end

--- 记录灼痕路径点（S-3形态，BT内由 main.lua 每帧调用）
---@param x number
---@param y number
function M.recordBurnPoint(x, y)
    if state.btActive and state.burnPathActive then
        local paths = state.burnPaths
        -- 只在移动超过一定距离时记录（避免静止时堆积）
        if #paths == 0 then
            paths[#paths + 1] = { x = x, y = y }
        else
            local last = paths[#paths]
            local dx = x - last.x
            local dy = y - last.y
            local minDist = CFG.burnPath and CFG.burnPath.minDist or 8
            if dx * dx + dy * dy > minDist * minDist then
                paths[#paths + 1] = { x = x, y = y }
            end
        end
    end
end

--- 切换到晨曦时调用（自动消耗轨道弹充能）
function M.onSwitchIn()
    state.autoChargeLeft = CFG.chargeConvert.autoOnSwitch
    state.chargeTimer = 0
    print("[ChenxiCtrl] 切入晨曦，自动充能:", state.autoChargeLeft, "颗")
end

--- 切出晨曦时调用
function M.onSwitchOut()
    -- 如果BT活跃，结束BT
    if state.btActive then
        M._endBT()
    end
    state.autoChargeLeft = 0
end

--- 直接设置能量（debug用）
function M.setEnergy(val)
    state.energy = math.max(0, math.min(CFG.energy.max, val))
end

--- 获取收尾攻击数据（BT结束时返回，供 VFX/伤害系统使用）
---@return table|nil finisherData
function M.popFinisher()
    if state.finisherPending then
        state.finisherPending = false
        return {
            slashCount = state.finisherCount,
            formId = SkillState.getFormId("cx_finisher"),
            formLevel = SkillState.getLevel("cx_finisher"),
        }
    end
    return nil
end

-- ——— 内部方法 ———

function M._endBT()
    state.btActive = false
    state.energyCooldown = CFG.energy.cooldown

    -- 触发收尾攻击
    state.finisherPending = true
    state.finisherCount = state.btSlashCount
    print(string.format("[ChenxiCtrl] BT结束! 斩击计数=%d, 收尾形态=%s Lv%d",
        state.finisherCount,
        SkillState.getFormId("cx_finisher"),
        SkillState.getLevel("cx_finisher")))

    -- 灼痕开始倒计时
    if state.burnPathActive then
        state.burnPathTimer = 0  -- 开始计时
    end

    state.btSlashCount = 0
end

--- 消耗一颗轨道子弹（返回是否成功）
---@return boolean
function M._consumeOrbitBullet()
    -- 由外部注入的回调实现（Player/BulletManager 提供）
    if M.consumeOrbitCallback then
        return M.consumeOrbitCallback()
    end
    return false
end

--- S-1连击更新
function M._updateCombo(enemy)
    local eid = enemy.id or tostring(enemy)
    local skills = ConfigLoader.load("config/characters/chenxi.json")
    local form = skills and skills.skills and skills.skills.cx_slash and skills.skills.cx_slash.endless
    local breakTime = form and form.comboBreakTime or 1.0
    local level = SkillState.getLevel("cx_slash")

    -- Lv2+: 延长窗口
    if level >= 2 and form and form.levelBonus and form.levelBonus["2"] then
        breakTime = form.levelBonus["2"].comboBreakTime or breakTime
    end

    if state.comboTarget == eid then
        -- 同一目标继续连击
        state.comboCount = state.comboCount + 1
        state.comboTimer = breakTime
    else
        -- Lv3: 切目标保留计数
        if level >= 3 then
            -- 短时间内切目标不重置
            state.comboTarget = eid
            state.comboTimer = breakTime
        else
            -- 重置
            state.comboTarget = eid
            state.comboCount = 1
            state.comboTimer = breakTime
        end
    end
end

--- S-1获取连击倍率
---@return number
function M._getComboMult()
    local skills = ConfigLoader.load("config/characters/chenxi.json")
    local form = skills and skills.skills and skills.skills.cx_slash and skills.skills.cx_slash.endless
    if not form then return 1.0 end

    local maxHits = form.comboMaxHits or 5
    local maxMult = form.comboMaxMult or 1.8
    local level = SkillState.getLevel("cx_slash")

    -- Lv2+: 上限提升
    if level >= 2 and form.levelBonus and form.levelBonus["2"] then
        maxMult = form.levelBonus["2"].comboMaxMult or maxMult
    end

    -- Lv3: 不重置
    local hits = math.min(state.comboCount, maxHits)
    local t = hits / maxHits  -- 0~1
    return 1.0 + (maxMult - 1.0) * t
end

return M
