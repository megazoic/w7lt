Sequel.migration do
  up do
    drop_column :auth_users, :active
  end
  down do
    add_column :auth_users, :active
    from(:auth_users).update(active: 1)
    alter_table(:auth_users) do
      set_column_not_null :active
    end
  end
end