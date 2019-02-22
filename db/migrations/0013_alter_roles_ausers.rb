Sequel.migration do
  change do
    alter_table(:roles_users) do
      add_foreign_key [:role_id], :roles, name: :roles_users_role_id_fkey
      add_foreign_key [:user_id], :auth_users, name: :roles_users_auth_users_id_fkey
    end
  end
end