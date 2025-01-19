require 'inspec/resources/platform'
require 'inspec/resources/version_helper'
require 'inspec/resources/arch_helper'
require 'inspec/resources/release_helper'
require 'rubygems'

module Inspec::Resources
  class OSResource < PlatformResource
    name 'os'
    supports platform: 'unix'
    supports platform: 'windows'
    desc 'Use the os InSpec audit resource to test the platform on which the system is running. The `release` method returns the release version as a string, suitable for string comparisons. The `version` method returns a semantic version object, suitable for semantic version comparisons.'
    example <<~EXAMPLE
      describe os[:family] do
        it { should eq 'redhat' }
      end

      describe os.redhat? do
        it { should eq true }
      end

      describe os.linux? do
        it { should eq true }
      end

      describe os.release do
        it { should eq '8.10' }
      end

      describe os.version do
        it { should cmp >= '8.10' }
      end

      describe os.version do
        it { should eq '14.7.2' }
      end
    EXAMPLE

    # reuse helper methods from backend
    %w[aix? redhat? debian? suse? bsd? solaris? linux? unix? windows? hpux? darwin? freebsd?].each do |os_family|
      define_method(os_family.to_sym) do
        @platform.send(os_family)
      end
    end

    def version
      @version ||= VersionHelper.parse_version(fetch_version)
    end

    def arch
      @arch ||= ArchHelper.fetch_arch(inspec, @platform)
    end

    def release
      @release ||= ReleaseHelper.fetch_release(inspec, @platform)
    end

    def params
      platform_info.merge(
        release:,
        arch:,
        version: version.to_s
      ).merge(VersionHelper.version_info(version))
    end

    def resource_id
      @platform.name || 'OS'
    end

    def to_s
      'Operating System Detection'
    end

    private

    def platform_info
      {
        name: @platform.name,
        family: @platform.family
      }
    end
  end
end
