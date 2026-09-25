cask "opencode2-desktop" do
  version "2.0.16"
  sha256 "e3176475f0db74ed80875c68e57bb19de9a03f4043b90386050944e2f66b21fa"

  url "https://opencode.ai/files/bin/#{version}/opencode-desktop-mac-arm64.dmg"
  name "OpenCode 2"
  desc "OpenCode 2 desktop coding agent"
  homepage "https://opencode.ai/v2/docs/"

  auto_updates true
  depends_on arch: :arm64

  app "OpenCode.app"
end
