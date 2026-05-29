-- ============================================================================
-- ShotHandler.lua - A线射击形态处理器
-- 根据 SkillState.shot.form 提供不同射击参数和子弹属性
-- ============================================================================

local SkillState = require "game.SkillState"

local M = {}

-- ═══ 各形态基础数值（来自设计文档） ═══

-- 默认形态使用 BulletManager 的 FIRE_CFG（不覆盖）
local FORM_DEFAULT = {
    id = "default",
}

-- S-1: 流星坠夜（穿透速射）
local FORM_PIERCE = {
    id = "pierce",
    interval = 0.08,        -- 射击间隔
    speed    = 1050,        -- 弹速 px/s
    perShot  = 1,
    spread   = 0,
    -- 子弹属性
    pierce      = 2,        -- 穿透数（可升级）
    pierceDecay = 0.20,     -- 穿透伤害衰减 20%/个
    bulletRadius = 6,
    bulletLife   = 2.5,
    -- 等级加成
    levelBonus = {
        -- level 2: +1穿透
        [2] = { pierce = 3 },
        -- level 3: 穿透不衰减
        [3] = { pierce = 3, pierceDecay = 0 },
        -- level 4: 尾焰AOE + 弹速x3
        [4] = { pierce = 4, pierceDecay = 0, speed = 1260 },
        -- level 5: 全部加成
        [5] = { pierce = 5, pierceDecay = 0, speed = 1260, endAoe = true },
    },
}

-- S-2: 凝霜长吟（聚能激光）— 特殊机制，不改变 doFire
local FORM_LASER = {
    id = "laser",
    -- 激光参数
    chargeRate   = 3,       -- 蓄力速度（颗/s）
    minCharge    = 3,       -- 最少消耗
    maxCharge    = 10,      -- 最多消耗
    durationMin  = 0.5,     -- 最短持续（3颗）
    durationMax  = 1.5,     -- 最长持续（10颗）
    widthMin     = 8,       -- 最窄宽度（3颗）
    widthMax     = 32,      -- 最宽宽度（10颗）
    dpsPerBullet = 2,       -- 每消耗颗 = 2 DPS
    -- 等级加成
    levelBonus = {
        [2] = { widthMax = 40 },
        [3] = { widthMax = 48, chargeRate = 5 },
        [4] = { widthMax = 48, chargeRate = 5, reflect = true },
        [5] = { widthMax = 48, chargeRate = 5, reflect = true, overcharge = true },
    },
}

-- S-3: 碎梦飞花（溅射弹幕）
local FORM_SPLASH = {
    id = "splash",
    -- 使用默认射速档位（不覆盖 interval/perShot）
    splashCount   = 4,      -- 溅射弹片数
    splashDmgMult = 0.4,    -- 弹片伤害 = 主弹 × 0.4
    splashRadius  = 50,     -- 溅射半径
    splashRange   = 80,     -- 弹片飞行距离
    -- 等级加成
    levelBonus = {
        [2] = { splashCount = 6 },
        [3] = { splashCount = 6, splashRadius = 75 },
        [4] = { splashCount = 6, splashRadius = 75, chain = 0.3 },
        [5] = { splashCount = 8, splashRadius = 75, chain = 0.3, slow = true },
    },
}

-- S-4: 霰雪惊鸿（散弹）
local FORM_SHOTGUN = {
    id = "shotgun",
    interval = 0.22,        -- 射击间隔
    speed    = 420,         -- 弹速（正常）
    perShot  = 5,           -- 分裂弹丸数
    spread   = math.rad(18),-- ±18°
    -- 子弹属性
    pierce      = 1,        -- 每颗穿透 1 个
    bulletLife   = 0.43,     -- 180px / 420px/s ≈ 0.43s 射程
    dmgMult     = 0.35,     -- 弹丸伤害 = 主弹 × 0.35
    bulletRadius = 5,
    -- 等级加成
    levelBonus = {
        [2] = { perShot = 7 },
        [3] = { perShot = 7, bulletLife = 0.62 },  -- 260px range
        [4] = { perShot = 7, bulletLife = 0.62, pierce = 2 },
        [5] = { perShot = 7, bulletLife = 0.62, pierce = 2, closeDmg = 1.5 },
    },
}

local FORMS = {
    [1] = FORM_DEFAULT,
    [2] = FORM_PIERCE,
    [3] = FORM_LASER,
    [4] = FORM_SPLASH,
    [5] = FORM_SHOTGUN,
}

-- ═══ 激光状态 ═══
local laserState_ = {
    charging  = false,
    charged   = 0,       -- 已蓄力颗数
    firing    = false,
    fireTimer = 0,
    fireDir   = 0,       -- 激光方向角
    width     = 0,
    dps       = 0,
    duration  = 0,
}

function M.init()
    M.resetLaser()
end

function M.resetLaser()
    laserState_.charging = false
    laserState_.charged = 0
    laserState_.firing = false
    laserState_.fireTimer = 0
end

-- ═══ 核心接口 ═══

