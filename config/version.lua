VersionConfig = {
  --- Whether a resource may compare its version against its GitHub release.
  ---
  --- • true (default): a warning is printed when a newer release exists,
  ---   and a confirmation when the installed version is the latest one
  --- • false: no HTTP request is ever sent
  ---
  --- Turn this off on a server with no outbound internet access, or to
  --- keep the boot sequence completely offline.
  ---
  --- This is read once at startup. Changing it needs a resource restart.
  enabled = true,
}
