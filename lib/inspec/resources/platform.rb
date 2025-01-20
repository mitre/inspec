require 'inspec/resource'
require 'inspec/resources/platform_helper'

module Inspec::Resources
  class PlatformResource < Inspec.resource(1)
    name 'platform'
    desc 'Use the platform InSpec resource to test the platform on which the system is running.'
    example <<~EXAMPLE
      describe platform do
        its('name') { should eq 'redhat' }
      end

      describe platform do
        it { should be_in_family('unix') }
      end
    EXAMPLE

    def initialize
      @platform = inspec.backend.platform
    end

    def family
      @platform[:family]
    end

    def release
      @platform[:release]
    end

    def arch
      @platform[:arch]
    end

    def families
      @platform[:family_hierarchy] || []
    end

    def name
      @platform[:name]
    end

    def [](key)
      # convert string to symbol
      key = key.to_sym if key.is_a? String
      return name if key == :name

      @platform[key]
    end

    def platform?(name)
      @platform[:name] == name ||
        @platform[:family_hierarchy].include?(name)
    end

    def in_family?(family)
      @platform[:family_hierarchy].include?(family)
    end

    def params
      h = {
        name:,
        families:,
        release:,
        arch:
      }
      h.delete :arch if in_family?('api') # not applicable if api

      h
    end

    def supported?(supports)
      raise ArgumentError, '`supports` is nil.' unless supports

      supports.any? do |support|
        support.all? do |k, v|
          case normalize(k)
          when :os_family, :platform_family
            in_family?(v)
          when :os, :platform
            platform?(v)
          when :os_name, :platform_name
            PlatformHelper.check_name(name, v)
          when :release
            PlatformHelper.check_release(release, v)
          end
        end
      end || supports.empty?
    end

    def normalize(key)
      key.to_s.tr('-', '_').to_sym
    end

    def resource_id
      @platform[:name] || 'platform'
    end

    def to_s
      'Platform Detection'
    end

    def fetch_version
      PlatformHelper.fetch_version(inspec, @platform)
    end
  end
end
