-- ============================================================================
-- characters/Xingye.lua - 主角「星夜」绘制模块
-- 梦灵少女，深蓝短发 + 星形发卡 + 浅灰蓝睡衣
-- ============================================================================

local Xingye = {}

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

--- 绘制主角「星夜」Q版小人（伪3D视差：nvgScale翻转 + fx逐层偏移）
---@param vg any NanoVG上下文
---@param cx number 屏幕中心X
---@param cy number 屏幕中心Y
---@param r number 角色半径（用于缩放）
---@param flash number 受击闪白（0~1）
---@param age number 动画累计时间
---@param dir number 朝向（1=右，-1=左）
---@param face_yaw number 伪3D偏转量（0~0.6）
function Xingye.draw(vg, cx, cy, r, flash, age, dir, face_yaw)
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
    local bodyTopY = headBot + 0.5 * s   -- 身体顶端略低于头底
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
    local backHairFx = fx * -0.3  -- 后发反向偏移

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
    local hairGrad = nvgLinearGradient(vg, 0, bhTop, 0, bhBot,
        nvgRGBAf(0.10, 0.08, 0.25, 1.0),
        nvgRGBAf(0.35, 0.25, 0.55, 1.0))
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
    local armBaseAngle = 0.45
    local armSwing = math.sin(age * 6.0) * 0.2
    local armNarrow = fx * 0.2

    -- 左臂
    nvgSave(vg)
    nvgTranslate(vg, -bodyTopW - armW * 0.3 + armNarrow, shoulderY)
    nvgRotate(vg, armBaseAngle + armSwing)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -armW / 2, 0, armW, armH, armW / 2)
    nvgFillColor(vg, nvgRGBAf(skinR, skinG, skinB, 1.0))
    nvgFill(vg)
    nvgRestore(vg)

    -- 右臂
    nvgSave(vg)
    nvgTranslate(vg, bodyTopW + armW * 0.3 - armNarrow, shoulderY)
    nvgRotate(vg, -armBaseAngle - armSwing)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -armW / 2, 0, armW, armH, armW / 2)
    nvgFillColor(vg, nvgRGBAf(skinR, skinG, skinB, 1.0))
    nvgFill(vg)
    nvgRestore(vg)

    -- === 5. 脚/拖鞋（保持在下方，伪3D内收）===
    local moveAmount = face_yaw / 0.6  -- 0=静止 1=移动中
    local footSwing = math.sin(age * 8.0) * 1.2 * s * moveAmount
    local legNarrow = fx * 0.1
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
    local bangInnerGap = 1.5 * s
    local bangMidW = 3.5 * s
    for i = 0, bangCount - 1 do
        local bLeft, bRight
        if i == 0 then
            bRight = -bangInnerGap - bangMidW
            bLeft = hairLeft
        elseif i == 1 then
            bLeft = -bangMidW
            bRight = bangMidW
        else
            bLeft = bangInnerGap + bangMidW
            bRight = hairRight
        end
        local bw = bRight - bLeft
        local bh = 4.5 * s + (i % 2) * 1.0 * s + 2.5 * s
        local bRad = math.min(bw * 0.2, 2 * s)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bLeft, bangY - 3 * s, bw, bh, bRad)
        nvgFillColor(vg, nvgRGBAf(hairFR, hairFG, hairFB, 1.0))
        nvgFill(vg)
    end

    -- === 8. 眼睛（贴近头底边，伪3D偏移）===
    local eyeW = 3.0 * s
    local eyeH = 4.0 * s
    local eyeY = headCY + 8 * s
    local eyeSpacing = 5.5 * s
    local eyeBaseOut = 0.75 * eyeW
    local eyeFx = fx * 0.2
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
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeLX - 0.5 * s, blushY, blushRx, blushRy)
    nvgFillColor(vg, nvgRGBAf(0.95, 0.55, 0.55, blushAlpha))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeRX + 0.5 * s, blushY, blushRx, blushRy)
    nvgFillColor(vg, nvgRGBAf(0.95, 0.55, 0.55, blushAlpha))
    nvgFill(vg)

    -- === 9. 星星发夹（固定右侧，伪3D fx*0.45）===
    local starFx = fx * 0.45
    local starCX = (headW / 2 - 3 * s) + starFx
    local starCY2 = headCY - 1 * s
    local starOuter = 5.5 * s
    local starInner = 2.5 * s
    local starRot = math.sin(age * 2.5) * 0.1
    nvgSave(vg)
    nvgTranslate(vg, starCX, starCY2)
    nvgRotate(vg, starRot)
    nvgBeginPath(vg)
    starPath(vg, 0, 0, starOuter, starInner)
    nvgFillColor(vg, nvgRGBAf(starClr[1], starClr[2], starClr[3], 1.0))
    nvgFill(vg)
    nvgRestore(vg)

    nvgRestore(vg)
end

return Xingye
