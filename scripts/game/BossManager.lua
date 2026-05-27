-- ============================================================================
-- BossManager.lua - Boss 系统（梦魔王 Dream Sovereign）
-- 多攻击模式 + 血条UI + 召唤小怪
-- ============================================================================

local Renderer  = require "game.Renderer"
local BulletMgr = require "game.BulletManager"
local Player    = require "game.Player"
local VFX       = require "lib.VFX"

local M = {}

local W_, H_ = 0, 0

-- Boss 状态
---@type table|nil
local boss_ = nil
local bossActive_ = false

-- Boss 配置
local BOSS_CONFIG = {
    radius       = 44,
    hp           = 100,
    speed        = 35,
    -- Phase 1 攻击
    bulletHellInterval = 1.8,   -- 弹海发射间隔
    bulletHellCount    = 8,     -- 每波弹数
    bulletHellSpeed    = 170,
    laserInterval      = 8.0,   -- 激光间隔
    laserChargeTime    = 1.2,
    laserFireTime      = 1.0,
    laserWidth         = 12,
    laserRange         = 550,
    -- Phase 2 攻击
    burstInterval   = 3.0,    -- 可夺取弹爆发间隔
    burstCount      = 16,     -- 爆发弹数
    burstSpeed      = 130,
    -- 召唤
    summonInterval  = 10.0,   -- 召唤间隔
    summonCount     = 3,      -- 每次召唤小怪数
    -- 动画
    phaseTransTime  = 2.0,    -- 阶段转换时间
}

-- Boss 出现触发条件
local BOSS_KILL_THRESHOLD = 500

function M.init(_W, _H)
    W_ = _W
    H_ = _H
    M.reset()
end

function M.reset()
    boss_ = nil
    bossActive_ = false
end

function M.isActive()
    return bossActive_
end

function M.getBoss()
    return boss_
end

--- 检查是否该触发 Boss
function M.checkSpawn(killCount)
    if bossActive_ or boss_ then return false end
    if killCount >= BOSS_KILL_THRESHOLD then
        M.spawnBoss()
        return true
    end
    return false
end

--- 生成 Boss
function M.spawnBoss()
    boss_ = {
        x            = W_ * 0.5,
        y            = -80,  -- 从屏幕外进入
        radius       = BOSS_CONFIG.radius,
        hp           = BOSS_CONFIG.hp,
        maxHp        = BOSS_CONFIG.hp,
        speed        = BOSS_CONFIG.speed,
        dead         = false,
        age          = 0,
        hitFlash     = 0,
        -- 阶段
        phase        = 1,           -- 1 或 2
        phaseTransTimer = 0,        -- 阶段转换动画计时
        inTransition = false,
        -- 入场动画
        entering     = true,
        enterTimer   = 0,
        -- Phase 1 攻击计时
        bulletTimer  = 1.5,
        laserState   = "idle",      -- idle / charging / firing / cooldown
        laserTimer   = 0,
        laserAngle   = 0,
        laserCooldown = BOSS_CONFIG.laserInterval * 0.5,
        -- Phase 2 攻击计时
        burstTimer   = 2.0,
        -- 通用
        summonTimer  = BOSS_CONFIG.summonInterval * 0.6,
        -- 动画用
        eyeGlow      = 0,
        crownAngle   = 0,
        flamePhase   = 0,
    }
    bossActive_ = true
    VFX.triggerShake(10, 0.5)
    VFX.spawnBanner("BOSS!", 255, 50, 50)
    print("[Boss] 梦魔王出现！")
end

