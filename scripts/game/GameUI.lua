-- ============================================================================
-- GameUI.lua - 所有 HUD / 菜单 / 游戏结束界面
-- 复古卡通桌游风格（米黄+暗绿+深蓝描边）
-- ============================================================================

local Tween   = require "lib.Tween"
local Theme   = require "ui.Theme"
local Comp    = require "ui.Components"
local Upgrade = require "game.UpgradeSystem"

local M = {}

---@type userdata
local vg_ = nil
local W_, H_ = 0, 0

-- 按钮图标句柄
local iconAttack_ = -1
local iconDodge_  = -1

-- ——— 菜单动画 ———
local menuVisible_    = true
local menuAnim_ = {
    panelScale = 0, panelAlpha = 0,
    titleScale = 0, titleAlpha = 0,
    subtitleAlpha = 0,
    orbitAlpha = 0,
    tapAlpha = 0,
}

-- ——— 游戏结束 ———
local gameoverVisible_ = false
local finalKills_      = 0
local goAnim_ = {
    maskAlpha = 0,
    panelScale = 0, panelAlpha = 0,
    titleScale = 0, titleAlpha = 0,
    killsAlpha = 0, killsY = 0,
    tapAlpha = 0,
}

-- ——— HUD 弹跳 ———
local hudAnim_ = {
    hpScale = 1.0,
    killScale = 1.0,
    orbitScale = 1.0,
}
local lastHp_ = -1
local lastKills_ = -1
local lastOrbit_ = -1

-- ——— 按钮脉冲 ———
local btnPulse_ = 0

-- ——— 暂停系统 ———
local paused_ = false
local pauseAnim_ = {
    maskAlpha  = 0,
    panelScale = 0,
    panelAlpha = 0,
    titleAlpha = 0,
    btnAlpha   = 0,
}
local pauseBtnRect_ = { x = 0, y = 0, w = 0, h = 0 }  -- 暂停按钮点击区域
local resumeBtnRect_ = { x = 0, y = 0, w = 0, h = 0 }
local menuBtnRect_ = { x = 0, y = 0, w = 0, h = 0 }

function M.init(_vg, _W, _H)
    vg_ = _vg
    W_  = _W
    H_  = _H
    Upgrade.setSize(_W, _H)

    -- 加载按钮图标（透明底 PNG）
    iconAttack_ = nvgCreateImage(_vg, "image/edited_icon_attack_final_20260526172119.png", NVG_IMAGE_GENERATE_MIPMAPS)
    iconDodge_  = nvgCreateImage(_vg, "image/edited_icon_dodge_final_20260526172142.png", NVG_IMAGE_GENERATE_MIPMAPS)
    print(string.format("[GameUI] 图标加载: attack=%d, dodge=%d", iconAttack_, iconDodge_))

    print("[GameUI] 初始化 " .. _W .. "x" .. _H)
    -- 触发菜单入场动画
    M.showMenu()
end

function M.update(dt)
    btnPulse_ = btnPulse_ + dt * 2.0
    Upgrade.update(dt)
end

function M.hideMenu()
    menuVisible_ = false
end

function M.showMenu()
    menuVisible_       = true
    gameoverVisible_   = false

    -- 重置并启动菜单入场动画
    Tween.cancelTarget(menuAnim_)
    menuAnim_.panelScale = 0
    menuAnim_.panelAlpha = 0
    menuAnim_.titleScale = 0
    menuAnim_.titleAlpha = 0
    menuAnim_.subtitleAlpha = 0
    menuAnim_.orbitAlpha = 0
    menuAnim_.tapAlpha = 0

    -- 面板 easeOutBack 弹入
    Tween.to(menuAnim_, { panelScale = 1, panelAlpha = 1 }, 0.45, {
        easing = Tween.Easing.easeOutBack, delay = 0.05
    })
    -- 标题 easeOutBack
    Tween.to(menuAnim_, { titleScale = 1, titleAlpha = 1 }, 0.4, {
        easing = Tween.Easing.easeOutBack, delay = 0.15
    })
    -- 副标题渐入
    Tween.to(menuAnim_, { subtitleAlpha = 1 }, 0.35, {
        easing = Tween.Easing.easeOutCubic, delay = 0.3
    })
    -- 装饰轨道渐入
    Tween.to(menuAnim_, { orbitAlpha = 1 }, 0.4, {
        easing = Tween.Easing.easeOutCubic, delay = 0.35
    })
    -- TAP TO START 渐入
    Tween.to(menuAnim_, { tapAlpha = 1 }, 0.35, {
        easing = Tween.Easing.easeOutCubic, delay = 0.5
    })
