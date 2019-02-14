Sequel.migration do
  change do
    alter_table(:auth_users) do
      add_column :role, String, null: false
      drop_column :authority
    end
  end
end