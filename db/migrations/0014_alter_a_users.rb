Sequel.migration do
  change do
    alter_table(:auth_users) do
      set_column_allow_null :mbr_id
      set_column_allow_null :role
    end
  end
end