end

function M.showGameOver(kills)
    gameoverVisible_ = true
    finalKills_      = kills

    -- 重置并启动 GameOver 级联动画
    Tween.cancelTarget(goAnim_)
    goAnim_.maskAlpha = 0
    goAnim_.panelScale = 0
    goAnim_.panelAlpha = 0
    goAnim_.titleScale = 0
    goAnim_.titleAlpha = 0
    goAnim_.killsAlpha = 0
    goAnim_.killsY = 15
    goAnim_.tapAlpha = 0

    -- 遮罩渐入
    Tween.to(goAnim_, { maskAlpha = 1 }, 0.4, {
        easing = Tween.Easing.easeOutCubic, delay = 0.0
    })
    -- 面板 easeOutBack
    Tween.to(goAnim_, { panelScale = 1, panelAlpha = 1 }, 0.45, {
        easing = Tween.Easing.easeOutBack, delay = 0.1
    })
    -- 标题 easeOutBack
    Tween.to(goAnim_, { titleScale = 1, titleAlpha = 1 }, 0.4, {
        easing = Tween.Easing.easeOutBack, delay = 0.25
    })
    -- 击杀数滑入
    Tween.to(goAnim_, { killsAlpha = 1, killsY = 0 }, 0.4, {
        easing = Tween.Easing.easeOutCubic, delay = 0.4
    })
    -- TAP TO RESTART 渐入
    Tween.to(goAnim_, { tapAlpha = 1 }, 0.35, {
        easing = Tween.Easing.easeOutCubic, delay = 0.6
    })
end

--- HUD 数值变化时触发弹跳
function M.pulseHUD(field)
    if field == "hp" then
        Tween.cancelTarget(hudAnim_)
        hudAnim_.hpScale = 1.25
        Tween.to(hudAnim_, { hpScale = 1.0 }, 0.35, { easing = Tween.Easing.easeOutElastic })
    elseif field == "kills" then
        hudAnim_.killScale = 1.3
        Tween.to(hudAnim_, { killScale = 1.0 }, 0.4, { easing = Tween.Easing.easeOutElastic })
    elseif field == "orbit" then
        hudAnim_.orbitScale = 1.35
        Tween.to(hudAnim_, { orbitScale = 1.0 }, 0.4, { easing = Tween.Easing.easeOutElastic })
    end
end

-- ══════════════════════════════════════════════════════════════
-- 暂停系统
-- ══════════════════════════════════════════════════════════════
function M.isPaused()
    return paused_
end

function M.showPause()
    if paused_ then return end
    paused_ = true

    Tween.cancelTarget(pauseAnim_)
    pauseAnim_.maskAlpha  = 0
    pauseAnim_.panelScale = 0
    pauseAnim_.panelAlpha = 0
    pauseAnim_.titleAlpha = 0
    pauseAnim_.btnAlpha   = 0

    Tween.to(pauseAnim_, { maskAlpha = 1 }, 0.30, {
        easing = Tween.Easing.easeOutCubic, delay = 0.0
    })
    Tween.to(pauseAnim_, { panelScale = 1, panelAlpha = 1 }, 0.40, {
        easing = Tween.Easing.easeOutBack, delay = 0.05
    })
    Tween.to(pauseAnim_, { titleAlpha = 1 }, 0.30, {
        easing = Tween.Easing.easeOutCubic, delay = 0.15
    })
    Tween.to(pauseAnim_, { btnAlpha = 1 }, 0.30, {
        easing = Tween.Easing.easeOutCubic, delay = 0.25
    })
end

function M.hidePause()
    if not paused_ then return end
    paused_ = false

    Tween.cancelTarget(pauseAnim_)
    Tween.to(pauseAnim_, { maskAlpha = 0, panelScale = 0.9, panelAlpha = 0, titleAlpha = 0, btnAlpha = 0 }, 0.25, {
        easing = Tween.Easing.easeOutCubic
    })
