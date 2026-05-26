-- ============================================================================
-- Pool.lua - 通用对象池
-- 避免高频 table 创建/GC 导致的卡顿
--
-- 用法:
--   local Pool = require "lib.Pool"
--   local bulletPool = Pool.new(128)  -- 预分配 128 个槽位
--
--   -- 获取对象（从回收池取或创建新 table）
--   local b = bulletPool:get()
--   b.x, b.y, b.vx, b.vy = 100, 200, 1, 0
--
--   -- 归还对象（清空并放回池中）
--   bulletPool:release(b)
--
--   -- 带初始化的快捷方式
--   local b = bulletPool:acquire({ x=100, y=200, vx=1, vy=0 })
--
--   -- 查看池状态
--   print(bulletPool:stats())  --> "idle=5 total=128"
-- ============================================================================

local M = {}
M.__index = M

--- 创建对象池
---@param prealloc number|nil 预分配数量（默认 64）
---@param resetFn function|nil 自定义重置函数，参数为 (obj)，归还时调用
---@return table Pool 实例
function M.new(prealloc, resetFn)
    prealloc = prealloc or 64

    local pool = setmetatable({
        _idle = {},      -- 空闲对象栈
        _count = 0,      -- 空闲数量（避免 # 运算）
        _total = 0,      -- 累计创建数量
        _resetFn = resetFn,
    }, M)

    -- 预分配
    for _ = 1, prealloc do
        pool._count = pool._count + 1
        pool._idle[pool._count] = {}
        pool._total = pool._total + 1
    end

    return pool
end

--- 从池中获取一个空 table
---@return table
function M:get()
    if self._count > 0 then
        local obj = self._idle[self._count]
        self._idle[self._count] = nil
        self._count = self._count - 1
        return obj
    end
    -- 池耗尽，创建新对象
    self._total = self._total + 1
    return {}
end

--- 从池中获取并批量赋值
---@param init table 初始字段键值对
---@return table
function M:acquire(init)
    local obj = self:get()
    if init then
        for k, v in pairs(init) do
            obj[k] = v
        end
    end
    return obj
end

--- 归还对象到池中
--- 会清空所有字段（或调用自定义 resetFn）
---@param obj table
function M:release(obj)
    if obj == nil then return end

    -- 重置对象
    if self._resetFn then
        self._resetFn(obj)
    else
        -- 默认：清空所有字段
        for k in pairs(obj) do
            obj[k] = nil
        end
    end

    self._count = self._count + 1
    self._idle[self._count] = obj
end

--- 批量归还（从数组中移除 dead 对象并归还池）
--- 适用于 "标记-清除" 模式：先标记 obj.dead = true，再统一清理
---@param list table 活跃对象数组
---@param deadField string|nil 判定死亡的字段名（默认 "dead"）
---@return number 本次回收数量
function M:sweep(list, deadField)
    deadField = deadField or "dead"
    local recycled = 0
    for i = #list, 1, -1 do
        if list[i][deadField] then
            self:release(list[i])
            table.remove(list, i)
            recycled = recycled + 1
        end
    end
    return recycled
end

--- 清空整个活跃列表并全部归还池
---@param list table 活跃对象数组
function M:drain(list)
    for i = #list, 1, -1 do
        self:release(list[i])
        list[i] = nil
    end
end

--- 查看池统计
---@return string
function M:stats()
    return string.format("idle=%d total=%d", self._count, self._total)
end

--- 当前空闲数量
---@return number
function M:idleCount()
    return self._count
end

--- 累计创建总数
---@return number
function M:totalCreated()
    return self._total
end

return M
