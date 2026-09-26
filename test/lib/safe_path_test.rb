require "test_helper"

class SafePathTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("safe-path-root")
    FileUtils.mkdir_p(File.join(@root, "01_Incoming"))
    File.write(File.join(@root, "01_Incoming", "a.txt"), "x")
    @outside = Dir.mktmpdir("safe-path-outside")
  end

  teardown { FileUtils.rm_rf([@root, @outside]) }

  test "resolves paths inside the root" do
    assert_equal File.realpath(File.join(@root, "01_Incoming/a.txt")),
                 SafePath.resolve(@root, "01_Incoming/a.txt").to_s
    assert_equal File.realpath(@root), SafePath.resolve(@root, "").to_s
  end

  test "blocks traversal with forward and back slashes" do
    assert_raises(SafePath::Error) { SafePath.resolve(@root, "../#{File.basename(@outside)}") }
    assert_raises(SafePath::Error) { SafePath.resolve(@root, "01_Incoming\\..\\..\\#{File.basename(@outside)}") }
  end

  test "blocks escape through a symlink" do
    File.symlink(@outside, File.join(@root, "01_Incoming", "sneaky"))
    assert_raises(SafePath::Error) { SafePath.resolve(@root, "01_Incoming/sneaky") }
    assert_raises(SafePath::Error) { SafePath.resolve(@root, "01_Incoming/sneaky/new.txt", allow_missing: true) }
  end

  test "rejects null bytes" do
    assert_raises(SafePath::Error) { SafePath.resolve(@root, "01_Incoming/a.txt\0.dwg") }
  end

  test "missing targets need allow_missing and a real parent" do
    assert_raises(SafePath::Error) { SafePath.resolve(@root, "01_Incoming/new.txt") }
    assert SafePath.resolve(@root, "01_Incoming/new.txt", allow_missing: true)
    assert_raises(Errno::ENOENT) { SafePath.resolve(@root, "nope/new.txt", allow_missing: true) }
  end
end