end

--- 暂停界面点击处理，返回 action 字符串或 nil
function M.onPauseClick(x, y)
    if not paused_ then return nil end
    if Comp.hitTest(resumeBtnRect_, x, y) then
        return "resume"
    elseif Comp.hitTest(menuBtnRect_, x, y) then
        return "menu"
    end
    return nil
end

--- 暂停按钮点击检测（仅 playing 状态用）
function M.hitPauseButton(x, y)
    return Comp.hitTest(pauseBtnRect_, x, y)
end

-- ——— 主绘制入口 ———
function M.draw(vg, state)
    vg_ = vg

    if state == "menu" then
        drawMenu()
    elseif state == "playing" then
        local Player = require("game.Player")
        local p = Player.getData()
        drawHUD(p)
        drawButtons(p)
        drawPauseButton()
        if paused_ then
            drawPauseOverlay()
        end
    elseif state == "upgrade" then
        local Player = require("game.Player")
        local p = Player.getData()
        drawHUD(p)
        Upgrade.draw(vg, W_, H_)
    elseif state == "gameover" then
        drawGameOver()
    end
end

-- ══════════════════════════════════════════════════════════════
-- 菜单界面
-- ══════════════════════════════════════════════════════════════
function drawMenu()
    if not menuVisible_ then return end

    local cx = W_ * 0.5
    local cy = H_ * 0.5
    local ma = menuAnim_

    -- 全屏背景（暗绿+花纹）
    Comp.drawBackground(vg_, W_, H_)

    -- 中央面板（easeOutBack 缩放弹入）
    local pw, ph = math.min(320, W_ * 0.8), math.min(280, H_ * 0.7)
    local px, py = cx - pw * 0.5, cy - ph * 0.5

    if ma.panelAlpha > 0.01 then
        nvgSave(vg_)
        nvgTranslate(vg_, cx, cy)
        nvgScale(vg_, ma.panelScale, ma.panelScale)
        nvgTranslate(vg_, -cx, -cy)
        nvgGlobalAlpha(vg_, ma.panelAlpha)
        Comp.drawPanel(vg_, px, py, pw, ph)
        nvgGlobalAlpha(vg_, 1.0)
        nvgRestore(vg_)
    end

    -- 标题（easeOutBack 弹入）
    if ma.titleAlpha > 0.01 then
        nvgSave(vg_)
        local titleY = py + 50
        nvgTranslate(vg_, cx, titleY)
        nvgScale(vg_, ma.titleScale, ma.titleScale)
        nvgTranslate(vg_, -cx, -titleY)
        nvgGlobalAlpha(vg_, ma.titleAlpha)
        Comp.drawTitle(vg_, cx, titleY, "BULLET THIEF", Theme.font.title)
        nvgGlobalAlpha(vg_, 1.0)
        nvgRestore(vg_)
    end

    -- 副标题（渐入）
    if ma.subtitleAlpha > 0.01 then
        nvgFontFace(vg_, Theme.font.family)
        nvgFontSize(vg_, Theme.font.body)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.mutedText, ma.subtitleAlpha)))
        nvgText(vg_, cx, py + 85, "Steal bullets. Become unstoppable.")
    end

    -- 装饰轨道（渐入）
    if ma.orbitAlpha > 0.01 then
        nvgSave(vg_)
        nvgGlobalAlpha(vg_, ma.orbitAlpha)
        drawDecorativeOrbit(cx, py + 150, os.clock())
        nvgGlobalAlpha(vg_, 1.0)
        nvgRestore(vg_)
    end

    -- "TAP TO START" 闪烁（渐入后才开始闪）+ hover 加亮
    if ma.tapAlpha > 0.01 then
        local t = os.clock()
        local blink = (math.sin(t * 3.5) + 1) * 0.5
        local tapY = py + ph - 40
        -- hover 检测（文字区域大致范围）
        local tapHov = Comp.isPointerInRect(cx - 80, tapY - 12, 160, 24)
        local baseAlpha = tapHov and 1.0 or (0.6 + blink * 0.4)
        local fontSize = tapHov and (Theme.font.subtitle + 1) or Theme.font.subtitle

        nvgFontFace(vg_, Theme.font.family)
        nvgFontSize(vg_, fontSize)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.accent, ma.tapAlpha * baseAlpha)))
        nvgText(vg_, cx, tapY, "TAP TO START")
    end