--- 更新 Boss
function M.update(dt)
    if not boss_ or boss_.dead then return end

    local e = boss_
    local player = Player.getData()
    e.age = e.age + dt
    e.crownAngle = e.crownAngle + dt * 0.8
    e.flamePhase = e.flamePhase + dt * 3.0

    -- hitFlash 衰减
    if e.hitFlash > 0 then
        e.hitFlash = math.max(0, e.hitFlash - dt * 3.0)
    end

    -- 入场动画
    if e.entering then
        e.enterTimer = e.enterTimer + dt
        local targetY = H_ * 0.25
        e.y = e.y + (targetY - e.y) * dt * 1.5
        if e.enterTimer > 2.0 then
            e.entering = false
            e.y = targetY
        end
        return
    end

    -- 阶段转换
    if e.inTransition then
        e.phaseTransTimer = e.phaseTransTimer + dt
        if e.phaseTransTimer >= BOSS_CONFIG.phaseTransTime then
            e.inTransition = false
            e.phase = 2
            VFX.spawnBanner("PHASE 2!", 180, 0, 255)
            VFX.triggerShake(8, 0.4)
        end
        return  -- 转换期间不攻击
    end

    -- 检查阶段切换
    if e.phase == 1 and e.hp <= e.maxHp * 0.5 then
        e.inTransition = true
        e.phaseTransTimer = 0
        VFX.triggerShake(12, 0.6)
        return
    end

    -- 缓慢移动（围绕场地上方区域巡逻）
    local targetX = W_ * 0.5 + math.sin(e.age * 0.3) * W_ * 0.25
    local targetY = H_ * 0.22 + math.cos(e.age * 0.2) * H_ * 0.05
    local dx = targetX - e.x
    local dy = targetY - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 2 then
        local spd = e.speed * dt
        e.x = e.x + (dx / dist) * spd
        e.y = e.y + (dy / dist) * spd
    end

    -- 攻击逻辑
    if e.phase == 1 then
        updatePhase1(e, player, dt)
    else
        updatePhase2(e, player, dt)
    end

    -- 召唤小怪（两个阶段都有，但间隔不同）
    local summonInterval = e.phase == 1 and BOSS_CONFIG.summonInterval or (BOSS_CONFIG.summonInterval * 0.7)
    e.summonTimer = e.summonTimer - dt
    if e.summonTimer <= 0 then
        e.summonTimer = summonInterval
        M.summonMinions()
    end
end

-- Phase 1: 弹海 + 偶发激光
function updatePhase1(e, player, dt)
    -- 弹海
    e.bulletTimer = e.bulletTimer - dt
    if e.bulletTimer <= 0 then
        e.bulletTimer = BOSS_CONFIG.bulletHellInterval * (0.8 + math.random() * 0.4)
        fireBulletHell(e, player)
    end

    -- 激光
    if e.laserState == "idle" then
        e.laserCooldown = e.laserCooldown - dt
        if e.laserCooldown <= 0 then
            e.laserState = "charging"
            e.laserTimer = 0
            local dx = player.x - e.x
            local dy = player.y - e.y
            e.laserAngle = math.atan(dy, dx)
        end
    elseif e.laserState == "charging" then
        e.laserTimer = e.laserTimer + dt
        -- 追踪玩家方向
        local dx = player.x - e.x
        local dy = player.y - e.y
        local targetAngle = math.atan(dy, dx)
        local angleDiff = targetAngle - e.laserAngle
        while angleDiff > math.pi do angleDiff = angleDiff - math.pi * 2 end
        while angleDiff < -math.pi do angleDiff = angleDiff + math.pi * 2 end
        local track = 1.2 * (1.0 - e.laserTimer / BOSS_CONFIG.laserChargeTime)
        e.laserAngle = e.laserAngle + angleDiff * track * dt
        if e.laserTimer >= BOSS_CONFIG.laserChargeTime then
            e.laserState = "firing"
            e.laserTimer = 0
            e.laserDmgTick = 0
        end
    elseif e.laserState == "firing" then
        e.laserTimer = e.laserTimer + dt
        e.laserDmgTick = (e.laserDmgTick or 0) + dt
        if e.laserTimer >= BOSS_CONFIG.laserFireTime then
            e.laserState = "cooldown"
            e.laserTimer = 0
        end
    elseif e.laserState == "cooldown" then
        e.laserTimer = e.laserTimer + dt
        if e.laserTimer >= 1.5 then
            e.laserState = "idle"
            e.laserCooldown = BOSS_CONFIG.laserInterval * (0.7 + math.random() * 0.3)
        end
    end
end

-- Phase 2: 可夺取弹爆发
function updatePhase2(e, player, dt)
    e.burstTimer = e.burstTimer - dt
    if e.burstTimer <= 0 then
        e.burstTimer = BOSS_CONFIG.burstInterval * (0.8 + math.random() * 0.4)
        fireSteelableBurst(e, player)
    end

    -- Phase 2 也有基础弹幕但频率低
    e.bulletTimer = e.bulletTimer - dt
    if e.bulletTimer <= 0 then
        e.bulletTimer = BOSS_CONFIG.bulletHellInterval * 2.0
        fireBulletHell(e, player)
    end
end

