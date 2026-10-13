---@meta

-- recoil-lua-library declares GL as an enum but types its constants as integer,
-- so every gl.* call that takes a GL constant warns; widen the enum to integer
---@alias GL integer