end

function drawDecorativeOrbit(cx, cy, t)
    local n    = 8
    local r1   = 30
    local r2   = 48

    -- 外环
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, r2)
    nvgStrokeColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.panelBorder, 0.25)))
    nvgStrokeWidth(vg_, 1.0)
    nvgStroke(vg_)

    -- 外环子弹
    for i = 1, n do
        local a  = (i / n) * math.pi * 2 + t * 1.8
        local bx = cx + math.cos(a) * r2
        local by = cy + math.sin(a) * r2
        nvgBeginPath(vg_)
        nvgCircle(vg_, bx, by, 5)
        nvgFillColor(vg_, nvgRGBAf(Theme.c(Theme.colors.accentGreen)))
        nvgFill(vg_)
    end

    -- 内环
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, r1)
    nvgStrokeColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.accent, 0.25)))
    nvgStrokeWidth(vg_, 1.0)
    nvgStroke(vg_)

    for i = 1, n - 2 do
        local a  = (i / (n - 2)) * math.pi * 2 - t * 1.2
        local bx = cx + math.cos(a) * r1
        local by = cy + math.sin(a) * r1
        nvgBeginPath(vg_)
        nvgCircle(vg_, bx, by, 4)
        nvgFillColor(vg_, nvgRGBAf(Theme.c(Theme.colors.accent)))
        nvgFill(vg_)
    end

    -- 中心六边形
    nvgBeginPath(vg_)
    for i = 0, 5 do
        local a = i * math.pi / 3 - math.pi / 6
        local px = cx + math.cos(a) * 12
        local py = cy + math.sin(a) * 12
        if i == 0 then nvgMoveTo(vg_, px, py)
        else nvgLineTo(vg_, px, py) end
    end
    nvgClosePath(vg_)
    nvgFillColor(vg_, nvgRGBAf(Theme.c(Theme.colors.panelBg)))
    nvgFill(vg_)
    nvgStrokeColor(vg_, nvgRGBAf(Theme.c(Theme.colors.panelBorder)))
    nvgStrokeWidth(vg_, 2.0)
    nvgStroke(vg_)
end

