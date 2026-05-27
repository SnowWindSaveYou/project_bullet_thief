-- ============================================================================
-- Player.lua - 玩家数据 + 更新 + 绘制
-- ============================================================================

local Renderer = require "game.Renderer"
local Input    = require "game.InputHandler"
local Tween    = require "lib.Tween"

local M = {}

-- 地图边距（与 Renderer.drawMapBoundary 一致）
local MAP_MARGIN = 28

-- ——— 配置 ———
local CFG = {
    radius       = 18,
    grazeRadius  = 42,
    speed        = 280,          -- 逻辑像素/秒
    maxHp        = 100,
    energy       = {
        max         = 1.0,
        regenRate   = 0.06,       -- 每秒恢复
        btCostRate  = 0.18,       -- 子弹时间每秒消耗
        minToStart  = 0.25,       -- 最低开启阈值
        cooldown    = 1.5,        -- 退出后冷却
    },
    orbitRadius  = 48,            -- 轨道半径（第一圈）
    orbitRadiusStep = 22,         -- 每圈额外半径
    orbitPerLayer = 12,           -- 每层最多多少颗
    orbitAngularSpeed = 2.4,      -- 轨道旋转速度（rad/s）
    orbitDamage  = 1,
}

---@type table
local data = {}

local W_, H_ = 0, 0

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
        hp            = CFG.maxHp,
        maxHp         = CFG.maxHp,
        energy        = 0.5,
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
        orbitSpeedMult = 1.0,
        energyRegenMult = 1.0,
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

function M.update(dt)
    -- 1. 移动（发射时不再强制停步）
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

    -- 2. 边界限制
    local margin = MAP_MARGIN + data.radius
    data.x = math.max(margin, math.min(W_ - margin, data.x))
    data.y = math.max(margin, math.min(H_ - margin, data.y))

    -- 3. 能量系统
    local enCFG = CFG.energy
    if data.bulletTimeActive then
        data.energy = data.energy - enCFG.btCostRate * dt
        if data.energy <= 0 then
            data.energy = 0
            data.bulletTimeActive = false
            data.energyCooldown   = enCFG.cooldown
            print("[Player] 子弹时间: 能量耗尽，进入冷却")
        end
    else
        -- 自然恢复
        if data.energyCooldown > 0 then
            data.energyCooldown = data.energyCooldown - dt
        else
            data.energy = math.min(enCFG.max,
                data.energy + enCFG.regenRate * data.energyRegenMult * dt)
        end
        -- 检测开启子弹时间
        if Input.isBulletTimeHeld()
            and data.energy >= enCFG.minToStart
            and data.energyCooldown <= 0 then
            data.bulletTimeActive = true
            print("[Player] 子弹时间: 开启")
        end
        -- 解除（松开按键）
        if data.bulletTimeActive and not Input.isBulletTimeHeld() then
            data.bulletTimeActive = false
            print("[Player] 子弹时间: 手动关闭")
        end
    end

    -- 4. 轨道角度旋转
    data.orbitAngle = data.orbitAngle
        + CFG.orbitAngularSpeed * data.orbitSpeedMult * dt

    -- 5. 视觉动画衰减
    data.hitFlash = math.max(0, data.hitFlash - dt * 3.0)
    data.btPulse  = data.btPulse + dt * 3.0
    data.age      = data.age + dt

    -- 6. 伪3D朝向 & 偏转
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
    data.energy = math.min(CFG.energy.max, data.energy + amount)
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
local LOCK_RADIUS = 180  -- 自动锁定半径（逻辑像素）
local LOCK_STICKY_TIME = 0.15  -- 锁定粘滞时间（秒），防抖动切换
local lockTarget_ = nil  -- 当前锁定的敌人引用
local lockTimer_  = 0    -- 粘滞计时器

function M.getLockRadius()
    return LOCK_RADIUS
end

-- 获取当前发射方向（自动瞄准：近程锁敌，远程用移动方向）
-- 返回 angle(弧度), lockedEnemy(table|nil)
function M.getFireDirection()
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
    if lockTarget_ and not lockTarget_.dead then
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

