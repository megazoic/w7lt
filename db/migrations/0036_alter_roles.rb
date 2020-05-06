Sequel.migration do
  change do
    alter_table(:roles) do
      add_column :rank, Integer
    end
    from(:roles).update(rank: 0)
    alter_table(:roles) do
      set_column_not_null :rank
    end
  end
end