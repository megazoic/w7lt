Sequel.migration do
  change do
    alter_table(:members) do
      add_column :modes, String
    end
  end
end