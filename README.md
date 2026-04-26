# new-tiled

基于 [Simple-Tiled-Implementation](https://github.com/karai17/Simple-Tiled-Implementation) 的 Tiled 地图库，适用于 LÖVE 框架。

## 特性

- 支持 Tiled 1.2.1 地图格式
- 中文注释，易于阅读和理解
- 支持正交、等距、六边形地图
- 支持 tile 图层、对象图层、图像图层
- 支持 tile 动画
- 支持无限地图（Chunks）

## 使用方法

```lua
local sti = require("sti")
local map = sti("map.lua")

function love.update(dt)
    map:update(dt)
end

function love.draw()
    map:draw()
end
```
