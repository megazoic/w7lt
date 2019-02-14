Sequel.migration do
  change do
    alter_table(:auth_users) do
      add_foreign_key :mbr_id, :members
      drop_column :fname
      drop_column :lname
      drop_column :email
    end
  end
end