-- 弹海攻击：放射状扇形弹
function fireBulletHell(e, player)
    local dx = player.x - e.x
    local dy = player.y - e.y
    local baseAngle = math.atan(dy, dx)
    local count = BOSS_CONFIG.bulletHellCount
    local spreadTotal = math.pi * 0.8  -- 大扇形

    for i = 1, count do
        local t = (i - 1) / (count - 1) - 0.5
        local angle = baseAngle + t * spreadTotal
        local spd = BOSS_CONFIG.bulletHellSpeed * (0.9 + math.random() * 0.2)
        BulletMgr.spawnEnemyBullet(e.x, e.y,
            math.cos(angle) * spd,
            math.sin(angle) * spd,
            {
                damage    = 1,
                radius    = 6,
                stealable = false,  -- Phase 1 弹不可夺取
                btype     = "boss",
            }
        )
    end
end

-- Phase 2 可夺取爆发弹（全方向）
function fireSteelableBurst(e, player)
    local count = BOSS_CONFIG.burstCount
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.2
        local spd = BOSS_CONFIG.burstSpeed * (0.8 + math.random() * 0.4)
        BulletMgr.spawnEnemyBullet(e.x, e.y,
            math.cos(angle) * spd,
            math.sin(angle) * spd,
            {
                damage    = 1,
                radius    = 8,
                stealable = true,  -- 可夺取！
                btype     = "boss",
            }
        )
    end
    VFX.spawnPopup("STEAL ME!", e.x, e.y + 30, 80, 255, 200)
end

-- 召唤小怪（通知 EnemyManager 生成）
function M.summonMinions()
    -- 返回 true 表示需要生成小怪，由 main.lua 转调 EnemyMgr
    M._pendingSummon = BOSS_CONFIG.summonCount
    VFX.spawnPopup("SUMMON!", boss_.x, boss_.y - 40, 200, 100, 255)
end

--- 获取待召唤小怪数（被 main.lua 消费后清零）
function M.getPendingSummon()
    local count = M._pendingSummon or 0
    M._pendingSummon = 0
    return count
end

--- 对 Boss 造成伤害
function M.damageBoss(dmg)
    if not boss_ or boss_.dead then return end
    boss_.hp = boss_.hp - dmg
    boss_.hitFlash = 0.5
    if boss_.hp <= 0 then
        boss_.hp = 0
        boss_.dead = true
        bossActive_ = false
        VFX.spawnBanner("BOSS DEFEATED!", 255, 210, 50)
        VFX.triggerShake(20, 0.8)
        -- 掉落大量道具
        local ItemMgr = require "game.ItemManager"
        local bossCfg = { etype = "boss" }
        for _ = 1, 8 do
            ItemMgr.tryDrop(
                boss_.x + (math.random() - 0.5) * 80,
                boss_.y + (math.random() - 0.5) * 80,
                bossCfg
            )
        end
        print("[Boss] 梦魔王被击败！")
    end
end

--- 获取 Boss 激光数据（供碰撞检测）
function M.getActiveLasers()
    local lasers = {}
    if not boss_ or boss_.dead then return lasers end
    if boss_.laserState == "firing" then
        local angle = boss_.laserAngle
        local range = BOSS_CONFIG.laserRange
        local cosA = math.cos(angle)
        local sinA = math.sin(angle)
        lasers[1] = {
            x1       = boss_.x,
            y1       = boss_.y,
            x2       = boss_.x + cosA * range,
            y2       = boss_.y + sinA * range,
            width    = BOSS_CONFIG.laserWidth,
            damage   = 2,  -- Boss 激光伤害更高
            dmgTick  = boss_.laserDmgTick or 0,
            isBoss   = true,
        }
    end
    return lasers
end

--- 重置 Boss 激光伤害 tick
function M.resetBossLaserDmgTick()
    if boss_ then boss_.laserDmgTick = 0 end
end

-- ============================================================================
-- 绘制
-- ============================================================================

function M.draw(vg)
    if not boss_ or boss_.dead then return end
    drawBoss(vg, boss_)
end

function M.drawLasers(vg)
    if not boss_ or boss_.dead then return end
    if boss_.laserState ~= "firing" and boss_.laserState ~= "charging" then return end
    drawBossLaser(vg, boss_)
end

function M.drawHPBar(vg)
    if not boss_ or boss_.dead then return end
    drawBossHPBar(vg, boss_)
end

