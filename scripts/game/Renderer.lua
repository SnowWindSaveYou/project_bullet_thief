-- ============================================================================
-- Renderer.lua - 基础渲染辅助（背景、世界坐标等）
-- ============================================================================

local M = {}

---@type userdata
local vg_ = nil
local W_, H_, dpr_ = 0, 0, 1.0

-- 斜投影参数
M.SHADOW_ANGLE = math.pi * 0.25   -- 45 度
M.SHADOW_SCALE = 0.4              -- 阴影缩放（与"高度"相关，地面物体用 1.0）
local COS_A = math.cos(M.SHADOW_ANGLE)
local SIN_A = math.sin(M.SHADOW_ANGLE)

function M.init(_vg, _W, _H, _dpr)
    vg_ = _vg
    W_  = _W
    H_  = _H
    dpr_ = _dpr
    print(string.format("[Renderer] 逻辑尺寸: %dx%d", W_, H_))
end

-- 计算斜投影阴影偏移量
-- @param height 物体离地面高度（0 = 贴地）
function M.shadowOffset(height)
    local dist = 8 + height * 0.6
    return COS_A * dist, SIN_A * dist
end

-- ----------------------------------------------------------------
-- 地面砖块图案（大矩形叠压版）
-- 形状由同色大圆角矩形叠压融合；不同颜色形状也可自由重叠
-- ----------------------------------------------------------------

local function lrng(seed)
    seed = (seed * 1664525 + 1013904223) & 0x7fffffff
    return seed, seed / 0x7fffffff
end

-- 基准色 #425972 → (0.259, 0.349, 0.447)
local TILE_COLORS = {
    { 0.246, 0.332, 0.425 }, -- 暗（基准×95%）
    { 0.272, 0.366, 0.469 }, -- 中（基准×105%）
    { 0.298, 0.401, 0.514 }, -- 亮（基准×115%）
}

local TR = 11  -- 圆角半径

-- 形状模板 {dx, dy, dw, dh}
-- 单条约 60×120px（1:2 比例），整体跨度 120~180px
local SHAPE_DEFS = {
    -- L 形 × 4 旋转（竖条120高 + 横条120宽，交叉处叠压）
    { { 0,  0, 60,120}, { 0, 60,120, 60} },   -- L↙
    { {60,  0, 60,120}, { 0, 60,120, 60} },   -- L↘
    { { 0,  0,120, 60}, { 0,  0, 60,120} },   -- L↖
    { { 0,  0,120, 60}, {60,  0, 60,120} },   -- L↗

    -- C 形 × 2 方向（竖条 + 上横 + 下横）
    { { 0,  0, 60,120}, { 0,  0,120, 60}, { 0, 60,120, 60} },  -- C→
    { {60,  0, 60,120}, { 0,  0,120, 60}, { 0, 60,120, 60} },  -- C←

    -- 像素圆（5层渐变横条，总高约 130px）
    {
        { 30,  0, 60, 30},
        {  8, 24,104, 40},
        {  0, 55,120, 45},
        {  8, 86,104, 40},
        { 30,116, 60, 30},
    },

    -- T 形 × 2（横条 + 竖条）
    { { 0,  0,120, 60}, {30,  0, 60,120} },   -- T↓
    { { 0,60,120, 60}, {30,  0, 60,120} },    -- T↑

    -- 单横矩形 × 3
    { { 0, 0,180, 60} },
    { { 0, 0,140, 60} },
    { { 0, 0,120, 60} },

    -- 单竖矩形 × 3
    { { 0, 0, 60,180} },
    { { 0, 0, 60,140} },
    { { 0, 0, 60,120} },

    -- 两横错位叠压
    { { 0,  0,130, 60}, {25, 45,130, 60} },
    -- 两竖错位叠压
    { { 0,  0, 60,130}, {40, 28, 60,130} },

    -- 加号
    { { 0,30,120, 60}, {30,  0, 60,120} },
}

local tiles_ = nil
local tilesW_, tilesH_ = 0, 0

