Sequel.migration do
  up do
    create_table(:refer_types) do
      primary_key :id, null: false
      String :name, null: false
      String :descr
    end
    from(:refer_types).multi_insert([{name:"website", descr:'clubs website'},
      {name:"meetup", descr:'meetup.com'},{name:"facebook", descr:'facebook.com'}])
    alter_table(:members) do
      add_foreign_key :refer_type_id, :refer_types
    end
  end
  down do
    alter_table(:members) do
      drop_column :refer_type_id
    end
    drop_table(:refer_types)
  end
end
