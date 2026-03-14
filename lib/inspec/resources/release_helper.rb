module Inspec::Resources
  class ReleaseHelper
    def self.fetch_release(inspec, platform)
      if platform[:name] == "mac_os_x"
        inspec.command("sw_vers -productVersion").stdout.strip
      else
        platform[:release]
      end
    end
  end
end