local function buildTiles(W, H)
    if tilesW_ == W and tilesH_ == H and tiles_ ~= nil then return end
    tilesW_, tilesH_ = W, H
    tiles_ = {}

    -- 投放槽：形状变大，槽格同步放大，密度约 55%
    local slotW = 175
    local slotH = 145
    local cols  = math.ceil(W / slotW) + 1
    local rows  = math.ceil(H / slotH) + 1
    local DENSITY = 55

    local seed = 3719

    for row = 0, rows do
        for col = 0, cols do
            seed = lrng(seed); local r1 = seed
            seed = lrng(seed); local r2 = seed
            seed = lrng(seed); local r3 = seed
            seed = lrng(seed); local r4 = seed

            if (r1 % 100) < DENSITY then
                local shapeIdx = (r2 % #SHAPE_DEFS) + 1
                local shape    = SHAPE_DEFS[shapeIdx]
                local colorIdx = (r3 % #TILE_COLORS) + 1
                local c        = TILE_COLORS[colorIdx]

                -- 锚点 = 槽格左上 + 较大随机偏移（让不同形状自然错落、互相叠压）
                local offX = (r4 % 51) - 25
                local offY = (seed % 41) - 20
                local ax = col * slotW + offX
                local ay = row * slotH + offY

                for _, rect in ipairs(shape) do
                    table.insert(tiles_, {
                        x  = ax + rect[1],
                        y  = ay + rect[2],
                        w  = rect[3],
                        h  = rect[4],
                        r  = TR,
                        cr = c[1], cg = c[2], cb = c[3],
                    })
                end
            end
        end
    end
end

-- 绘制背景
function M.drawBackground(state)
    -- 底色（#425972 × 85%）
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, W_, H_)
    nvgFillColor(vg_, nvgRGBAf(0.220, 0.297, 0.380, 1.0))
    nvgFill(vg_)

    -- 地面砖块图案（全状态都绘制）
    M.drawFloorTiles()

    -- 地图边界线（playing 时显示）
    if state == "playing" or state == "upgrade" then
        M.drawMapBoundary()
    end
end

-- 绘制地面砖块
function M.drawFloorTiles()
    buildTiles(W_, H_)

    for _, t in ipairs(tiles_) do
        nvgBeginPath(vg_)
        nvgRoundedRect(vg_, t.x, t.y, t.w, t.h, t.r)
        nvgFillColor(vg_, nvgRGBAf(t.cr, t.cg, t.cb, 1.0))
        nvgFill(vg_)
    end
end

-- 地图边界
function M.drawMapBoundary()
    local margin = 20
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, margin, margin, W_ - margin*2, H_ - margin*2, 8)
    nvgStrokeColor(vg_, nvgRGBAf(0.38, 0.50, 0.62, 0.4))
    nvgStrokeWidth(vg_, 1.5)
    nvgStroke(vg_)
end

-- 绘制世界（地图之外的杂项覆盖层，目前留空）
function M.drawWorld()
    -- 暂无
end

-- ----------------------------------------------------------------
-- 便捷绘制函数：带斜投影阴影的圆形
-- ----------------------------------------------------------------
function M.drawCircleWithShadow(x, y, r, fr, fg, fb, fa, height)
    local ox, oy = M.shadowOffset(height or 0)
    -- 阴影
    nvgBeginPath(vg_)
    nvgCircle(vg_, x + ox, y + oy, r * 0.9)
    nvgFillColor(vg_, nvgRGBAf(0.0, 0.0, 0.0, 0.45))
    nvgFill(vg_)
    -- 实体
    nvgBeginPath(vg_)
    nvgCircle(vg_, x, y, r)
    nvgFillColor(vg_, nvgRGBAf(fr, fg, fb, fa or 1.0))
    nvgFill(vg_)
end

-- ----------------------------------------------------------------
-- 便捷绘制函数：带斜投影阴影的多边形（path 方式）
-- ----------------------------------------------------------------
function M.beginShadowPath(x, y, height)
    local ox, oy = M.shadowOffset(height or 0)
    return ox, oy
end

-- ----------------------------------------------------------------
-- CRT 扫线效果（Balatro 风格）
-- 在逻辑坐标系下每隔 lineSpacing 像素绘制一条半透明黑色横线
-- lineSpacing: 扫线间距（逻辑像素，默认 3）
-- alpha: 暗条透明度（0~1，默认 0.12，越大越明显）
-- ----------------------------------------------------------------
function M.drawScanlines(lineSpacing, alpha)
    lineSpacing = lineSpacing or 3
    alpha       = alpha or 0.12

    -- 使用逻辑分辨率绘制：nvgBeginFrame 已设置好逻辑坐标映射
    -- 每条线高 1 逻辑像素，间隔 lineSpacing
    nvgBeginPath(vg_)
    for y = 0, H_ - 1, lineSpacing do
        nvgRect(vg_, 0, y, W_, 1)
    end
    nvgFillColor(vg_, nvgRGBAf(0.0, 0.0, 0.0, alpha))
    nvgFill(vg_)
end

-- ----------------------------------------------------------------
-- drawVignette(alpha): 四角压暗效果（径向渐变）
-- alpha: 边缘最大透明度（0~1，默认 0.6）
-- ----------------------------------------------------------------
function M.drawVignette(alpha)
    alpha = alpha or 0.6
    local cx, cy = W_ * 0.5, H_ * 0.5
    local radius = math.sqrt(cx * cx + cy * cy)

    -- 从中心透明到边缘纯黑的径向渐变
    local inner = nvgRGBAf(0, 0, 0, 0)
    local outer = nvgRGBAf(0, 0, 0, alpha)
    local paint = nvgRadialGradient(vg_, cx, cy, radius * 0.35, radius * 0.95, inner, outer)

    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, W_, H_)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

return M
