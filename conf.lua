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

    -- In the browser the canvas is the window: a fullscreen request with no
    -- click behind it is refused, and the page around it decides how big the
    -- picture is. So take the size above as it is and let the page blow it
    -- up from there.
    if love._os == "Web" then
        t.window.fullscreen = false
        t.window.resizable = false
    end
end