--- 获取当前形态配置（含等级加成）
---@return table formCfg
function M.getFormConfig()
    local form = SkillState.getForm("shot")
    local level = SkillState.getLevel("shot")
    local base = FORMS[form] or FORM_DEFAULT
    if base.id == "default" then return base end

    -- 合并等级加成
    local cfg = {}
    for k, v in pairs(base) do
        if k ~= "levelBonus" then
            cfg[k] = v
        end
    end

    if base.levelBonus and level >= 2 then
        local bonus = base.levelBonus[math.min(level, 5)]
        if bonus then
            for k, v in pairs(bonus) do
                cfg[k] = v
            end
        end
    end

    return cfg
end

--- 获取发射参数覆盖（供 BulletManager.doFire 使用）
--- 返回 nil 表示使用默认参数
---@return table|nil overrides { interval, speed, perShot, spread }
function M.getFireOverrides()
    local cfg = M.getFormConfig()
    if cfg.id == "default" then return nil end
    if cfg.id == "laser" then return nil end  -- 激光有独立机制

    local overrides = {}
    if cfg.interval then overrides.interval = cfg.interval end
    if cfg.speed then overrides.speed = cfg.speed end
    if cfg.perShot then overrides.perShot = cfg.perShot end
    if cfg.spread then overrides.spread = cfg.spread end
    return overrides
end

--- 修饰新生成的玩家子弹（添加穿透/溅射/散弹属性）
---@param bullet table 刚生成的子弹对象
function M.modifyBullet(bullet)
    local cfg = M.getFormConfig()
    if cfg.id == "default" then return end

    if cfg.id == "pierce" then
        bullet.pierce = cfg.pierce or 2
        bullet.pierceDecay = cfg.pierceDecay or 0.2
        bullet.radius = cfg.bulletRadius or 6
        if cfg.bulletLife then bullet.life = cfg.bulletLife end
        if cfg.endAoe then bullet.endAoe = true end

    elseif cfg.id == "splash" then
        bullet.splash = true
        bullet.splashCount = cfg.splashCount or 4
        bullet.splashDmgMult = cfg.splashDmgMult or 0.4
        bullet.splashRadius = cfg.splashRadius or 50
        bullet.splashRange = cfg.splashRange or 80
        if cfg.chain then bullet.splashChain = cfg.chain end
        if cfg.slow then bullet.splashSlow = true end

    elseif cfg.id == "shotgun" then
        bullet.pierce = cfg.pierce or 1
        bullet.radius = cfg.bulletRadius or 5
        bullet.dmgMult = cfg.dmgMult or 0.35
        if cfg.bulletLife then bullet.life = cfg.bulletLife end
        if cfg.closeDmg then bullet.closeDmg = cfg.closeDmg end
    end
end

--- 是否使用激光模式（激光需要特殊处理）
---@return boolean
function M.isLaserMode()
    local form = SkillState.getForm("shot")
    return form == 3
end

--- 获取激光状态（供绘制用）
function M.getLaserState()
    return laserState_
end

--- 激光蓄力开始（按住射击键时）
function M.laserChargeStart()
    if not M.isLaserMode() then return end
    laserState_.charging = true
end

--- 激光蓄力更新（每帧，按住射击键时调用）
---@param dt number
---@param orbitCount number 当前轨道子弹数
function M.laserChargeUpdate(dt, orbitCount)
    if not laserState_.charging then return end
    local cfg = M.getFormConfig()
    local rate = cfg.chargeRate or 3
    local maxC = math.min(cfg.maxCharge or 10, orbitCount)

    laserState_.charged = math.min(laserState_.charged + rate * dt, maxC)
end

--- 激光释放（松开射击键 / 满充）
---@param dir number 激光方向角
---@return integer consumed 消耗的轨道弹数量
function M.laserRelease(dir)
    if not laserState_.charging then return 0 end
    local cfg = M.getFormConfig()
    local minC = cfg.minCharge or 3
    local charged = math.floor(laserState_.charged)

    if charged < minC then
        -- 蓄力不足，取消
        laserState_.charging = false
        laserState_.charged = 0
        return 0
    end

    -- 开始激光发射
    local t = (charged - minC) / ((cfg.maxCharge or 10) - minC)
    t = math.max(0, math.min(1, t))

    laserState_.charging = false
    laserState_.firing = true
    laserState_.fireDir = dir
    laserState_.duration = cfg.durationMin + t * (cfg.durationMax - cfg.durationMin)
    laserState_.fireTimer = laserState_.duration
    laserState_.width = cfg.widthMin + t * (cfg.widthMax - cfg.widthMin)
    laserState_.dps = charged * (cfg.dpsPerBullet or 2)
    laserState_.charged = 0

    return charged
end

--- 激光发射更新
---@param dt number
---@return boolean active 是否仍在发射
function M.laserFireUpdate(dt)
    if not laserState_.firing then return false end
    laserState_.fireTimer = laserState_.fireTimer - dt
    if laserState_.fireTimer <= 0 then
        laserState_.firing = false
        return false
    end
    return true
end

return M