-- ——— 绘制：Q版小人 ———

-- 绘制五角星路径（辅助函数）
local function starPath(vg, cx, cy, outerR, innerR)
    for i = 0, 4 do
        local aOuter = -math.pi / 2 + i * math.pi * 2 / 5
        local aInner = aOuter + math.pi / 5
        local ox = cx + math.cos(aOuter) * outerR
        local oy = cy + math.sin(aOuter) * outerR
        local ix = cx + math.cos(aInner) * innerR
        local iy = cy + math.sin(aInner) * innerR
        if i == 0 then
            nvgMoveTo(vg, ox, oy)
        else
            nvgLineTo(vg, ox, oy)
        end
        nvgLineTo(vg, ix, iy)
    end
    nvgClosePath(vg)
end

-- 绘制Q版主角小人（伪3D视差：nvgScale翻转 + fx逐层偏移）
function drawChibiPlayer(vg, cx, cy, r, flash, age, dir, face_yaw)
    local s = r / 18.0  -- 基于 radius=18 设计

    -- 伪3D视差基准
    local fx = face_yaw * 20  -- 范围 0~12

    -- 走路弹跳
    local bobY = math.abs(math.sin(age * 8.0)) * 2.0 * s

    -- 颜色（纯色）
    local hairFR, hairFG, hairFB = 0.17, 0.17, 0.37
    local hairBkR, hairBkG, hairBkB = 0.10, 0.10, 0.25
    local dressR, dressG, dressB = 0.72, 0.83, 0.94
    local dressDkR, dressDkG, dressDkB = 0.55, 0.68, 0.82
    local skinR, skinG, skinB = 0.96, 0.89, 0.85
    local starClr = {1.0, 0.82, 0.15}
    local eyeTopR, eyeTopG, eyeTopB = 0.20, 0.35, 0.72
    local eyeBotR, eyeBotG, eyeBotB = 0.40, 0.70, 0.92
    local slipperR, slipperG, slipperB = 0.96, 0.94, 0.97

    -- 受击闪白
    if flash > 0 then
        local f = flash
        hairFR  = hairFR + (1 - hairFR) * f
        hairFG  = hairFG + (1 - hairFG) * f
        hairFB  = hairFB + (1 - hairFB) * f
        hairBkR = hairBkR + (1 - hairBkR) * f
        hairBkG = hairBkG + (1 - hairBkG) * f
        hairBkB = hairBkB + (1 - hairBkB) * f
        dressR  = dressR + (1 - dressR) * f
        dressG  = dressG + (1 - dressG) * f
        dressB  = dressB + (1 - dressB) * f
    end

    nvgSave(vg)
    nvgTranslate(vg, cx, cy - bobY)
    nvgScale(vg, dir, 1)  -- Layer 1: 整体左右翻转

    -- 布局：头大身极小，身体紧贴头部下方
    local headCY = -7 * s     -- 头中心Y
    local headW  = 26 * s     -- 头宽
    local headH  = 24 * s     -- 头高
    local headRad = 3 * s     -- 圆角（小，接近矩形）
    local headBot = headCY + headH / 2  -- 头底边 = 5*s

    -- 身体紧贴头底（无间隙），三角形轮廓（上窄下宽）- 缩小版
    local bodyCY = headBot + 3.5 * s    -- 身体中心上移
    local bodyTopW = 2.0 * s            -- 肩膀更窄
    local bodyBotW = 6 * s              -- 裙摆收窄
    local bodyTopY = headBot - 1 * s    -- 身体顶端嵌入头底1*s
    local bodyBotY = bodyCY + 3.5 * s   -- 身体更短

    -- 脚固定在更下方（身体抬高但鞋子保留原位）
    local footY = bodyCY + 11 * s

    -- === 1. 阴影 ===
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, footY + 3 * s, 7 * s, 2.5 * s)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.22))
    nvgFill(vg)

    -- === 2. 后发（蓬松：上窄下宽，渐变深紫→浅紫）===
    local bhTop = headCY - headH / 2 + 1 * s
    local bhBot = headCY + headH / 2 + 3 * s
    local bhTopW = headW * 0.35
    local bhBotW = headW * 0.6
    local backHairFx = fx * -0.3  -- 后发反向偏移（减小）

    nvgBeginPath(vg)
    local bfx = backHairFx
    nvgMoveTo(vg, -bhTopW + bfx, bhTop)
    nvgLineTo(vg, bhTopW + bfx, bhTop)
    nvgBezierTo(vg, bhBotW + 2 * s + bfx, bhTop + (bhBot - bhTop) * 0.4,
        bhBotW + 1 * s + bfx, bhBot - 3 * s, bhBotW + bfx, bhBot)
    nvgBezierTo(vg, bhBotW - 3 * s + bfx, bhBot + 2 * s, -bhBotW + 3 * s + bfx, bhBot + 2 * s, -bhBotW + bfx, bhBot)
    nvgBezierTo(vg, -bhBotW - 1 * s + bfx, bhBot - 3 * s, -bhBotW - 2 * s + bfx, bhTop + (bhBot - bhTop) * 0.4,
        -bhTopW + bfx, bhTop)
    nvgClosePath(vg)
    -- 渐变：上深紫→下淡紫
    local hairGrad = nvgLinearGradient(vg, 0, bhTop, 0, bhBot,
        nvgRGBAf(0.10, 0.08, 0.25, 1.0),   -- 上：深紫
        nvgRGBAf(0.35, 0.25, 0.55, 1.0))   -- 下：淡紫
    nvgFillPaint(vg, hairGrad)
    nvgFill(vg)

    -- === 3. 身体（极小梯形 + 伪3D挤压）===
    local bodyShift = fx * 0.2
    nvgSave(vg)
    nvgTranslate(vg, bodyShift * 0.5, 0)
    local bodySx = 1.0 - math.abs(bodyShift) / 85
    if bodySx > 0.5 then nvgScale(vg, bodySx, 1.0) end

    nvgBeginPath(vg)
    nvgMoveTo(vg, -bodyTopW, bodyTopY)
    nvgLineTo(vg, bodyTopW, bodyTopY)
    nvgBezierTo(vg, bodyTopW + 1.5 * s, bodyCY, bodyBotW, bodyBotY - 2 * s, bodyBotW, bodyBotY)
    nvgBezierTo(vg, bodyBotW - 2 * s, bodyBotY + 2 * s, -bodyBotW + 2 * s, bodyBotY + 2 * s, -bodyBotW, bodyBotY)
    nvgBezierTo(vg, -bodyBotW, bodyBotY - 2 * s, -bodyTopW - 1.5 * s, bodyCY, -bodyTopW, bodyTopY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(dressR, dressG, dressB, 1.0))
    nvgFill(vg)

    -- 裙摆暗色带
    nvgBeginPath(vg)
    nvgMoveTo(vg, -bodyBotW + 1 * s, bodyBotY)
    nvgBezierTo(vg, -bodyBotW + 2 * s, bodyBotY + 1.5 * s, bodyBotW - 2 * s, bodyBotY + 1.5 * s, bodyBotW - 1 * s, bodyBotY)
    nvgStrokeColor(vg, nvgRGBAf(dressDkR, dressDkG, dressDkB, 1.0))
    nvgStrokeWidth(vg, 2 * s)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 领结
    local bowY = bodyTopY + 1.5 * s
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, bowY - 2 * s)
    nvgLineTo(vg, -2.5 * s, bowY)
    nvgLineTo(vg, 0, bowY + 2 * s)
    nvgLineTo(vg, 2.5 * s, bowY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(0.12, 0.12, 0.32, 1.0))
    nvgFill(vg)

    nvgRestore(vg)  -- 结束身体变换

    -- === 4. 手臂（长条，外扒 + 伪3D内收）===
    local armW = 2.2 * s
    local armH = 9 * s
    local shoulderY = bodyTopY + 1 * s
    local armBaseAngle = 0.45  -- 基础外扒角度（弧度）
    local armSwing = math.sin(age * 6.0) * 0.2  -- 摆动幅度
    local armNarrow = fx * 0.2  -- 伪3D：两臂向中线收拢

    -- 左臂（近侧，向右收 narrow）
    nvgSave(vg)
    nvgTranslate(vg, -bodyTopW - armW * 0.3 + armNarrow, shoulderY)
    nvgRotate(vg, armBaseAngle + armSwing)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -armW / 2, 0, armW, armH, armW / 2)
    nvgFillColor(vg, nvgRGBAf(skinR, skinG, skinB, 1.0))
    nvgFill(vg)
    nvgRestore(vg)

    -- 右臂（远侧，向左收 narrow）
    nvgSave(vg)
    nvgTranslate(vg, bodyTopW + armW * 0.3 - armNarrow, shoulderY)
    nvgRotate(vg, -armBaseAngle - armSwing)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -armW / 2, 0, armW, armH, armW / 2)
    nvgFillColor(vg, nvgRGBAf(skinR, skinG, skinB, 1.0))
    nvgFill(vg)
    nvgRestore(vg)

    -- === 5. 脚/拖鞋（保持在下方，伪3D内收）===
    local footSwing = math.sin(age * 8.0) * 1.2 * s
    local legNarrow = fx * 0.1  -- 伪3D：两脚向中线收拢
    for _, side in ipairs({-1, 1}) do
        local footNrw = (side < 0) and legNarrow or -legNarrow
        local ftx = side * 3.5 * s + footNrw
        local fy = footY + side * footSwing
        nvgBeginPath(vg)
        nvgEllipse(vg, ftx, fy, 4 * s, 2.5 * s)
        nvgFillColor(vg, nvgRGBAf(slipperR, slipperG, slipperB, 1.0))
        nvgFill(vg)
        -- 兔耳
        nvgBeginPath(vg)
        nvgEllipse(vg, ftx - 1.2 * s, fy - 3 * s, 1 * s, 2 * s)
        nvgFillColor(vg, nvgRGBAf(slipperR, slipperG, slipperB, 1.0))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgEllipse(vg, ftx + 1.2 * s, fy - 3 * s, 1 * s, 2 * s)
        nvgFillColor(vg, nvgRGBAf(slipperR, slipperG, slipperB, 1.0))
        nvgFill(vg)
        -- 兔耳内粉
        nvgBeginPath(vg)
        nvgEllipse(vg, ftx - 1.2 * s, fy - 2.8 * s, 0.5 * s, 1.0 * s)
        nvgFillColor(vg, nvgRGBAf(0.9, 0.7, 0.75, 0.8))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgEllipse(vg, ftx + 1.2 * s, fy - 2.8 * s, 0.5 * s, 1.0 * s)
        nvgFillColor(vg, nvgRGBAf(0.9, 0.7, 0.75, 0.8))
        nvgFill(vg)
    end

    -- === 6. 脸（圆角小，宽度紧凑让眼睛两侧留白少） ===
    local faceW = headW - 8 * s
    local faceH = headH - 5 * s
    local faceY = headCY + 3 * s
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -faceW / 2, faceY - faceH / 2, faceW, faceH, headRad)
    nvgFillColor(vg, nvgRGBAf(skinR, skinG, skinB, 1.0))
    nvgFill(vg)

    -- === 7. 前发（弧形主体 + 3片刘海，伪3D fx*0.35）===
    local frontHairFx = fx * 0.35
    local bangY = headCY + 3 * s
    local hairTop = headCY - headH / 2 - 1 * s
    local hairLeft = -headW / 2 - 1 * s + frontHairFx
    local hairRight = headW / 2 + 1 * s + frontHairFx

    -- 前发主体（覆盖上半脸）
    nvgBeginPath(vg)
    nvgMoveTo(vg, hairLeft, bangY)
    nvgLineTo(vg, hairRight, bangY)
    nvgBezierTo(vg, hairRight, hairTop + 4 * s, hairRight - 5 * s, hairTop, frontHairFx, hairTop)
    nvgBezierTo(vg, hairLeft + 5 * s, hairTop, hairLeft, hairTop + 4 * s, hairLeft, bangY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(hairFR, hairFG, hairFB, 1.0))
    nvgFill(vg)

    -- 刘海发片（3片平底，左右片外边缘连接弧线边缘）
    local bangCount = 3
    local bangInnerGap = 1.5 * s  -- 发片之间的内间隙
    local bangMidW = 3.5 * s      -- 中间发片半宽
    for i = 0, bangCount - 1 do
        local bLeft, bRight
        if i == 0 then
            -- 左发片：外边缘=hairLeft，内边缘=中间片左侧-gap
            bRight = -bangInnerGap - bangMidW
            bLeft = hairLeft
        elseif i == 1 then
            -- 中间发片
            bLeft = -bangMidW
            bRight = bangMidW
        else
            -- 右发片：外边缘=hairRight，内边缘=中间片右侧+gap
            bLeft = bangInnerGap + bangMidW
            bRight = hairRight
        end
        local bw = bRight - bLeft
        local bh = 4.5 * s + (i % 2) * 1.0 * s
        local bRad = math.min(bw * 0.2, 2 * s)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bLeft, bangY - 0.5 * s, bw, bh, bRad)
        nvgFillColor(vg, nvgRGBAf(hairFR, hairFG, hairFB, 1.0))
        nvgFill(vg)
    end

    -- === 8. 眼睛（贴近头底边，伪3D偏移 fx*0.4）===
    local eyeW = 3.0 * s
    local eyeH = 4.0 * s
    local eyeY = headCY + 8 * s   -- 更靠下，贴近头底
    local eyeSpacing = 5.5 * s    -- 两眼基础中心间距
    local eyeBaseOut = 0.75 * eyeW  -- 对称外扩
    local eyeFx = fx * 0.2         -- 伪3D：眼睛整体偏移（减小）
    local eyeLX = -eyeSpacing / 2 - eyeBaseOut + eyeFx
    local eyeRX = eyeSpacing / 2 + eyeBaseOut + eyeFx
    local eyeRound = 1.0 * s

    for _, ex in ipairs({eyeLX, eyeRX}) do
        local x0 = ex - eyeW / 2
        local y0 = eyeY - eyeH / 2
        local halfH = eyeH / 2

        -- 上半
        nvgBeginPath(vg)
        nvgMoveTo(vg, x0, y0 + halfH)
        nvgLineTo(vg, x0, y0 + eyeRound)
        nvgBezierTo(vg, x0, y0, x0, y0, x0 + eyeRound, y0)
        nvgLineTo(vg, x0 + eyeW - eyeRound, y0)
        nvgBezierTo(vg, x0 + eyeW, y0, x0 + eyeW, y0, x0 + eyeW, y0 + eyeRound)
        nvgLineTo(vg, x0 + eyeW, y0 + halfH)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(eyeTopR, eyeTopG, eyeTopB, 1.0))
        nvgFill(vg)

        -- 下半
        nvgBeginPath(vg)
        nvgMoveTo(vg, x0, y0 + halfH)
        nvgLineTo(vg, x0, y0 + eyeH - eyeRound)
        nvgBezierTo(vg, x0, y0 + eyeH, x0, y0 + eyeH, x0 + eyeRound, y0 + eyeH)
        nvgLineTo(vg, x0 + eyeW - eyeRound, y0 + eyeH)
        nvgBezierTo(vg, x0 + eyeW, y0 + eyeH, x0 + eyeW, y0 + eyeH, x0 + eyeW, y0 + eyeH - eyeRound)
        nvgLineTo(vg, x0 + eyeW, y0 + halfH)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(eyeBotR, eyeBotG, eyeBotB, 1.0))
        nvgFill(vg)

        -- 高光
        nvgBeginPath(vg)
        nvgEllipse(vg, ex + 0.6 * s, eyeY - 0.8 * s, 0.7 * s, 0.9 * s)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, 0.85))
        nvgFill(vg)
    end

    -- === 8.5 腮红 ===
    local blushY = eyeY + 2.5 * s
    local blushRx = 2.8 * s
    local blushRy = 1.5 * s
    local blushAlpha = 0.35
    -- 左腮红
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeLX - 0.5 * s, blushY, blushRx, blushRy)
    nvgFillColor(vg, nvgRGBAf(0.95, 0.55, 0.55, blushAlpha))
    nvgFill(vg)
    -- 右腮红
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeRX + 0.5 * s, blushY, blushRx, blushRy)
    nvgFillColor(vg, nvgRGBAf(0.95, 0.55, 0.55, blushAlpha))
    nvgFill(vg)

    -- === 9. 星星发夹（固定视觉右侧，不随整体镜像翻转）===
    local starFx = fx * 0.45
    local starCX = (headW / 2 - 3 * s) + starFx   -- 基础位置（右侧）
    local starCY2 = headCY - 1 * s
    local starOuter = 5.5 * s
    local starInner = 2.5 * s
    local starRot = math.sin(age * 2.5) * 0.1
    nvgSave(vg)
    -- starCX * dir：抵消外层 nvgScale(dir,1) 对位置的翻转
    -- 当 dir=-1 时，外层会把 localX 映射为 -screenX，乘 dir 后 -starCX 经外层翻转变回 +starCX
    nvgTranslate(vg, starCX * dir, starCY2)
    nvgScale(vg, dir, 1)  -- 抵消外层对形状/旋转的翻转
    nvgRotate(vg, starRot)
    nvgBeginPath(vg)
    starPath(vg, 0, 0, starOuter, starInner)
    nvgFillColor(vg, nvgRGBAf(starClr[1], starClr[2], starClr[3], 1.0))
    nvgFill(vg)
    nvgRestore(vg)

    nvgRestore(vg)
