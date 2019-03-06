Sequel.migration do
  up do
    add_column :auth_users, :active, Integer
    from(:auth_users).update(active: 1)
    add_column :auth_users, :last_login, DateTime
    from(:auth_users).update(last_login: Time.now)
    alter_table(:auth_users) do
      set_column_not_null :mbr_id
      set_column_not_null :active
      set_column_not_null :last_login
      set_column_not_null :time_pwd_set
      set_column_not_null :new_login
    end
  end
  down do
    drop_column :auth_users, :active
    drop_column :auth_users, :last_login
  end
end