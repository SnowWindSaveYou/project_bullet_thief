-- ============================================================================
-- OrbitModifier.lua - A线轨道形态修饰器
-- 根据 SkillState.orbit.form 修改轨道子弹行为
-- ============================================================================

local SkillState = require "game.SkillState"

local M = {}

-- ═══ 形态配置 ═══

local FORM_DEFAULT = { id = "default" }

-- O-1: 环刃吟霜（刀刃轨道）
local FORM_BLADE = {
    id = "blade",
    durability   = 3,       -- 碰撞 3 次后消耗
    dmgMult      = 1.3,     -- 碰撞伤害倍率
    -- 等级加成
    levelBonus = {
        [2] = { durability = 4 },
        [3] = { durability = 4, dmgMult = 1.8 },
        [4] = { durability = 4, dmgMult = 1.8, explodeOnBreak = true, explodeRadius = 40, explodeDmgMult = 1.5 },
        [5] = { durability = 4, dmgMult = 1.8, explodeOnBreak = true, explodeRadius = 40, explodeDmgMult = 1.5, slowOnHit = 0.7, slowDuration = 1.0 },
    },
}

-- O-2: 潮汐寐息（脉冲轨道）
local FORM_PULSE = {
    id = "pulse",
    pulsePeriod   = 3.0,     -- 脉冲周期
    pulseMinR     = 48,      -- 起始扩张半径
    pulseMaxR     = 120,     -- 最大扩张半径
    pulseExpandT  = 0.3,     -- 膨胀时间
    pulseRetractT = 0.2,     -- 收回时间
    pulseDmgBase  = 2,       -- 基础伤害
    pulseDmgPerBullet = 0.2, -- 每颗弹加成
    pulseCost     = 1,       -- 每次脉冲消耗弹数
    -- 等级加成
    levelBonus = {
        [2] = { pulsePeriod = 2.0 },
        [3] = { pulsePeriod = 2.0, pulseMaxR = 160 },
        [4] = { pulsePeriod = 2.0, pulseMaxR = 160, knockback = 40 },
        [5] = { pulsePeriod = 2.0, pulseMaxR = 160, knockback = 40, noCost = true },
    },
}

-- O-3: 繁星共语（共鸣轨道）
local FORM_RESONANCE = {
    id = "resonance",
    coeff = 0.08,           -- 每颗加成系数
    -- 等级加成
    levelBonus = {
        [2] = { coeff = 0.12 },
        [3] = { coeff = 0.12, pierceAt15 = true },
        [4] = { coeff = 0.12, pierceAt15 = true, fullBurstRadius = 80, fullBurstDmg = 0.5 },
        [5] = { coeff = 0.12, pierceAt15 = true, fullBurstRadius = 80, fullBurstDmg = 0.5, qteBonusMult = 0.20 },
    },
}

-- O-4: 薄翼守梦（护盾轨道）
local FORM_SHIELD = {
    id = "shield",
    shieldHP = 1,           -- 每颗护盾值
    -- 等级加成
    levelBonus = {
        [2] = { shieldHP = 2 },
        [3] = { shieldHP = 2, reflect = true, reflectDmgMult = 0.5 },
        [4] = { shieldHP = 2, reflect = true, reflectDmgMult = 0.5, regen = true, regenInterval = 5.0 },
        [5] = { shieldHP = 2, reflect = true, reflectDmgMult = 0.5, regen = true, regenInterval = 5.0, energyPerBlock = 0.03 },
    },
}

local FORMS = {
    [1] = FORM_DEFAULT,
    [2] = FORM_BLADE,
    [3] = FORM_PULSE,
    [4] = FORM_RESONANCE,
    [5] = FORM_SHIELD,
}

-- ═══ 脉冲状态 ═══
local pulseState_ = {
    timer    = 0,       -- 距下次脉冲的计时器
    pulsing  = false,   -- 正在膨胀中
    pulseT   = 0,       -- 当前脉冲动画进度 (0~1)
    radius   = 0,       -- 当前脉冲半径
    hitEnemies = {},    -- 本次脉冲已命中的敌人索引（防重复）
}

