module Inspec::Resources
  class VersionHelper
    class OSVersion < Gem::Version
      def major
        segments[0]
      end

      def minor
        segments[1]
      end

      def patch
        segments[2]
      end

      def build
        segments[3..-1].join if segments.size > 3
      end

      def <=>(other)
        other = other.to_s if other.is_a?(Numeric)
        super(other)
      end
    end

    def self.parse_version(version_string)
      OSVersion.new(version_string)
    rescue ArgumentError
      OSVersion.new('0.0.0')
    end

    def self.version_info(version)
      {
        major: version_attr(version, :major),
        minor: version_attr(version, :minor),
        patch: version_attr(version, :patch),
        build: version_attr(version, :build)
      }
    end

    def self.version_attr(version, attr)
      version&.public_send(attr) || default_for(attr)
    end

    def self.default_for(_attr)
      nil
    end
  end
end
