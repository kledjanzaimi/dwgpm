require "test_helper"

class TemplatesFlowTest < ActionDispatch::IntegrationTest
  setup do
    clear_storage!
    FileUtils.rm_rf(Dir[FolderTemplate.dir.join("{t_*.yml,.history}")])
    @admin = create_user("Admin", admin: true)
    @pm = create_user("Pam Manager")
  end

  test "only admins can manage templates" do
    sign_in @pm
    get templates_path
    assert_response :forbidden
    patch template_path("standard_v1"), params: { template: { folders: {} } }
    assert_response :forbidden
  end

  test "admin sees templates and the editor" do
    sign_in @admin
    get templates_path
    assert_select "h2 a", "standard_v1"
    get edit_template_path("standard_v1")
    assert_response :success
    # Rows show just the folder name; the full path travels in a hidden field.
    assert_select "input.path-input[value='DWG'][title='02_Drawings/DWG']"
    assert_select "input.path-full[type=hidden][value='02_Drawings/DWG'][data-parent='02_Drawings']"
    assert_select "input[type=checkbox][name='template[folders][0][user][]']"
  end

  test "duplicate, edit, resync and delete a template" do
    sign_in @admin
    post templates_path, params: { name: "t_civil", from: "standard_v1" }
    assert_redirected_to edit_template_path("t_civil")
    project = create_project("civil-1", creator: @admin).tap { _1.update!(template_name: "t_civil") }

    tf = TemplateFile.find("t_civil")
    folders = tf.sorted_folders.each_with_index.to_h { |f, i| [i.to_s, f] }
    folders["new"] = { "path" => "04_Archive", "project_manager" => %w[view] }
    patch template_path("t_civil"), params: { template: {
      digest: tf.digest, folders: folders,
      library_source: tf.library_source, library_dest: tf.library_dest, library_mode: "copy"
    } }
    assert_redirected_to edit_template_path("t_civil")
    assert_match "added 04_Archive", flash[:notice]
    assert AuditLog.where(action: "template_update").where("detail LIKE ?", "%04_Archive%").exists?

    # A new folder only reaches existing projects through resync.
    refute Dir.exist?(File.join(project.root, "04_Archive"))
    post resync_template_path("t_civil")
    assert Dir.exist?(File.join(project.root, "04_Archive"))

    delete template_path("t_civil")
    assert TemplateFile.exists?("t_civil"), "templates in use cannot be deleted"

    project.update!(template_name: "standard_v1")
    delete template_path("t_civil")
    refute TemplateFile.exists?("t_civil")
  end

  test "a stale save is refused and the form is shown again" do
    sign_in @admin
    post templates_path, params: { name: "t_stale", from: "" }
    patch template_path("t_stale"), params: { template: {
      digest: "not-the-current-digest", folders: { "0" => { path: "X" } }, library_mode: "copy"
    } }
    assert_response :unprocessable_entity
    assert_select ".errors", /changed by someone else/
  end
end
