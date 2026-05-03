Sequel.migration do
  up do
    create_table(:event_types) do
      primary_key :id, null: false
      foreign_key :a_user_id, :auth_users, null: false
      String :name
      String :descr
    end
    create_table(:events) do
      primary_key :id, null: false
      foreign_key :a_user_id, :auth_users, null: false
      foreign_key :mbr_id, :members, null: false
      foreign_key :event_type_id, :event_types, null: false
      Integer :duration
      String :name
      String :descr
      String :duration_units
      DateTime :ts, null: false
    end
    alter_table(:logs) do
      add_foreign_key :event_id, :events, null: true
    end
    create_join_table({mbr_id: :members, event_id: :events}, name: :members_events)
    # Only seed if the owning auth_user exists (safe on a fresh test database).
    if from(:auth_users).where(id: 22).count > 0
      from(:event_types).multi_insert([{a_user_id:22, name:'weekly net'}, {a_user_id:22, name:'monthly meeting'}])
    end
  end
  down do
    drop_join_table({mbr_id: :members, event_id: :events}, name: :members_events)
    drop_column :logs, :event_id
    drop_table(:events)
    drop_table(:event_types)
  end
end
