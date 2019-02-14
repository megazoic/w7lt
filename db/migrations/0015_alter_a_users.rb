Sequel.migration do
  change do
    alter_table(:auth_users) do
      drop_column :role
    end
  end
end
