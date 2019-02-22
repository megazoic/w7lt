Sequel.migration do
  change do
    alter_table(:roles) do
      add_primary_key :id
    end
  end
end