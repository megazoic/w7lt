Sequel.migration do
  change do
    create_table(:unit_types) do
      primary_key :id, null: false
      String :type, null: false
      String :desc
    end
    create_table(:units) do
      primary_key :id, null: false
      foreign_key :created_by_id, :members, null: false
      foreign_key :unit_type_id, :unit_types, null: false
      Integer :active, null: false
      String :name
      DateTime :ts, null: false
    end
    create_join_table(unit_id: :units, mbr_id: :members)
  end
end