-- ══════════════════════════════════════════════════════════════
-- HUD（血条 + 击杀数 + 轨道弹数）
-- ══════════════════════════════════════════════════════════════
function drawHUD(p)
    local barX, barY = 16, 16
    local barW = math.min(130, W_ * 0.3)
    local barH = Theme.bar.height

    -- 检测数值变化并触发弹跳
    local curHp = math.floor(p.hp)
    if lastHp_ >= 0 and curHp ~= lastHp_ then
        M.pulseHUD("hp")
    end
    lastHp_ = curHp

    local kills = p.killCount or 0
    if lastKills_ >= 0 and kills ~= lastKills_ then
        M.pulseHUD("kills")
    end
    lastKills_ = kills

    local BulletMgr = require("game.BulletManager")
    local orbitCount = #BulletMgr.getOrbitBullets()
    if lastOrbit_ >= 0 and orbitCount ~= lastOrbit_ then
        M.pulseHUD("orbit")
    end
    lastOrbit_ = orbitCount

    -- HP 条（带弹跳缩放）
    local hpRatio = p.hp / p.maxHp
    local hpColor
    if hpRatio > 0.5 then
        hpColor = Theme.colors.hpGreen
    elseif hpRatio > 0.25 then
        hpColor = Theme.colors.hpOrange
    else
        hpColor = Theme.colors.hpRed
    end

    local hpCx = barX + barW * 0.5
    local hpCy = barY + 14 + barH * 0.5
    nvgSave(vg_)
    nvgTranslate(vg_, hpCx, hpCy)
    nvgScale(vg_, hudAnim_.hpScale, hudAnim_.hpScale)
    nvgTranslate(vg_, -hpCx, -hpCy)
    Comp.drawProgressBar(vg_, barX, barY + 14, barW, barH, hpRatio, hpColor, {
        label = "HP " .. math.floor(p.hp) .. "/" .. p.maxHp
    })
    nvgRestore(vg_)

    -- 击杀进度条（带弹跳缩放）
    local nextThresh = Upgrade.getNextThreshold()
    local killRatio = math.min(1.0, kills / nextThresh)

    local killCx = barX + barW * 0.5
    local killCy = barY + 42 + 4
    nvgSave(vg_)
    nvgTranslate(vg_, killCx, killCy)
    nvgScale(vg_, hudAnim_.killScale, hudAnim_.killScale)
    nvgTranslate(vg_, -killCx, -killCy)
    Comp.drawProgressBar(vg_, barX, barY + 42, barW, 8, killRatio, Theme.colors.killYellow, {
        label = "KILLS " .. kills .. "/" .. nextThresh
    })
    nvgRestore(vg_)

    -- 轨道子弹计数（右上角胶囊，暂停按钮左侧，带弹跳缩放）
    if orbitCount > 0 then
        local orbCx = W_ - 50 - 36  -- 为暂停按钮留出空间
        local orbCy = 26
        nvgSave(vg_)
        nvgTranslate(vg_, orbCx, orbCy)
        nvgScale(vg_, hudAnim_.orbitScale, hudAnim_.orbitScale)
        nvgTranslate(vg_, -orbCx, -orbCy)
        Comp.drawBadge(vg_, orbCx, orbCy, "x" .. orbitCount, Theme.colors.panelBgDark, Theme.colors.lightText)

        nvgFontFace(vg_, Theme.font.family)
        nvgFontSize(vg_, Theme.font.small)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, nvgRGBAf(Theme.c(Theme.colors.titleText)))
        nvgText(vg_, orbCx, 44, "ORBIT")
        nvgRestore(vg_)
    end

    -- 子弹时间状态
    if p.bulletTimeActive then
        local blink = (math.sin(os.clock() * 8) + 1) * 0.5
        Comp.drawBadge(vg_, W_ * 0.5, 22, "BULLET TIME",
            { 0.30, 0.85, 0.90, 0.7 + blink * 0.3 }, Theme.colors.white)
    end
end

-- ══════════════════════════════════════════════════════════════
-- 操作按钮（BT + FIRE）
-- ══════════════════════════════════════════════════════════════
function drawButtons(p)
    local InputH = require("game.InputHandler")
    local btBtn, fireBtn = InputH.getButtonRects()

    -- BT（闪避/子弹时间）按钮（左下）
    local btActive = InputH.isBulletTimeHeld()
    local btDisabled = (p.energy or 0) < 0.05  -- 能量不足时变透明
    Comp.drawCircleButton(vg_, btBtn.x, btBtn.y, btBtn.r, "BT", {
        active    = btActive,
        fillRatio = p.energy,
        arcColor  = Theme.colors.energyCyan,
        icon      = iconDodge_,
        disabled  = btDisabled,
    })

    -- FIRE（攻击）按钮（右下）
    local fireActive = InputH.isFireHeld()
    local BulletMgr = require("game.BulletManager")
    local orbitCount = #(BulletMgr.getOrbitBullets())
    local fireDisabled = (orbitCount <= 0)  -- 没子弹时变透明
    Comp.drawCircleButton(vg_, fireBtn.x, fireBtn.y, fireBtn.r, "FIRE", {
        active    = fireActive,
        fillRatio = (orbitCount > 0) and 1.0 or 0.0,
        arcColor  = Theme.colors.accentYellow,
        icon      = iconAttack_,
        disabled  = fireDisabled,
    })

    -- QTE 音游缩圈（在 FIRE 按钮上）
    local qte = BulletMgr.getQTEState()
    if qte.active then
        local QTE_WINDOW = 1.5  -- 需要和 BulletManager 中 QTE_CFG.window 一致
        local progress = 1.0 - (qte.timer / QTE_WINDOW)  -- 0→1
        -- 从按钮外围 2.5 倍收缩到按钮边缘
        local maxR = fireBtn.r * 2.5
        local minR = fireBtn.r + 2
        local ringR = maxR - (maxR - minR) * progress

        -- 透明度：淡入 + 最后闪烁
        local ringAlpha
        if progress < 0.08 then
            ringAlpha = progress / 0.08
        elseif qte.timer < 0.4 then
            ringAlpha = 0.6 + 0.4 * math.abs(math.sin(qte.timer * 16))
        else
            ringAlpha = 0.9
        end

        -- 缩圈
        nvgBeginPath(vg_)
        nvgCircle(vg_, fireBtn.x, fireBtn.y, ringR)
        nvgStrokeColor(vg_, nvgRGBAf(1.0, 0.95, 0.3, ringAlpha))
        nvgStrokeWidth(vg_, 4.0)
        nvgStroke(vg_)

        -- 内圈目标参照（按钮边缘）
        nvgBeginPath(vg_)
        nvgCircle(vg_, fireBtn.x, fireBtn.y, minR)
        nvgStrokeColor(vg_, nvgRGBAf(1.0, 1.0, 1.0, 0.3))
        nvgStrokeWidth(vg_, 1.5)
        nvgStroke(vg_)
    end
