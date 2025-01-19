module Inspec::Resources
  class PlatformHelper
    def self.fetch_version(inspec, platform)
      case platform[:name]
      when 'mac_os_x'
        product_version = inspec.command('sw_vers -productVersion').stdout.strip
        build_version = inspec.command('sw_vers -buildVersion').stdout.strip
        puts("Fetched macOS version: #{product_version}.#{build_version}")
        "#{product_version}.#{build_version}"
      when 'freebsd'
        release_version = platform[:release] || '0.0.0'
        build_version = inspec.command('uname -r').stdout.strip.split('-').last
        "#{release_version}.#{build_version}"
      else
        platform[:release] || '0.0.0'
      end
    rescue StandardError => e
      Inspec::Log.warn("Failed to fetch version: #{e.message}")
      '0.0.0'
    end

    def self.check_name(name, value)
      if value.include?('*')
        cleaned = Regexp.escape(value).gsub('\*', '.*?')
        name =~ /#{cleaned}/
      else
        name == value
      end
    end

    def self.check_release(release, value)
      if value.include?('*')
        cleaned = Regexp.escape(value).gsub('\*', '.*?')
        release =~ /#{cleaned}/
      else
        release == value
      end
    end
  end
end
