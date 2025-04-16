Sequel.migration do
  up do
    create_table(:member_action_types) do
      primary_key :id, null: false
      String :name
      String :descr
    end
    from(:member_action_types).multi_insert([
      {name:"call_member", descr:"followup on a members request to have a call"},{name:"organize_event",
      descr:"be lead on event org"}
    ])
    create_table(:member_actions) do
      primary_key :id, null: false
      foreign_key :a_user_id, :auth_users, null: false
      foreign_key :tasked_to_mbr_id, :members
      foreign_key :member_target, :members, null: false
      foreign_key :member_action_type_id, :member_action_types, null: false
      Boolean :completed, null: false, default: false
      String :notes
      DateTime :ts, null: false
    end
  end
  down do
    drop_table(:member_actions)
    drop_table(:member_action_types)
  end
end