-- ——— Boss 视觉（巨型黑色轮廓 + 扭曲星冠 + 红色双眼 + 紫焰边缘）———
function drawBoss(vg, e)
    local cx, cy, r = e.x, e.y, e.radius
    local flash = e.hitFlash or 0

    -- 斜投影阴影
    local ox, oy = Renderer.shadowOffset(0)
    nvgBeginPath(vg)
    nvgCircle(vg, cx + ox, cy + oy, r * 1.1)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.4))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)

    -- === 紫焰边缘 ===
    for fi = 1, 12 do
        local fAngle = (fi / 12) * math.pi * 2 + e.flamePhase * 0.7
        local fDist = r * (0.9 + 0.3 * math.sin(e.flamePhase * 2 + fi * 1.7))
        local fSize = r * (0.15 + 0.1 * math.sin(e.age * 4 + fi))
        local fx = math.cos(fAngle) * fDist
        local fy = math.sin(fAngle) * fDist
        nvgBeginPath(vg)
        nvgCircle(vg, fx, fy, fSize)
        local fAlpha = 0.4 + 0.2 * math.sin(e.age * 3 + fi * 2)
        nvgFillColor(vg, nvgRGBAf(0.53, 0.0, 1.0, fAlpha))
        nvgFill(vg)
    end

    -- === 主体（深黑色圆形）===
    local bodyR, bodyG, bodyB = 0.04, 0.04, 0.08
    if flash > 0 then
        bodyR, bodyG, bodyB = 0.5, 0.3, 0.5
    end
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r * 0.85)
    nvgFillColor(vg, nvgRGBAf(bodyR, bodyG, bodyB, 1.0))
    nvgFill(vg)

    -- === 扭曲星冠 ===
    local crownR = r * 0.6
    nvgBeginPath(vg)
    for ci = 1, 5 do
        local cAngle = (ci / 5) * math.pi * 2 + e.crownAngle
        local tipR = crownR + r * 0.25
        local baseR = crownR * 0.7
        -- 星冠尖端
        local tx = math.cos(cAngle) * tipR
        local ty = math.sin(cAngle) * tipR - r * 0.15
        -- 星冠基座
        local bAngle = cAngle + math.pi / 5
        local bx = math.cos(bAngle) * baseR
        local by = math.sin(bAngle) * baseR - r * 0.15
        if ci == 1 then
            nvgMoveTo(vg, tx, ty)
        else
            nvgLineTo(vg, tx, ty)
        end
        nvgLineTo(vg, bx, by)
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.84, 0.0, 0.9))  -- 金色
    nvgFill(vg)

    -- === 红色双眼 ===
    local eyeSpacing = r * 0.25
    local eyeY = r * 0.05
    local eyeR = r * 0.12
    e.eyeGlow = 0.7 + 0.3 * math.sin(e.age * 4)

    for side = -1, 1, 2 do
        local ex = side * eyeSpacing
        -- 外发光
        nvgBeginPath(vg)
        nvgCircle(vg, ex, eyeY, eyeR * 1.6)
        nvgFillColor(vg, nvgRGBAf(1.0, 0.0, 0.0, 0.3 * e.eyeGlow))
        nvgFill(vg)
        -- 眼球
        nvgBeginPath(vg)
        nvgCircle(vg, ex, eyeY, eyeR)
        nvgFillColor(vg, nvgRGBAf(1.0, 0.0, 0.0, e.eyeGlow))
        nvgFill(vg)
        -- 瞳孔
        nvgBeginPath(vg)
        nvgCircle(vg, ex, eyeY, eyeR * 0.4)
        nvgFillColor(vg, nvgRGBAf(0.2, 0.0, 0.0, 1.0))
        nvgFill(vg)
    end

    -- === Phase 指示 ===
    if e.phase == 2 then
        -- Phase 2 全身紫色脉冲光环
        local pulseR = r * (1.0 + 0.15 * math.sin(e.age * 5))
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, pulseR)
        nvgStrokeColor(vg, nvgRGBAf(0.53, 0.0, 1.0, 0.4 + 0.2 * math.sin(e.age * 5)))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
    end

    -- === 阶段转换动画 ===
    if e.inTransition then
        local t = e.phaseTransTimer / BOSS_CONFIG.phaseTransTime
        -- 扩展冲击波
        local waveR = r * (1.0 + t * 2.0)
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, waveR)
        nvgStrokeColor(vg, nvgRGBAf(0.53, 0.0, 1.0, (1.0 - t) * 0.8))
        nvgStrokeWidth(vg, 3.0 * (1.0 - t))
        nvgStroke(vg)
    end

    -- === 蓄力指示器（激光预警）===
    if e.laserState == "charging" then
        local chargeT = e.laserTimer / BOSS_CONFIG.laserChargeTime
        local dirX = math.cos(e.laserAngle)
        local dirY = math.sin(e.laserAngle)
        -- 预警线（虚线闪烁）
        local lineLen = BOSS_CONFIG.laserRange * chargeT
        local startX = dirX * r
        local startY = dirY * r
        nvgBeginPath(vg)
        nvgMoveTo(vg, startX, startY)
        nvgLineTo(vg, startX + dirX * lineLen, startY + dirY * lineLen)
        nvgStrokeColor(vg, nvgRGBAf(1.0, 0.2, 0.0, 0.4 + 0.3 * math.sin(e.age * 20)))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    end

    nvgRestore(vg)
