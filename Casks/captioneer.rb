cask "captioneer" do
  version :latest
  sha256 :no_check

  url "https://github.com/radioheavy/captioneer/releases/latest/download/Captioneer.dmg"
  name "Captioneer"
  desc "On-device live transcription + translation overlay captions for macOS"
  homepage "https://github.com/radioheavy/captioneer"

  depends_on macos: ">= :sequoia"

  app "Captioneer.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-cr", "#{appdir}/Captioneer.app"]
  end

  zap trash: [
    "~/Library/Preferences/dev.fka.captioneer.plist",
    "~/Library/Saved Application State/dev.fka.captioneer.savedState",
  ]
end
