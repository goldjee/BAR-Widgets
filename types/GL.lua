---@meta

-- recoil-lua-library declares GL as an enum but types its constants as integer,
-- so every gl.* call that takes a GL constant warns. Widen the enum to integer;
-- redefining the library's GL is the point, hence the disabled duplicate check.
---@diagnostic disable-next-line: duplicate-doc-alias
---@alias GL integer
