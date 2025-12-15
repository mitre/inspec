module Inspec::Resources
  class ArchHelper
    def self.fetch_arch(inspec, platform)
      if platform[:name] == "mac_os_x"
        inspec.command("uname -m").stdout.strip
      else
        platform[:arch]
      end
    end
  end
end
