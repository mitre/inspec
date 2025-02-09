require 'forwardable' unless defined?(Forwardable)
require 'inspec/utils/sudoers_parser'

module Inspec::Resources
  class Sudoers < Inspec.resource(1)
    name 'sudoers'
    supports platform: 'unix'
    supports platform: 'darwin'
    supports platform: 'freebsd'
    supports platform: 'solaris'
    supports platform: 'aix'

    desc 'Use the sudoers InSpec audit resource to test the configuration of sudo.'
    example <<~EXAMPLE
      describe sudoers do
        its('parsed_data') { should_not be_empty }
      end
    EXAMPLE

    attr_reader :sudoers_files, :raw_content

    def initialize(sudoers_files = nil)
      super()
      @sudoers_files = [sudoers_files || default_sudoers_path].flatten
      @parser = SudoersParser.new
      @raw_content = load_content
      parse_content if @raw_content
    end

    def parsed_data
      @parser.parsed_data
    end

    def to_s
      "Sudoers Configuration #{@sudoers_files.join(', ')}"
    end

    def resource_id
      @sudoers_files.first || default_sudoers_path
    end

    private

    def load_content
      content = inspec.command("cat #{@sudoers_files.join(' ')}").stdout
      if content.empty?
        Inspec::Log.warn("Failed to load content from sudoers files: #{@sudoers_files.join(', ')}")
        skip_resource 'Failed to load content from sudoers files.'
        return nil
      end
      Inspec::Log.debug("raw_content: #{content}")
      content
    end

    def parse_content
      @parser.parse(@raw_content)
    rescue StandardError => e
      raise Inspec::Exceptions::ResourceFailed, "Failed to parse sudoers content: #{e.message}"
    end

    def default_sudoers_path
      path = case inspec.os.name
             when 'darwin'
               '/private/etc/sudoers'
             when 'freebsd'
               '/usr/local/etc/sudoers'
             when 'solaris'
               '/etc/opt/sudoers'
             when 'aix'
               '/etc/security/sudoers'
             else
               '/etc/sudoers'
             end

      Inspec::Log.warn("Default sudoers path #{path} does not exist.") unless inspec.file(path).exist?
      path
    end
  end
end
