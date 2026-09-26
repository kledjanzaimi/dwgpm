require "test_helper"

class TemplateFileTest < ActiveSupport::TestCase
  setup do
    FileUtils.rm_rf(Dir[FolderTemplate.dir.join("{t_*.yml,.history}")])
  end

  def form(folders, **library)
    ActionController::Parameters.new(
      folders: folders.each_with_index.to_h { |f, i| [i.to_s, f] },
      library_source: "", library_dest: "", library_mode: "copy", **library
    )
  end

  test "round-trips standard_v1 without changing any permission" do
    original = YAML.safe_load_file(FolderTemplate.dir.join("standard_v1.yml"))
    written = YAML.safe_load(TemplateFile.find("standard_v1").to_yaml)
    sort = ->(c) { c.merge("folders" => c["folders"].sort_by { _1["path"] }) }
    assert_equal sort[original], sort[written]
  end

  test "saving writes YAML that FolderTemplate enforces, and keeps history" do
    t = TemplateFile.blank("t_one")
    assert t.save
    t = TemplateFile.find("t_one")
    t.assign_form(form([{ path: "A", "user" => %w[view] }, { path: "A\\B", "user" => %w[upload] }]))
    assert t.save, t.errors.full_messages.inspect

    tpl = FolderTemplate.load("t_one")
    assert_equal %w[view], tpl.nearest_rule("A/x")["user"]
    assert_equal %w[view upload], tpl.nearest_rule("A/B/c")["user"], "upload implies view"
    assert_equal 1, Dir[FolderTemplate.dir.join(".history/t_one/*.yml")].size
  end

  test "refuses to overwrite a template that changed since it was opened" do
    TemplateFile.blank("t_two").save
    mine = TemplateFile.find("t_two")
    theirs = TemplateFile.find("t_two")
    theirs.assign_form(form([{ path: "Theirs", "user" => %w[view] }]))
    assert theirs.save

    mine.assign_form(form([{ path: "Mine", "user" => %w[view] }]))
    refute mine.save
    assert_match(/changed by someone else/, mine.errors.full_messages.to_sentence)
    assert FolderTemplate.load("t_two").nearest_rule("Theirs")
  end

  test "rejects names the Windows file server cannot hold and case-insensitive duplicates" do
    t = TemplateFile.blank("t_three")
    t.assign_form(form([{ path: "Bad:Name" }, { path: "Trailing." }, { path: "Docs" }, { path: "docs" }]))
    refute t.valid?
    messages = t.errors.full_messages.to_sentence
    assert_match(/Bad:Name/, messages)
    assert_match(/Trailing\./, messages)
    assert_match(/more than once/, messages)
  end

  test "traversal segments are dropped or rejected, never written" do
    t = TemplateFile.blank("t_four")
    t.assign_form(form([{ path: "A/../B" }]))
    refute t.valid?
    t.assign_form(form([{ path: "./A/./B" }]))
    assert_equal ["A/B"], t.folders.map { _1["path"] }
  end

  test "template names are restricted so they cannot escape the folder" do
    assert_raises(FolderTemplate::NotFound) { TemplateFile.find("../secrets") }
    assert_raises(FolderTemplate::NotFound) { FolderTemplate.load("../secrets") }
    refute TemplateFile.blank("../x").valid?
  end

  test "library folder must be one of the template's folders" do
    t = TemplateFile.blank("t_five")
    t.assign_form(form([{ path: "Docs" }], library_source: "/srv/lib", library_dest: "_Library"))
    refute t.valid?
    t.assign_form(form([{ path: "_Library" }], library_source: "/srv/lib", library_dest: "_Library"))
    assert t.valid?, t.errors.full_messages.inspect
  end

  test "summarises changes for the audit log" do
    before = TemplateFile.find("standard_v1")
    after = TemplateFile.find("standard_v1")
    after.folders = after.folders.reject { _1["path"] == "03_Output" } +
                    [TemplateFile.folder_hash("04_Archive", "user" => %w[view])]
    after.folders.find { _1["path"] == "00_Admin" }["user"] = %w[view]
    summary = after.changes_from(before)
    assert_match "added 04_Archive", summary
    assert_match "removed 03_Output", summary
    assert_match "changed permissions on 00_Admin", summary
  end
end
