-- LÖVE 图形 API 的安全包装层
-- 在无 LÖVE 图形环境（headless/服务端）下运行时，所有调用均安全跳过。
-- 通过检查 love.graphics 是否可用来决定是否转发调用。
local lg       = _G.love.graphics
local graphics = { isCreated = lg and true or false }

--- 创建新的精灵批处理对象
-- @param ... 传递给 love.graphics.newSpriteBatch 的参数
-- @return SpriteBatch|nil LÖVE SpriteBatch 对象，无图形环境时返回 nil
function graphics.newSpriteBatch(...)
	if graphics.isCreated then
		return lg.newSpriteBatch(...)
	end
end

--- 创建新的 Canvas（离屏渲染目标）
-- @param ... 传递给 love.graphics.newCanvas 的参数
-- @return Canvas|nil LÖVE Canvas 对象，无图形环境时返回 nil
function graphics.newCanvas(...)
	if graphics.isCreated then
		return lg.newCanvas(...)
	end
end

--- 加载新的图片资源
-- @param ... 传递给 love.graphics.newImage 的参数
-- @return Image|nil LÖVE Image 对象，无图形环境时返回 nil
function graphics.newImage(...)
	if graphics.isCreated then
		return lg.newImage(...)
	end
end

--- 创建新的四边形（用于精灵图集裁剪）
-- @param ... 传递给 love.graphics.newQuad 的参数
-- @return Quad|nil LÖVE Quad 对象，无图形环境时返回 nil
function graphics.newQuad(...)
	if graphics.isCreated then
		return lg.newQuad(...)
	end
end

--- 获取当前激活的 Canvas
-- @param ... 传递给 love.graphics.getCanvas 的参数
-- @return Canvas|nil 当前 Canvas 对象，无图形环境时返回 nil
function graphics.getCanvas(...)
	if graphics.isCreated then
		return lg.getCanvas(...)
	end
end

--- 设置当前渲染目标 Canvas
-- @param ... 传递给 love.graphics.setCanvas 的参数
function graphics.setCanvas(...)
	if graphics.isCreated then
		return lg.setCanvas(...)
	end
end

--- 清除当前渲染目标（填充为背景色或透明）
-- @param ... 传递给 love.graphics.clear 的参数
function graphics.clear(...)
	if graphics.isCreated then
		return lg.clear(...)
	end
end

--- 将当前变换矩阵压入栈
-- @param ... 传递给 love.graphics.push 的参数
function graphics.push(...)
	if graphics.isCreated then
		return lg.push(...)
	end
end

--- 重置当前变换矩阵为单位矩阵
-- @param ... 传递给 love.graphics.origin 的参数
function graphics.origin(...)
	if graphics.isCreated then
		return lg.origin(...)
	end
end

--- 对当前变换矩阵应用缩放
-- @param ... 传递给 love.graphics.scale 的参数
function graphics.scale(...)
	if graphics.isCreated then
		return lg.scale(...)
	end
end

--- 对当前变换矩阵应用平移
-- @param ... 传递给 love.graphics.translate 的参数
function graphics.translate(...)
	if graphics.isCreated then
		return lg.translate(...)
	end
end

--- 从变换矩阵栈弹出（恢复到上一个 push 时的状态）
-- @param ... 传递给 love.graphics.pop 的参数
function graphics.pop(...)
	if graphics.isCreated then
		return lg.pop(...)
	end
end

--- 绘制图片、Canvas 或精灵批处理等可绘制对象
-- @param ... 传递给 love.graphics.draw 的参数
function graphics.draw(...)
	if graphics.isCreated then
		return lg.draw(...)
	end
end

--- 绘制矩形（描边或填充）
-- @param ... 传递给 love.graphics.rectangle 的参数
function graphics.rectangle(...)
	if graphics.isCreated then
		return lg.rectangle(...)
	end
end

--- 获取当前绘制颜色
-- @param ... 传递给 love.graphics.getColor 的参数
-- @return number, number, number, number r, g, b, a 颜色分量（0~1）
function graphics.getColor(...)
	if graphics.isCreated then
		return lg.getColor(...)
	end
end

--- 设置当前绘制颜色
-- @param ... 传递给 love.graphics.setColor 的参数
function graphics.setColor(...)
	if graphics.isCreated then
		return lg.setColor(...)
	end
end

--- 绘制折线
-- @param ... 传递给 love.graphics.line 的参数
function graphics.line(...)
	if graphics.isCreated then
		return lg.line(...)
	end
end

--- 绘制多边形（描边或填充）
-- @param ... 传递给 love.graphics.polygon 的参数
function graphics.polygon(...)
	if graphics.isCreated then
		return lg.polygon(...)
	end
end

--- 绘制一组点
-- @param ... 传递给 love.graphics.points 的参数
function graphics.points(...)
	if graphics.isCreated then
		return lg.points(...)
	end
end

--- 获取渲染窗口宽度（像素）
-- @return number 窗口宽度；无图形环境时返回 0
function graphics.getWidth()
	if graphics.isCreated then
		return lg.getWidth()
	end
	return 0
end

--- 获取渲染窗口高度（像素）
-- @return number 窗口高度；无图形环境时返回 0
function graphics.getHeight()
	if graphics.isCreated then
		return lg.getHeight()
	end
	return 0
end

return graphics