-- ═══ 护盾再生计时 ═══
local shieldRegenTimer_ = 0

function M.init()
    M.resetPulse()
end

function M.resetPulse()
    pulseState_.timer = 0
    pulseState_.pulsing = false
    pulseState_.pulseT = 0
    pulseState_.radius = 0
    pulseState_.hitEnemies = {}
    shieldRegenTimer_ = 0
end

-- ═══ 核心接口 ═══

--- 获取当前轨道形态配置（含等级加成）
function M.getFormConfig()
    local form = SkillState.getForm("orbit")
    local level = SkillState.getLevel("orbit")
    local base = FORMS[form] or FORM_DEFAULT
    if base.id == "default" then return base end

    local cfg = {}
    for k, v in pairs(base) do
        if k ~= "levelBonus" then cfg[k] = v end
    end

    if base.levelBonus and level >= 2 then
        local bonus = base.levelBonus[math.min(level, 5)]
        if bonus then
            for k, v in pairs(bonus) do cfg[k] = v end
        end
    end
    return cfg
end

--- 获取当前形态 ID
function M.getFormId()
    local cfg = M.getFormConfig()
    return cfg.id
end

--- 修饰新夺取的轨道子弹（加刀刃耐久/护盾值等）
---@param ob table 轨道子弹对象
function M.modifyOrbitBullet(ob)
    local cfg = M.getFormConfig()

    -- 清理旧形态残留
    ob.bladeDurability = nil
    ob.bladeDmgMult = nil
    ob.shieldHP = nil
    ob.shieldMax = nil

    if cfg.id == "blade" then
        ob.bladeDurability = cfg.durability or 3
        ob.bladeDmgMult = cfg.dmgMult or 1.3
    elseif cfg.id == "shield" then
        ob.shieldHP = cfg.shieldHP or 1
        ob.shieldMax = cfg.shieldHP or 1
    end
    -- resonance 和 pulse 不需要 per-bullet 属性
end

--- 获取轨道子弹碰撞敌人时的伤害倍率
---@param ob table 轨道子弹
---@param orbitCount number 当前轨道弹总数
---@return number dmgMult
function M.getOrbitDamageMult(ob, orbitCount)
    local cfg = M.getFormConfig()
    if cfg.id == "blade" then
        return ob.bladeDmgMult or cfg.dmgMult or 1.3
    elseif cfg.id == "resonance" then
        local coeff = cfg.coeff or 0.08
        return 1 + orbitCount * coeff
    end
    return 1.0
end

--- 轨道子弹碰撞敌人后是否应消耗
--- 返回 true = 消耗，false = 保留（刀刃耐久未耗尽）
---@param ob table 轨道子弹
---@return boolean shouldConsume
---@return boolean|nil explode 是否触发碎裂爆发
function M.onOrbitHitEnemy(ob)
    local cfg = M.getFormConfig()
    if cfg.id == "blade" then
        ob.bladeDurability = (ob.bladeDurability or 1) - 1
        if ob.bladeDurability <= 0 then
            -- 耐久归零，消耗
            local explode = cfg.explodeOnBreak or false
            return true, explode
        end
        return false, false  -- 不消耗
    end
    -- 默认/共鸣/脉冲/护盾碰敌人都消耗
    return true, false
end

--- 轨道子弹碰撞敌方子弹（护盾模式）
--- 返回: absorbed (是否吸收了敌弹), shouldReflect, reflectDmg
---@param ob table 轨道子弹
---@param enemyBulletDmg number 敌弹伤害
---@return boolean absorbed
---@return boolean shouldReflect
---@return number reflectDmg
function M.onOrbitHitEnemyBullet(ob, enemyBulletDmg)
    local cfg = M.getFormConfig()
    if cfg.id ~= "shield" then
        return false, false, 0
    end

    if (ob.shieldHP or 0) > 0 then
        ob.shieldHP = ob.shieldHP - 1
        local shouldReflect = cfg.reflect or false
        local reflectDmg = shouldReflect and math.max(1, math.floor(enemyBulletDmg * (cfg.reflectDmgMult or 0.5))) or 0
        return true, shouldReflect, reflectDmg
    end
    -- 护盾已空，不吸收
    return false, false, 0
