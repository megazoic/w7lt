Sequel.migration do
  up do
    drop_table(:roles_users)
    alter_table(:auth_users) do
      add_foreign_key :role_id, :roles
    end
    from(:auth_users).update(role_id: 1)
    alter_table(:auth_users) do
      set_column_not_null :role_id
    end
  end
  down do
    alter_table(:auth_users) do
      drop_column(:role_id)
    end
    create_table(:roles_users) do
      foreign_key :role_id, :roles, :null=>false
      foreign_key :user_id, :roles, :null=>false
    end
  end
end
