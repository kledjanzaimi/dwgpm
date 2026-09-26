require "test_helper"

class FolderTemplateTest < ActiveSupport::TestCase
  setup { @tpl = FolderTemplate.load("standard_v1") }

  test "a defined folder uses its own rule" do
    assert_equal %w[view upload], @tpl.nearest_rule("02_Drawings/DWG")["user"]
  end

  test "user-created subfolders inherit the nearest defined ancestor" do
    assert_equal %w[view upload], @tpl.nearest_rule("02_Drawings/DWG/clientX/sub")["user"]
    assert_equal %w[view], @tpl.nearest_rule("02_Drawings/PDF")["user"]
  end

  test "undefined paths fail closed" do
    assert_nil @tpl.nearest_rule("99_Unknown")
    assert_nil @tpl.nearest_rule("")
  end

  test "backslashes and stray separators are normalised" do
    assert_equal @tpl.nearest_rule("02_Drawings/DWG"), @tpl.nearest_rule("\\02_Drawings\\DWG\\")
  end

  test "folder matching is case-sensitive, so wrong casing is denied" do
    assert_nil @tpl.nearest_rule("00_admin")
  end
end
