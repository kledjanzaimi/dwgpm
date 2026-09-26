# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_16_000001) do
  create_table "audit_logs", force: :cascade do |t|
    t.integer "user_id"
    t.integer "project_id"
    t.string "action", null: false
    t.string "path"
    t.string "ip"
    t.string "detail"
    t.boolean "allowed", default: true, null: false
    t.datetime "created_at", null: false
    t.index ["project_id", "created_at"], name: "index_audit_logs_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_audit_logs_on_project_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "project_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_memberships_on_project_id"
    t.index ["user_id", "project_id"], name: "index_memberships_on_user_id_and_project_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "template_name", default: "standard_v1", null: false
    t.integer "created_by_id", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_projects_on_created_by_id"
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.boolean "global_admin", default: false, null: false
    t.datetime "disabled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "audit_logs", "projects"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "memberships", "projects"
  add_foreign_key "memberships", "users"
  add_foreign_key "projects", "users", column: "created_by_id"
end
