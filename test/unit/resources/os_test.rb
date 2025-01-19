require 'helper'
require 'inspec/resource'
require 'inspec/resources/os'
require_relative '../../helpers/mock_loader'

# Configure the logger to output debug messages
Inspec::Log.level = :debug

describe 'Inspec::Resources::Os' do
  # Direct tests for unique or special cases
  it 'verify version methods on macOS' do
    resource = MockLoader.new(:macos1472).load_resource('os')
    _(resource.version.to_s).must_equal '14.7.2.23H311'
    _(resource.version.major).must_equal 14
    _(resource.version.minor).must_equal 7
    _(resource.version.patch).must_equal 2
    _(resource.version.build).must_equal '23H311'
  end

  it 'verify semver comparisons on Ubuntu' do
    resource = MockLoader.new(:ubuntu2204).load_resource('os')
    _(resource.version).must_be :>, '8.1'
    _(resource.version).must_be :<, '22.5'
    _(resource.version).must_be :==, '22.4'
    _(resource.version).must_be :>=, '22.4'
    _(resource.version).must_be :<=, '22.4'
    _(resource.version).must_be :>, 8.1
    _(resource.version).must_be :<, 22.5
    _(resource.version).must_be :==, 22.4
    _(resource.version).must_be :>=, 22.4
    _(resource.version).must_be :<=, 22.4
  end

  # Dynamic tests for similar or repeated cases
  MockLoader::OPERATING_SYSTEMS.each_key do |os|
    next if %i[macos1472 ubuntu2204].include?(os) # Skip unique cases

    it "verify os parsing on #{os.to_s.capitalize}" do
      resource = MockLoader.new(os).load_resource('os')
      expected = MockLoader::OPERATING_SYSTEMS[os]

      _(resource.resource_id).must_equal expected[:name]
      _(resource.name).must_equal expected[:name]
      _(resource.family).must_equal expected[:family]
      _(resource.release).must_equal expected[:release]
      _(resource.arch).must_equal expected[:arch]
      _(resource.version.to_s).must_equal expected[:release]
      _(resource.version.major).must_equal expected[:version][:major]
      _(resource.version.minor).must_equal expected[:version][:minor]
      _(resource.version.patch).must_equal expected[:version][:patch]
      _(resource.version.build).must_equal expected[:version][:build]
    end
  end
end
