CameraConfig = {
  --- Field of view given to every camera created without an explicit one.
  ---
  --- Degrees, clamped by the engine between 1.0 and 130.0. The GTA
  --- gameplay camera sits around 50.0.
  ---
  --- Default: 50.0
  defaultFov = 50.0,

  --- Duration in milliseconds of the eased transition used by
  --- Siku.camera.render and Siku.camera.stopRendering when easing is
  --- requested without an explicit time.
  ---
  --- Default: 750
  defaultEaseTime = 750,

  --- Duration in milliseconds used by Siku.camera.moveTo and
  --- Siku.camera.switchTo when none is provided.
  ---
  --- Default: 1000
  defaultDuration = 1000,
}
