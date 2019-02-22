Sequel.migration do
  change do
    alter_table(:members) do
      drop_column :mbr_type
    end
    alter_table(:roles) do
      drop_column :desc
      add_column :description, String
    end
  end
end