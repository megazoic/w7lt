Sequel.migration do
  change do
    add_column :auth_users, :new_login, Integer
    from(:auth_users).update(new_login: 0)
    alter_table(:auth_users) do
      set_column_type :new_login, Integer, null: false
    end
  end
end
