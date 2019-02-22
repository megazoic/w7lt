Sequel.migration do
  change do
    alter_table(:members) do
      add_column :mbr_type, String
    end
  end
end