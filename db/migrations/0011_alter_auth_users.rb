Sequel.migration do
  change do
    alter_table(:auth_users) do
      set_column_not_null :mbr_id
    end
  end
end