end

function M.draw(vg)
    local p = data

    -- 子弹时间光晕
    if p.bulletTimeActive then
        local pulse = math.abs(math.sin(p.btPulse))
        local glowR = p.radius + 10 + pulse * 8
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, glowR)
        nvgFillColor(vg, nvgRGBAf(0.3, 0.9, 1.0, 0.15 + pulse * 0.1))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, glowR)
        nvgStrokeColor(vg, nvgRGBAf(0.3, 0.9, 1.0, 0.5 + pulse * 0.3))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 绘制Q版小人
    drawChibiPlayer(vg, p.x, p.y, p.radius, p.hitFlash, p.age, p.dir, p.face_yaw)

    -- 能量环（外圈弧线）
    drawEnergyRing(vg, p.x, p.y, p.radius + 8, p.energy,
        p.bulletTimeActive, p.energyCooldown)

    -- 自动锁定范围（白色虚线圆环）
    drawLockRangeCircle(vg, p.x, p.y, LOCK_RADIUS)
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

-- 绘制能量环
function drawEnergyRing(vg, cx, cy, r, energy, btActive, cooldown)
    local arc = energy * math.pi * 2

    -- 背景环（暗灰）
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, r, -math.pi * 0.5, math.pi * 1.5, NVG_CW)
    nvgStrokeColor(vg, nvgRGBAf(0.2, 0.2, 0.3, 0.5))
    nvgStrokeWidth(vg, 3.5)
    nvgStroke(vg)

    if arc < 0.05 then return end

    -- 能量弧
    local er, eg, eb, ea
    if cooldown > 0 then
        -- 冷却中：灰色闪烁
        local flicker = 0.4 + math.abs(math.sin(cooldown * 8)) * 0.3
        er, eg, eb, ea = 0.35, 0.35, 0.4, flicker
    elseif btActive then
        -- 子弹时间：亮青色
        er, eg, eb, ea = 0.3, 1.0, 0.9, 1.0
    elseif energy < 0.25 then
        -- 低能量：暗橙
        er, eg, eb, ea = 0.8, 0.4, 0.1, 0.8
    else
        -- 正常：青色
        er, eg, eb, ea = 0.3, 0.85, 0.95, 0.9
    end

    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, r, -math.pi * 0.5, -math.pi * 0.5 + arc, NVG_CW)
    nvgStrokeColor(vg, nvgRGBAf(er, eg, eb, ea))
    nvgStrokeWidth(vg, 3.5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
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