end

-- ══════════════════════════════════════════════════════════════
-- 暂停按钮（右上角矢量图标）
-- ══════════════════════════════════════════════════════════════
function drawPauseButton()
    local size = 32
    local margin = 16
    local bx = W_ - margin - size
    local by = margin
    pauseBtnRect_ = { x = bx, y = by, w = size, h = size }

    local cx = bx + size * 0.5
    local cy = by + size * 0.5
    local r  = size * 0.5

    -- hover 检测
    local hov = Comp.isPointerInRect(bx, by, size, size)

    -- 背景圆
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, r)
    nvgFillColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.panelBgDark, hov and 0.9 or 0.7)))
    nvgFill(vg_)

    -- 描边
    nvgBeginPath(vg_)
    nvgCircle(vg_, cx, cy, r)
    nvgStrokeColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.panelBorder, hov and 1.0 or 0.6)))
    nvgStrokeWidth(vg_, 1.5)
    nvgStroke(vg_)

    -- hover 高亮
    if hov then
        nvgBeginPath(vg_)
        nvgCircle(vg_, cx, cy, r)
        nvgFillColor(vg_, nvgRGBAf(1, 1, 1, 0.12))
        nvgFill(vg_)
    end

    -- 暂停图标：两条竖线 ||
    local barW = 3.0
    local barH = r * 0.7
    local gap  = 3.5
    local iconColor = hov and Theme.colors.white or Theme.colors.lightText

    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, cx - gap - barW, cy - barH * 0.5, barW, barH, 1.0)
    nvgFillColor(vg_, nvgRGBAf(Theme.c(iconColor)))
    nvgFill(vg_)

    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, cx + gap, cy - barH * 0.5, barW, barH, 1.0)
    nvgFillColor(vg_, nvgRGBAf(Theme.c(iconColor)))
    nvgFill(vg_)
end

-- ══════════════════════════════════════════════════════════════
-- 暂停弹窗
-- ══════════════════════════════════════════════════════════════
function drawPauseOverlay()
    local pa = pauseAnim_
    local cx = W_ * 0.5
    local cy = H_ * 0.5

    -- 遮罩
    if pa.maskAlpha > 0.01 then
        nvgBeginPath(vg_)
        nvgRect(vg_, 0, 0, W_, H_)
        local or_, og, ob = Theme.c(Theme.colors.overlay)
        nvgFillColor(vg_, nvgRGBAf(or_, og, ob, Theme.colors.overlayAlpha * pa.maskAlpha))
        nvgFill(vg_)
    end

    -- 面板
    local pw, ph = 220, 170
    local px, py = cx - pw * 0.5, cy - ph * 0.5

    if pa.panelAlpha > 0.01 then
        nvgSave(vg_)
        nvgTranslate(vg_, cx, cy)
        nvgScale(vg_, pa.panelScale, pa.panelScale)
        nvgTranslate(vg_, -cx, -cy)
        nvgGlobalAlpha(vg_, pa.panelAlpha)
        Comp.drawPanel(vg_, px, py, pw, ph)
        nvgGlobalAlpha(vg_, 1.0)
        nvgRestore(vg_)
    end

    -- 标题
    if pa.titleAlpha > 0.01 then
        nvgGlobalAlpha(vg_, pa.titleAlpha)
        Comp.drawTitle(vg_, cx, py + 40, "PAUSED", 24, Theme.colors.titleText)
        nvgGlobalAlpha(vg_, 1.0)
    end

    -- 按钮
    if pa.btnAlpha > 0.01 then
        nvgGlobalAlpha(vg_, pa.btnAlpha)

        -- 继续游戏按钮
        local resumeResult = Comp.drawButton(vg_, cx, cy + 10, "RESUME", { variant = "primary", w = 160 })
        resumeBtnRect_ = resumeResult

        -- 回到菜单按钮
        local menuResult = Comp.drawButton(vg_, cx, cy + 56, "MAIN MENU", { variant = "accent", w = 160 })
        menuBtnRect_ = menuResult

        nvgGlobalAlpha(vg_, 1.0)
    end
