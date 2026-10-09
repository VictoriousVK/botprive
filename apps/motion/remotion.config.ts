// Remotion settings for the Alpha Edge films (https://www.remotion.dev/docs/config).
import { Config } from "@remotion/cli/config";

Config.setVideoImageFormat("jpeg");
Config.setJpegQuality(92);
Config.setPixelFormat("yuv420p");
Config.setColorSpace("bt709");
Config.setCodec("h264");
Config.setCrf(18);
Config.setOverwriteOutput(true);
Config.setPublicDir("public");
// A Chromium already installed (CI, offline machines): REMOTION_BROWSER_EXECUTABLE=/path/to/chrome
if (process.env.REMOTION_BROWSER_EXECUTABLE) Config.setBrowserExecutable(process.env.REMOTION_BROWSER_EXECUTABLE);