end

--- 脉冲更新（每帧调用）
---@param dt number
---@param orbitCount number
---@param playerX number
---@param playerY number
---@return table|nil pulseHit { radius, dmg, x, y, knockback } 如果本帧触发了伤害脉冲
function M.updatePulse(dt, orbitCount, playerX, playerY)
    local cfg = M.getFormConfig()
    if cfg.id ~= "pulse" then return nil end
    if orbitCount == 0 then
        pulseState_.timer = 0
        return nil
    end

    local period = cfg.pulsePeriod or 3.0
    local expandT = cfg.pulseExpandT or 0.3
    local retractT = cfg.pulseRetractT or 0.2
    local totalAnim = expandT + retractT

    -- 脉冲中
    if pulseState_.pulsing then
        pulseState_.pulseT = pulseState_.pulseT + dt
        local maxR = cfg.pulseMaxR or 120
        local minR = cfg.pulseMinR or 48

        if pulseState_.pulseT < expandT then
            -- 膨胀阶段
            local t = pulseState_.pulseT / expandT
            pulseState_.radius = minR + (maxR - minR) * t
        elseif pulseState_.pulseT < totalAnim then
            -- 收回阶段
            local t = (pulseState_.pulseT - expandT) / retractT
            pulseState_.radius = maxR - (maxR - minR) * t
        else
            -- 结束
            pulseState_.pulsing = false
            pulseState_.radius = 0
            pulseState_.hitEnemies = {}
        end
        return nil  -- 伤害在膨胀峰值帧已返回
    end

    -- 计时
    pulseState_.timer = pulseState_.timer + dt
    if pulseState_.timer >= period then
        pulseState_.timer = pulseState_.timer - period
        pulseState_.pulsing = true
        pulseState_.pulseT = 0
        pulseState_.hitEnemies = {}

        -- 计算脉冲伤害
        local baseDmg = cfg.pulseDmgBase or 2
        local perBullet = cfg.pulseDmgPerBullet or 0.2
        local dmg = baseDmg + orbitCount * perBullet

        return {
            radius = cfg.pulseMaxR or 120,
            dmg = dmg,
            x = playerX,
            y = playerY,
            knockback = cfg.knockback or 0,
            cost = (cfg.noCost and 0) or (cfg.pulseCost or 1),
        }
    end
    return nil
end

--- 获取脉冲状态（用于绘制）
function M.getPulseState()
    return pulseState_
end

--- 护盾自动再生更新
---@param dt number
---@param orbitBullets table[] 所有轨道子弹
function M.updateShieldRegen(dt, orbitBullets)
    local cfg = M.getFormConfig()
    if cfg.id ~= "shield" or not cfg.regen then return end

    shieldRegenTimer_ = shieldRegenTimer_ + dt
    local interval = cfg.regenInterval or 5.0
    if shieldRegenTimer_ >= interval then
        shieldRegenTimer_ = shieldRegenTimer_ - interval
        -- 恢复一颗护盾值最低的子弹
        for _, ob in ipairs(orbitBullets) do
            if (ob.shieldHP or 0) < (ob.shieldMax or 1) then
                ob.shieldHP = (ob.shieldHP or 0) + 1
                break
            end
        end
    end
end

--- 共鸣轨道的 QTE 锁定倍率
---@param orbitCount number
---@return number mult
function M.getResonanceQTEMult(orbitCount)
    local cfg = M.getFormConfig()
    if cfg.id ~= "resonance" then return 1.0 end
    local coeff = cfg.coeff or 0.08
    local mult = 1 + orbitCount * coeff
    if cfg.qteBonusMult then
        mult = mult * (1 + cfg.qteBonusMult)
    end
    return mult
end

return M
