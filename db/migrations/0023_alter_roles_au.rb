Sequel.migration do
  up do
    alter_table(:roles_users) do
      set_column_not_null :role_id
    end
  end
  down do
  end
end
