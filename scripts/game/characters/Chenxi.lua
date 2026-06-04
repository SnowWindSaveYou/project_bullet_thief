-- ============================================================================
-- characters/Chenxi.lua - 第二角色「晨曦」绘制模块
-- 白日面清醒梦者，金色短发 + 小王冠发夹 + 淡绿上衣 + 黄色围巾
-- ============================================================================

local Chenxi = {}

-- 绘制小王冠路径（辅助函数）
local function crownPath(vg, cx, cy, w, h)
    -- 三齿小王冠
    local left = cx - w / 2
    local right = cx + w / 2
    local top = cy - h / 2
    local bot = cy + h / 2
    nvgMoveTo(vg, left, bot)
    nvgLineTo(vg, left, top + h * 0.3)
    nvgLineTo(vg, cx - w * 0.25, top + h * 0.55)
    nvgLineTo(vg, cx - w * 0.12, top)
    nvgLineTo(vg, cx, top + h * 0.4)
    nvgLineTo(vg, cx + w * 0.12, top)
    nvgLineTo(vg, cx + w * 0.25, top + h * 0.55)
    nvgLineTo(vg, right, top + h * 0.3)
    nvgLineTo(vg, right, bot)
    nvgClosePath(vg)
end

--- 绘制角色「晨曦」Q版小人（伪3D视差：nvgScale翻转 + fx逐层偏移）
---@param vg any NanoVG上下文
---@param cx number 屏幕中心X
---@param cy number 屏幕中心Y
---@param r number 角色半径（用于缩放）
---@param flash number 受击闪白（0~1）
---@param age number 动画累计时间
---@param dir number 朝向（1=右，-1=左）
---@param face_yaw number 伪3D偏转量（0~0.6）
function Chenxi.draw(vg, cx, cy, r, flash, age, dir, face_yaw)
    local s = r / 18.0  -- 基于 radius=18 设计

    -- 伪3D视差基准
    local fx = face_yaw * 20  -- 范围 0~12

    -- 走路弹跳
    local bobY = math.abs(math.sin(age * 8.0)) * 2.0 * s

    -- 颜色
    local hairFR, hairFG, hairFB = 1.0, 0.84, 0.0       -- #FFD700 金色
    local hairBkR, hairBkG, hairBkB = 0.85, 0.70, 0.0   -- 深金色
    local topR, topG, topB = 0.72, 0.90, 0.78           -- #B8E6C8 淡绿
    local topDkR, topDkG, topDkB = 0.55, 0.75, 0.60    -- 暗绿
    local skinR, skinG, skinB = 0.96, 0.89, 0.85
    local crownClr = {0.91, 0.91, 0.94}                 -- #E8E8F0 银白
    local eyeTopR, eyeTopG, eyeTopB = 0.85, 0.55, 0.15  -- 琥珀上半
    local eyeBotR, eyeBotG, eyeBotB = 1.0, 0.67, 0.20   -- #FFAA33 琥珀下半
    local scarfR, scarfG, scarfB = 1.0, 0.88, 0.40       -- #FFE066 黄色围巾
    local shortsR, shortsG, shortsB = 0.94, 0.94, 0.94   -- #F0F0F0 白色短裤

    -- 受击闪白
    if flash > 0 then
        local f = flash
        hairFR  = hairFR + (1 - hairFR) * f
        hairFG  = hairFG + (1 - hairFG) * f
        hairFB  = hairFB + (1 - hairFB) * f
        hairBkR = hairBkR + (1 - hairBkR) * f
        hairBkG = hairBkG + (1 - hairBkG) * f
        hairBkB = hairBkB + (1 - hairBkB) * f
        topR    = topR + (1 - topR) * f
        topG    = topG + (1 - topG) * f
        topB    = topB + (1 - topB) * f
    end

    nvgSave(vg)
    nvgTranslate(vg, cx, cy - bobY)
    nvgScale(vg, dir, 1)  -- Layer 1: 整体左右翻转

    -- 布局：与星夜相同
    local headCY = -7 * s
    local headW  = 26 * s
    local headH  = 24 * s
    local headRad = 3 * s
    local headBot = headCY + headH / 2

    local bodyCY = headBot + 3.5 * s
    local bodyTopW = 2.0 * s
    local bodyBotW = 6 * s
    local bodyTopY = headBot + 0.5 * s
    local bodyBotY = bodyCY + 3.5 * s

    local footY = bodyCY + 11 * s

    -- === 1. 阴影 ===
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, footY + 3 * s, 7 * s, 2.5 * s)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.22))
    nvgFill(vg)

    -- === 2. 后发（金色渐变，蓬松短发）===
    local bhTop = headCY - headH / 2 + 1 * s
    local bhBot = headCY + headH / 2 + 2 * s  -- 比星夜略短
    local bhTopW = headW * 0.35
    local bhBotW = headW * 0.55
    local backHairFx = fx * -0.3

    nvgBeginPath(vg)
    local bfx = backHairFx
    nvgMoveTo(vg, -bhTopW + bfx, bhTop)
    nvgLineTo(vg, bhTopW + bfx, bhTop)
    nvgBezierTo(vg, bhBotW + 2 * s + bfx, bhTop + (bhBot - bhTop) * 0.4,
        bhBotW + 1 * s + bfx, bhBot - 3 * s, bhBotW + bfx, bhBot)
    nvgBezierTo(vg, bhBotW - 3 * s + bfx, bhBot + 1.5 * s, -bhBotW + 3 * s + bfx, bhBot + 1.5 * s, -bhBotW + bfx, bhBot)
    nvgBezierTo(vg, -bhBotW - 1 * s + bfx, bhBot - 3 * s, -bhBotW - 2 * s + bfx, bhTop + (bhBot - bhTop) * 0.4,
        -bhTopW + bfx, bhTop)
    nvgClosePath(vg)
    local hairGrad = nvgLinearGradient(vg, 0, bhTop, 0, bhBot,
        nvgRGBAf(hairBkR, hairBkG, hairBkB, 1.0),
        nvgRGBAf(1.0, 0.96, 0.72, 1.0))  -- #FFF4B8 淡金
    nvgFillPaint(vg, hairGrad)
    nvgFill(vg)

    -- === 3. 身体（淡绿短袖）===
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
    nvgFillColor(vg, nvgRGBAf(topR, topG, topB, 1.0))
    nvgFill(vg)

    -- 下摆暗色带
    nvgBeginPath(vg)
    nvgMoveTo(vg, -bodyBotW + 1 * s, bodyBotY)
    nvgBezierTo(vg, -bodyBotW + 2 * s, bodyBotY + 1.5 * s, bodyBotW - 2 * s, bodyBotY + 1.5 * s, bodyBotW - 1 * s, bodyBotY)
    nvgStrokeColor(vg, nvgRGBAf(topDkR, topDkG, topDkB, 1.0))
    nvgStrokeWidth(vg, 2 * s)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 围巾（在领口飘出，黄色）
    local scarfY = bodyTopY + 0.5 * s
    local scarfWave = math.sin(age * 3.5) * 1.5 * s
    -- 围巾左飘尾
    nvgBeginPath(vg)
    nvgMoveTo(vg, -bodyTopW - 1 * s, scarfY)
    nvgBezierTo(vg, -bodyTopW - 3 * s, scarfY + 4 * s + scarfWave,
                    -bodyTopW - 5 * s + scarfWave, scarfY + 7 * s,
                    -bodyTopW - 4 * s, scarfY + 10 * s + scarfWave)
    nvgStrokeColor(vg, nvgRGBAf(scarfR, scarfG, scarfB, 0.9))
    nvgStrokeWidth(vg, 3.5 * s)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
    -- 围巾领口
    nvgBeginPath(vg)
    nvgMoveTo(vg, -bodyTopW - 1 * s, scarfY)
    nvgBezierTo(vg, -1 * s, scarfY + 2 * s, 1 * s, scarfY + 2 * s, bodyTopW + 1 * s, scarfY)
    nvgStrokeColor(vg, nvgRGBAf(scarfR, scarfG, scarfB, 1.0))
    nvgStrokeWidth(vg, 3 * s)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgRestore(vg)  -- 结束身体变换

    -- === 4. 手臂（和星夜一样的肤色手臂）===
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

    -- === 5. 脚（赤脚，无拖鞋，简单圆形小脚）===
    local moveAmount = face_yaw / 0.6
    local footSwing = math.sin(age * 8.0) * 1.2 * s * moveAmount
    local legNarrow = fx * 0.1
    for _, side in ipairs({-1, 1}) do
        local footNrw = (side < 0) and legNarrow or -legNarrow
        local ftx = side * 3.5 * s + footNrw
        local fy = footY + side * footSwing
        -- 赤脚（肤色小椭圆）
        nvgBeginPath(vg)
        nvgEllipse(vg, ftx, fy, 3 * s, 2 * s)
        nvgFillColor(vg, nvgRGBAf(skinR, skinG, skinB, 1.0))
        nvgFill(vg)
    end

    -- === 6. 脸 ===
    local faceW = headW - 8 * s
    local faceH = headH - 5 * s
    local faceY = headCY + 3 * s
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -faceW / 2, faceY - faceH / 2, faceW, faceH, headRad)
    nvgFillColor(vg, nvgRGBAf(skinR, skinG, skinB, 1.0))
    nvgFill(vg)

    -- === 7. 前发（金色弧形 + 3片刘海）===
    local frontHairFx = fx * 0.35
    local bangY = headCY + 3 * s
    local hairTop = headCY - headH / 2 - 1 * s
    local hairLeft = -headW / 2 - 1 * s + frontHairFx
    local hairRight = headW / 2 + 1 * s + frontHairFx

    -- 前发主体
    nvgBeginPath(vg)
    nvgMoveTo(vg, hairLeft, bangY)
    nvgLineTo(vg, hairRight, bangY)
    nvgBezierTo(vg, hairRight, hairTop + 4 * s, hairRight - 5 * s, hairTop, frontHairFx, hairTop)
    nvgBezierTo(vg, hairLeft + 5 * s, hairTop, hairLeft, hairTop + 4 * s, hairLeft, bangY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(hairFR, hairFG, hairFB, 1.0))
    nvgFill(vg)

    -- 刘海发片（3片）
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

    -- === 8. 眼睛（琥珀色，十字高光）===
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

        -- 上半（琥珀深色）
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

        -- 下半（琥珀亮色）
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

        -- 十字高光（区别于星夜的圆形高光）
        nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.9))
        nvgStrokeWidth(vg, 0.8 * s)
        nvgLineCap(vg, NVG_ROUND)
        -- 竖线
        nvgBeginPath(vg)
        nvgMoveTo(vg, ex + 0.5 * s, eyeY - 1.2 * s)
        nvgLineTo(vg, ex + 0.5 * s, eyeY + 0.4 * s)
        nvgStroke(vg)
        -- 横线
        nvgBeginPath(vg)
        nvgMoveTo(vg, ex - 0.3 * s, eyeY - 0.4 * s)
        nvgLineTo(vg, ex + 1.3 * s, eyeY - 0.4 * s)
        nvgStroke(vg)
    end

    -- === 8.5 腮红 ===
    local blushY = eyeY + 2.5 * s
    local blushRx = 2.8 * s
    local blushRy = 1.5 * s
    local blushAlpha = 0.35
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeLX - 0.5 * s, blushY, blushRx, blushRy)
    nvgFillColor(vg, nvgRGBAf(0.95, 0.65, 0.45, blushAlpha))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeRX + 0.5 * s, blushY, blushRx, blushRy)
    nvgFillColor(vg, nvgRGBAf(0.95, 0.65, 0.45, blushAlpha))
    nvgFill(vg)

    -- === 9. 小王冠发夹（固定视觉右侧）===
    local crownFx = fx * 0.45
    local crownCX = (headW / 2 - 3 * s) + crownFx
    local crownCY = headCY - 3 * s
    local crownW = 8 * s
    local crownH = 6 * s
    local crownRot = math.sin(age * 2.0) * 0.08

    nvgSave(vg)
    nvgTranslate(vg, crownCX * dir, crownCY)
    nvgScale(vg, dir, 1)  -- 抵消外层翻转
    nvgRotate(vg, crownRot)
    nvgBeginPath(vg)
    crownPath(vg, 0, 0, crownW, crownH)
    nvgFillColor(vg, nvgRGBAf(crownClr[1], crownClr[2], crownClr[3], 1.0))
    nvgFill(vg)
    -- 王冠边缘高光
    nvgStrokeColor(vg, nvgRGBAf(1.0, 1.0, 1.0, 0.5))
    nvgStrokeWidth(vg, 0.8 * s)
    nvgStroke(vg)
    nvgRestore(vg)

    nvgRestore(vg)
end

return Chenxi
