class CreateCoreTables < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string  :email, null: false
      t.string  :name, null: false
      t.string  :password_digest, null: false
      t.boolean :global_admin, null: false, default: false
      t.datetime :disabled_at
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :projects do |t|
      t.string     :name, null: false
      t.string     :slug, null: false
      t.string     :template_name, null: false, default: "standard_v1"
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.datetime   :archived_at
      t.timestamps
    end
    add_index :projects, :slug, unique: true

    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string     :role, null: false
      t.timestamps
    end
    add_index :memberships, %i[user_id project_id], unique: true

    create_table :audit_logs do |t|
      t.references :user, foreign_key: true
      t.references :project, foreign_key: true
      t.string     :action, null: false
      t.string     :path
      t.string     :ip
      t.string     :detail
      t.boolean    :allowed, null: false, default: true
      t.datetime   :created_at, null: false
    end
    add_index :audit_logs, %i[project_id created_at]
  end
end