end

-- ══════════════════════════════════════════════════════════════
-- 游戏结束界面
-- ══════════════════════════════════════════════════════════════
function drawGameOver()
    if not gameoverVisible_ then return end

    local ga = goAnim_
    local cx = W_ * 0.5
    local cy = H_ * 0.5

    -- 遮罩（渐入，带色调）
    if ga.maskAlpha > 0.01 then
        nvgBeginPath(vg_)
        nvgRect(vg_, 0, 0, W_, H_)
        local or_, og, ob = Theme.c(Theme.colors.overlay)
        nvgFillColor(vg_, nvgRGBAf(or_, og, ob, Theme.colors.overlayAlpha * ga.maskAlpha))
        nvgFill(vg_)
    end

    -- 面板（easeOutBack 弹入）
    local pw, ph = 260, 200
    local px, py = cx - pw * 0.5, cy - ph * 0.5

    if ga.panelAlpha > 0.01 then
        nvgSave(vg_)
        nvgTranslate(vg_, cx, cy)
        nvgScale(vg_, ga.panelScale, ga.panelScale)
        nvgTranslate(vg_, -cx, -cy)
        nvgGlobalAlpha(vg_, ga.panelAlpha)
        Comp.drawPanel(vg_, px, py, pw, ph, { borderColor = Theme.colors.accent })
        nvgGlobalAlpha(vg_, 1.0)
        nvgRestore(vg_)
    end

    -- 标题（easeOutBack 弹入）
    if ga.titleAlpha > 0.01 then
        nvgSave(vg_)
        local titleY = py + 45
        nvgTranslate(vg_, cx, titleY)
        nvgScale(vg_, ga.titleScale, ga.titleScale)
        nvgTranslate(vg_, -cx, -titleY)
        nvgGlobalAlpha(vg_, ga.titleAlpha)
        Comp.drawTitle(vg_, cx, titleY, "GAME OVER", 30, Theme.colors.accent)
        nvgGlobalAlpha(vg_, 1.0)
        nvgRestore(vg_)
    end

    -- 击杀数（滑入+渐入）
    if ga.killsAlpha > 0.01 then
        nvgFontFace(vg_, Theme.font.family)
        nvgFontSize(vg_, Theme.font.subtitle)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.bodyText, ga.killsAlpha)))
        nvgText(vg_, cx, cy + 5 + ga.killsY, "Orbit Kills: " .. finalKills_)
    end

    -- 重开提示（渐入+闪烁）+ hover 加亮
    if ga.tapAlpha > 0.01 then
        local blink = (math.sin(os.clock() * 3.0) + 1) * 0.5
        local restartY = cy + 55
        local restartHov = Comp.isPointerInRect(cx - 80, restartY - 12, 160, 24)
        local baseAlpha = restartHov and 1.0 or (0.6 + blink * 0.4)
        local fontSize = restartHov and (Theme.font.body + 1) or Theme.font.body

        nvgFontFace(vg_, Theme.font.family)
        nvgFontSize(vg_, fontSize)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, nvgRGBAf(Theme.ca(Theme.colors.accent, ga.tapAlpha * baseAlpha)))
        nvgText(vg_, cx, restartY, "TAP TO RESTART")
    end
end

return M
