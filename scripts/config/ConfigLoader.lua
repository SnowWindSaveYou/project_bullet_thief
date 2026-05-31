-- ============================================================================
-- ConfigLoader.lua - JSON 配置加载器
-- 统一从 config/ 目录加载 JSON 配置文件
-- ============================================================================

local M = {}

--- 缓存已加载的配置（避免重复读取）
local cache_ = {}

--- 加载 JSON 配置文件
---@param path string 相对于 scripts/ 的路径, 如 "config/characters/protagonist.json"
---@return table|nil data 解析后的 table, 失败返回 nil
function M.load(path)
    if cache_[path] then
        return cache_[path]
    end

    local file = cache:GetFile(path)
    if not file then
        print("[ConfigLoader] ERROR: 找不到配置文件: " .. path)
        return nil
    end

    local jsonStr = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok then
        print("[ConfigLoader] ERROR: JSON 解析失败: " .. path .. " - " .. tostring(data))
        return nil
    end

    cache_[path] = data
    return data
end

--- 清除缓存（热重载用）
function M.clearCache()
    cache_ = {}
end

return M
