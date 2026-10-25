function love.conf(t)
    t.identity = "prison-breaker"
    t.version = "11.4"
    t.window.title = "Cell Block Zero"
    t.window.width = 1024
    t.window.height = 640
    t.window.minwidth = 640
    t.window.minheight = 400
    t.window.resizable = true
    t.window.fullscreen = true
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.touch = false
    t.modules.video = false
end