end

-- Boss 激光绘制
function drawBossLaser(vg, e)
    if e.laserState ~= "firing" then return end

    local angle = e.laserAngle
    local range = BOSS_CONFIG.laserRange
    local width = BOSS_CONFIG.laserWidth
    local flicker = 0.85 + 0.15 * math.sin(e.age * 25)
    local fireT = e.laserTimer / BOSS_CONFIG.laserFireTime
    local fadeAlpha = fireT > 0.75 and (1.0 - (fireT - 0.75) / 0.25) or 1.0

    local dirX = math.cos(angle)
    local dirY = math.sin(angle)
    local startX = e.x + dirX * e.radius
    local startY = e.y + dirY * e.radius
    local endX = e.x + dirX * range
    local endY = e.y + dirY * range

    -- 外层光晕
    nvgBeginPath(vg)
    nvgMoveTo(vg, startX, startY)
    nvgLineTo(vg, endX, endY)
    nvgStrokeColor(vg, nvgRGBAf(0.53, 0.0, 1.0, 0.3 * fadeAlpha * flicker))
    nvgStrokeWidth(vg, width * 4.0)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 中层
    nvgBeginPath(vg)
    nvgMoveTo(vg, startX, startY)
    nvgLineTo(vg, endX, endY)
    nvgStrokeColor(vg, nvgRGBAf(0.8, 0.1, 0.2, 0.75 * fadeAlpha * flicker))
    nvgStrokeWidth(vg, width * 2.0)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 内核
    nvgBeginPath(vg)
    nvgMoveTo(vg, startX, startY)
    nvgLineTo(vg, endX, endY)
    nvgStrokeColor(vg, nvgRGBAf(1.0, 0.8, 0.6, 0.95 * fadeAlpha * flicker))
    nvgStrokeWidth(vg, width * 0.6)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
end

-- Boss 血条 UI（顶部全宽）
function drawBossHPBar(vg, e)
    local barW = W_ * 0.6
    local barH = 12
    local barX = (W_ - barW) * 0.5
    local barY = 18

    -- 底框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 2, barY - 2, barW + 4, barH + 4, 4)
    nvgFillColor(vg, nvgRGBAf(0.0, 0.0, 0.0, 0.7))
    nvgFill(vg)

    -- 血条背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 3)
    nvgFillColor(vg, nvgRGBAf(0.15, 0.0, 0.05, 1.0))
    nvgFill(vg)

    -- 血量
    local hpRatio = e.hp / e.maxHp
    local hpW = barW * hpRatio
    -- 颜色随血量变化
    local hpR, hpG, hpB
    if hpRatio > 0.5 then
        hpR, hpG, hpB = 0.8, 0.1, 0.2  -- 红色
    else
        hpR, hpG, hpB = 0.53, 0.0, 1.0  -- 紫色（Phase 2）
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, hpW, barH, 3)
    nvgFillColor(vg, nvgRGBAf(hpR, hpG, hpB, 1.0))
    nvgFill(vg)

    -- 高光
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, hpW, barH * 0.4, 3)
    nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, 0.15))
    nvgFill(vg)

    -- Boss 名称
    nvgFontFace(vg, "bold")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(1.0, 0.84, 0.0, 0.9))
    local label = string.format("梦魔王  %.0f / %.0f", e.hp, e.maxHp)
    nvgText(vg, W_ * 0.5, barY + barH + 4, label)
end

return M
