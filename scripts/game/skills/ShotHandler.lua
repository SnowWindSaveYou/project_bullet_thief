-- ============================================================================
-- ShotHandler.lua - A线射击形态处理器
-- 根据 SkillState.shot.form 提供不同射击参数和子弹属性
-- ============================================================================

local SkillState   = require "game.SkillState"
local ConfigLoader = require "config.ConfigLoader"

local M = {}

-- ═══ 从 JSON 加载形态配置 ═══

local function loadForms()
    local data = ConfigLoader.load("config/characters/protagonist.json")
    if not data or not data.skills or not data.skills.shot then
        print("[ShotHandler] WARN: 无法加载射击配置，使用空配置")
        return { [1] = { id = "default" } }
    end

    local shotCfg = data.skills.shot
    local forms = { [1] = { id = "default" } }

    -- 转换 JSON levelBonus 的字符串 key 为数字 key
    local function convertLevelBonus(raw)
        if not raw or not raw.levelBonus then return raw end
        local lb = {}
        for k, v in pairs(raw.levelBonus) do
            lb[tonumber(k)] = v
        end
        raw.levelBonus = lb
        return raw
    end

    -- 加载各形态，保持顺序与 SkillState 一致
    local order = { "pierce", "laser", "splash", "shotgun" }
    for i, name in ipairs(order) do
        local cfg = shotCfg[name]
        if cfg then
            cfg = convertLevelBonus(cfg)
            -- 散弹的 spreadDeg 转为弧度
            if cfg.spreadDeg then
                cfg.spread = math.rad(cfg.spreadDeg)
                cfg.spreadDeg = nil
            end
            forms[i + 1] = cfg
        end
    end

    return forms
end

local FORMS = loadForms()

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
    local base = FORMS[form] or FORMS[1]
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
