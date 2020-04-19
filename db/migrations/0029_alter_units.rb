Sequel.migration do
  change do
    alter_table(:units) do
      drop_column :created_by_id
      add_foreign_key :a_user_id, :auth_users, null: false
    end
  end
end