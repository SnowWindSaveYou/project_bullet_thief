-- ============================================================================
-- QTEHandler.lua - A线 QTE 形态修饰器
-- 根据 SkillState.qte.form 修改 QTE 全弹爆发行为
-- 形态: default / beam / radial / homing
-- ============================================================================

local SkillState = require "game.SkillState"
local ConfigLoader = require "config.ConfigLoader"

local M = {}

-- ═══ 形态配置（从 JSON 加载） ═══

local FORMS = nil  -- 延迟初始化

--- 将 JSON 的 string key levelBonus 转为 Lua numeric key
local function convertLevelBonus(tbl)
    if not tbl then return nil end
    local out = {}
    for k, v in pairs(tbl) do
        out[tonumber(k)] = v
    end
    return out
end

--- 从 protagonist.json 加载 QTE 形态配置
local function loadForms()
    if FORMS then return FORMS end

    local data = ConfigLoader.load("config/characters/protagonist.json")
    if data and data.skills and data.skills.qte then
        local order = { "default", "beam", "radial", "homing" }
        FORMS = {}
        for i, key in ipairs(order) do
            local raw = data.skills.qte[key]
            if raw then
                local form = {}
                for k, v in pairs(raw) do
                    if k == "levelBonus" then
                        form[k] = convertLevelBonus(v)
                    else
                        form[k] = v
                    end
                end
                FORMS[i] = form
            end
        end
        print("[QTEHandler] 从 JSON 加载 " .. #FORMS .. " 个形态配置")
    end

    -- 兜底默认值
    if not FORMS or #FORMS == 0 then
        print("[QTEHandler] WARN: JSON 加载失败，使用内置默认值")
        FORMS = {
            [1] = { id = "default", window = 0.9, burstDelay = 0.03, speedMult = 1.8, baseDmgMult = 1.5, countBonus = 0.12 },
            [2] = { id = "beam", window = 0.9, speedMult = 2.5, baseDmgMult = 2.0, countBonus = 0.25, beamWidth = 12, beamLength = 600, pierce = true },
            [3] = { id = "radial", window = 0.9, burstDelay = 0, speedMult = 1.6, baseDmgMult = 1.2, countBonus = 0.08, extraBullets = 0 },
            [4] = { id = "homing", window = 1.1, burstDelay = 0.05, speedMult = 1.4, baseDmgMult = 1.8, countBonus = 0.15, turnRate = 6.0, accel = 200, lifetime = 3.0 },
        }
    end
    return FORMS
end

-- ═══ 内部状态 ═══

-- 光束特效状态（绘制用）
local beamState_ = {
    active   = false,
    timer    = 0,
    duration = 0.4,    -- 光束持续显示时间
    x1 = 0, y1 = 0,   -- 起点
    x2 = 0, y2 = 0,   -- 终点
    width = 12,
    alpha = 1.0,
}

-- 追踪弹列表（独立管理生命周期）
---@type table[]
local homingBullets_ = {}

function M.init()
    M.resetBeam()
    homingBullets_ = {}
end

function M.resetBeam()
    beamState_.active = false
    beamState_.timer = 0
    beamState_.alpha = 0
end

-- ═══ 核心接口 ═══

--- 获取当前 QTE 形态配置（含等级加成）
---@return table config
function M.getFormConfig()
    local forms = loadForms()
    local form = SkillState.getForm("qte")
    local level = SkillState.getLevel("qte")
    local base = forms[form] or forms[1]
    if base.id == "default" and level <= 1 then return base end

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
---@return string
function M.getFormId()
    return M.getFormConfig().id
end

--- 获取 QTE 窗口时长
---@return number
function M.getWindow()
    return M.getFormConfig().window or 0.9
end

--- 获取爆发时每颗子弹间隔
---@return number
function M.getBurstDelay()
    return M.getFormConfig().burstDelay or 0.03
end

--- 获取爆发速度倍率
---@return number
function M.getSpeedMult()
    return M.getFormConfig().speedMult or 1.8
end

--- 计算爆发伤害倍率
---@param orbitCount number 轨道弹数量
---@return number dmgMult
function M.calcDmgMult(orbitCount)
    local cfg = M.getFormConfig()
    local base = cfg.baseDmgMult or 1.5
    local bonus = cfg.countBonus or 0.12
    -- 共鸣轨道叠加 QTE 倍率
    local OrbitMod = require "game.skills.OrbitModifier"
    local resonanceMult = OrbitMod.getResonanceQTEMult(orbitCount)
    return (base + orbitCount * bonus) * resonanceMult
end

--- 是否自动触发（不需要玩家按键）
---@return boolean
function M.isAutoTrigger()
    local cfg = M.getFormConfig()
    return cfg.autoTrigger == true
end

-- ═══ 光束形态接口 ═══

--- 判断当前是否是光束模式
---@return boolean
function M.isBeamMode()
    return M.getFormId() == "beam"
end

--- 触发光束爆发（替代普通连射）
--- 返回: 总伤害值, 命中敌人索引列表, 光束参数
---@param playerX number
---@param playerY number
---@param fireAngle number
---@param orbitCount number
---@param baseDamage number 轨道弹平均伤害
---@return table beamResult { totalDmg, hitIndices, x1, y1, x2, y2, width, stun }
function M.fireBeam(playerX, playerY, fireAngle, orbitCount, baseDamage)
    local cfg = M.getFormConfig()
    local dmgMult = M.calcDmgMult(orbitCount)
    local totalDmg = math.floor(baseDamage * orbitCount * dmgMult)

    local length = cfg.beamLength or 600
    local width = cfg.beamWidth or 12
    local x2 = playerX + math.cos(fireAngle) * length
    local y2 = playerY + math.sin(fireAngle) * length

    -- 设置光束显示状态
    beamState_.active = true
    beamState_.timer = 0
    beamState_.duration = 0.4
    beamState_.x1 = playerX
    beamState_.y1 = playerY
    beamState_.x2 = x2
    beamState_.y2 = y2
    beamState_.width = width
    beamState_.alpha = 1.0

    return {
        totalDmg = totalDmg,
        x1 = playerX, y1 = playerY,
        x2 = x2, y2 = y2,
        width = width,
        length = length,
        angle = fireAngle,
        pierce = cfg.pierce or false,
        stun = cfg.stunDuration or 0,
        chain = cfg.chain or false,
    }
end

--- 获取光束状态（绘制用）
---@return table beamState
function M.getBeamState()
    return beamState_
end

-- ═══ 星坠形态接口 ═══

--- 判断当前是否是星坠模式
---@return boolean
function M.isRadialMode()
    return M.getFormId() == "radial"
end

--- 生成星坠爆发角度列表（360° 均匀分布）
--- 返回: 每颗子弹的发射角度列表（含额外子弹）
---@param orbitCount number
---@return number[] angles
---@return table opts { explodeOnHit, explodeRadius, secondWave }
function M.calcRadialAngles(orbitCount)
    local cfg = M.getFormConfig()
    local extra = cfg.extraBullets or 0
    local total = orbitCount + extra
    local angles = {}
    for i = 1, total do
        local angle = (i - 1) / total * math.pi * 2
        angles[i] = angle
    end
    return angles, {
        explodeOnHit = cfg.explodeOnHit or false,
        explodeRadius = cfg.explodeRadius or 30,
        secondWave = cfg.secondWave or false,
    }
end

-- ═══ 群星追踪形态接口 ═══

--- 判断当前是否是追踪模式
---@return boolean
function M.isHomingMode()
    return M.getFormId() == "homing"
end

--- 生成追踪弹（在 BulletManager 爆发逻辑中调用）
---@param x number 发射位置 x
---@param y number 发射位置 y
---@param angle number 初始角度
---@param damage number 伤害值
---@param targetEnemy table|nil 优先目标 {x,y}
function M.spawnHomingBullet(x, y, angle, damage, targetEnemy)
    local cfg = M.getFormConfig()
    local speed = 280 * (cfg.speedMult or 1.4)
    local hb = {
        x = x, y = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        speed = speed,
        angle = angle,
        damage = damage,
        radius = 10,
        turnRate = cfg.turnRate or 6.0,
        accel = cfg.accel or 200,
        lifetime = cfg.lifetime or 3.0,
        age = 0,
        dead = false,
        target = targetEnemy,  -- 可为 nil（会自动寻找最近敌人）
        splitOnKill = cfg.splitOnKill or false,
    }
    table.insert(homingBullets_, hb)
end

--- 更新所有追踪弹（每帧调用）
---@param dt number
---@param enemies table[] 活跃敌人列表
---@param bossData table|nil Boss 数据
---@return table[] hitResults { {x, y, damage, enemyIdx|"boss"} }
function M.updateHomingBullets(dt, enemies, bossData)
    local hits = {}

    for i = #homingBullets_, 1, -1 do
        local hb = homingBullets_[i]
        if hb.dead then
            table.remove(homingBullets_, i)
        else
            hb.age = hb.age + dt
            if hb.age >= hb.lifetime then
                hb.dead = true
            else
                -- 寻找目标
                local tx, ty = nil, nil
                local targetIdx = nil
                local targetType = nil

                -- 优先追踪指定目标
                if hb.target and not hb.target.dead then
                    tx, ty = hb.target.x, hb.target.y
                else
                    -- 找最近的活跃敌人
                    local bestDist = math.huge
                    for ei, e in ipairs(enemies) do
                        if not e.dead then
                            local dx = e.x - hb.x
                            local dy = e.y - hb.y
                            local d = dx * dx + dy * dy
                            if d < bestDist then
                                bestDist = d
                                tx, ty = e.x, e.y
                                targetIdx = ei
                                targetType = "enemy"
                            end
                        end
                    end
                    -- 也考虑 Boss
                    if bossData and not bossData.dead then
                        local dx = bossData.x - hb.x
                        local dy = bossData.y - hb.y
                        local d = dx * dx + dy * dy
                        if d < bestDist then
                            tx, ty = bossData.x, bossData.y
                            targetIdx = nil
                            targetType = "boss"
                        end
                    end
                end

                -- 追踪转向
                if tx and ty then
                    local desired = math.atan(ty - hb.y, tx - hb.x)
                    local diff = desired - hb.angle
                    -- 归一化到 [-pi, pi]
                    while diff > math.pi do diff = diff - 2 * math.pi end
                    while diff < -math.pi do diff = diff + 2 * math.pi end
                    local maxTurn = hb.turnRate * dt
                    if math.abs(diff) < maxTurn then
                        hb.angle = desired
                    else
                        hb.angle = hb.angle + maxTurn * (diff > 0 and 1 or -1)
                    end
                end

                -- 加速
                hb.speed = hb.speed + hb.accel * dt
                hb.vx = math.cos(hb.angle) * hb.speed
                hb.vy = math.sin(hb.angle) * hb.speed

                -- 移动
                hb.x = hb.x + hb.vx * dt
                hb.y = hb.y + hb.vy * dt

                -- 碰撞检测 - 敌人
                for ei, e in ipairs(enemies) do
                    if not e.dead then
                        local dx = hb.x - e.x
                        local dy = hb.y - e.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist < (hb.radius + (e.radius or 16)) then
                            table.insert(hits, { x = hb.x, y = hb.y, damage = hb.damage, targetIdx = ei, targetType = "enemy" })
                            hb.dead = true
                            break
                        end
                    end
                end

                -- 碰撞检测 - Boss
                if not hb.dead and bossData and not bossData.dead then
                    local dx = hb.x - bossData.x
                    local dy = hb.y - bossData.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < (hb.radius + (bossData.radius or 32)) then
                        table.insert(hits, { x = hb.x, y = hb.y, damage = hb.damage, targetIdx = nil, targetType = "boss" })
                        hb.dead = true
                    end
                end

                -- 出屏判定
                if hb.x < -50 or hb.x > 1200 or hb.y < -50 or hb.y > 900 then
                    hb.dead = true
                end
            end
        end
    end

    -- 清理死亡弹
    for i = #homingBullets_, 1, -1 do
        if homingBullets_[i].dead then
            table.remove(homingBullets_, i)
        end
    end

    return hits
end

--- 获取追踪弹列表（绘制用）
---@return table[]
function M.getHomingBullets()
    return homingBullets_
end

--- 清空追踪弹
function M.clearHomingBullets()
    homingBullets_ = {}
end

-- ═══ 更新（光束衰减 + 追踪弹由外部调用） ═══

--- 每帧更新光束显示衰减
---@param dt number
function M.updateBeamVisual(dt)
    if beamState_.active then
        beamState_.timer = beamState_.timer + dt
        beamState_.alpha = math.max(0, 1.0 - beamState_.timer / beamState_.duration)
        if beamState_.timer >= beamState_.duration then
            beamState_.active = false
        end
    end
end

-- ═══ 绘制接口 ═══

--- 绘制光束特效
---@param vg any NanoVG context
function M.drawBeam(vg)
    if not beamState_.active or beamState_.alpha <= 0 then return end

    local s = beamState_
    local alpha = s.alpha

    -- 核心光束（白色）
    nvgBeginPath(vg)
    nvgMoveTo(vg, s.x1, s.y1)
    nvgLineTo(vg, s.x2, s.y2)
    nvgStrokeColor(vg, nvgRGBAf(1.0, 1.0, 1.0, alpha * 0.9))
    nvgStrokeWidth(vg, s.width * 0.4)
    nvgStroke(vg)

    -- 外层光晕（青蓝色）
    nvgBeginPath(vg)
    nvgMoveTo(vg, s.x1, s.y1)
    nvgLineTo(vg, s.x2, s.y2)
    nvgStrokeColor(vg, nvgRGBAf(0.3, 0.7, 1.0, alpha * 0.5))
    nvgStrokeWidth(vg, s.width)
    nvgStroke(vg)

    -- 最外层扩散光晕
    nvgBeginPath(vg)
    nvgMoveTo(vg, s.x1, s.y1)
    nvgLineTo(vg, s.x2, s.y2)
    nvgStrokeColor(vg, nvgRGBAf(0.2, 0.5, 1.0, alpha * 0.2))
    nvgStrokeWidth(vg, s.width * 2.0)
    nvgStroke(vg)
end

--- 绘制追踪弹
---@param vg any NanoVG context
function M.drawHomingBullets(vg)
    for _, hb in ipairs(homingBullets_) do
        if not hb.dead then
            -- 拖尾
            local tailLen = 14
            local tx = hb.x - math.cos(hb.angle) * tailLen
            local ty = hb.y - math.sin(hb.angle) * tailLen
            nvgBeginPath(vg)
            nvgMoveTo(vg, tx, ty)
            nvgLineTo(vg, hb.x, hb.y)
            nvgStrokeColor(vg, nvgRGBAf(0.4, 0.9, 1.0, 0.5))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)

            -- 弹头
            nvgBeginPath(vg)
            nvgCircle(vg, hb.x, hb.y, hb.radius * 0.6)
            nvgFillColor(vg, nvgRGBAf(0.6, 0.95, 1.0, 0.9))
            nvgFill(vg)
        end
    end
end

return M
