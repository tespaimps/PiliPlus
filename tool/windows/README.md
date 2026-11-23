# Windows one-click build

These scripts target the prepared Windows workspace. Copy the four `.ps1` files into the workspace `.tools` directory and `Build-PiliPlus.cmd` into the workspace root, next to `PiliPlus-main` and `.tools`. Use PowerShell 7. The workspace must already contain Flutter, Java 17, Android SDK, the local Gradle archive and checksum, resolved Flutter dependencies, and the existing development signing backup. Keep the signing backup local.

Double-click `Build-PiliPlus.cmd` to build the ARM64 development APK and see progress, output and the verification result. The APK goes to the workspace root and logs go to `.tools/build-logs`. To choose a build number, run `Build-PiliPlus.cmd -BuildNumber 5659`.
