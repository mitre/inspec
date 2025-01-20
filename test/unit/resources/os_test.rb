require "helper"
require "inspec/resource"
require "inspec/resources/os"
require_relative "../../helpers/mock_loader"

# Configure the logger to output debug messages
Inspec::Log.level = :debug

describe "Inspec::Resources::Os" do
  it "verify os parsing on CentOS" do
    resource = MockLoader.new(:centos7).load_resource("os")
    _(resource.resource_id).must_equal "centos"
    _(resource.name).must_equal "centos"
    _(resource.family).must_equal "redhat"
    _(resource.release).must_equal "7.1.1503"
    _(resource.arch).must_equal "x86_64"
  end

  it "read env variable on Windows" do
    resource = MockLoader.new(:windows).load_resource("os")
    _(resource.resource_id).must_equal "windows"
    _(resource.name).must_equal "windows"
    _(resource.family).must_equal "windows"
    _(resource.release).must_equal "6.2.9200"
    _(resource.arch).must_equal "x86_64"
  end

  it "verify os parsing on Debian" do
    resource = MockLoader.new(:debian8).load_resource("os")
    _(resource.resource_id).must_equal "debian"
    _(resource.name).must_equal "debian"
    _(resource.family).must_equal "debian"
    _(resource.release).must_equal "8"
    _(resource.arch).must_equal "x86_64"
  end

  it "verify os parsing on Ubuntu" do
    resource = MockLoader.new(:ubuntu).load_resource("os")
    _(resource.name).must_equal "ubuntu"
    _(resource.family).must_equal "debian"
    _(resource.release).must_equal "22.04"
    _(resource.arch).must_equal "x86_64"
  end

  it "verify os parsing on Mint" do
    resource = MockLoader.new(:mint18).load_resource("os")
    _(resource.name).must_equal "linuxmint"
    _(resource.family).must_equal "debian"
    _(resource.release).must_equal "18"
    _(resource.arch).must_equal "x86_64"
  end

  # Direct tests for unique or special cases
  it "verify version methods on macOS" do
    resource = MockLoader.new(:macos1472).load_resource("os")
    _(resource.version.to_s).must_equal "14.7.2.23H311"
    _(resource.version.major).must_equal 14
    _(resource.version.minor).must_equal 7
    _(resource.version.patch).must_equal 2
    _(resource.version.build).must_equal "23H311"
  end

  it "verify semver comparisons on Ubuntu" do
    resource = MockLoader.new(:ubuntu2204).load_resource("os")
    _(resource.version).must_be :>, "8.1"
    _(resource.version).must_be :<, "22.5"
    _(resource.version).must_be :==, "22.4"
    _(resource.version).must_be :>=, "22.4"
    _(resource.version).must_be :<=, "22.4"
    _(resource.version).must_be :>, 8.1
    _(resource.version).must_be :<, 22.5
    _(resource.version).must_be :==, 22.4
    _(resource.version).must_be :>=, 22.4
    _(resource.version).must_be :<=, 22.4
  end
end
