Sequel.migration do
  up do
    create_table(:renewal_event_types) do
      primary_key :id, null: false
      String :name
      String :descr
    end
    from(:renewal_event_types).multi_insert([
      {name:"unsubscribe", descr:'a member requested to halt renewal reminders'},{name:"remind later", descr:"a member requested \
        that we remind them later (see note)"},{name:"verbal assurance", descr:'a member verbally assured us that they would renew'},
        {name:"bogus email", descr:"received notice that email undeliverable"}, {name:"reminder sent", descr: "just recording \
          that this action has been taken"}, {name:"other", descr: "catch-all, see note for explanation"}, {name:"missing email",
          descr:"no email address on record, this is recorded automatically when encountered"},
          {name:"no response", descr:"did not hear back after sent renewal reminder to email on record"}])
    create_table(:mbr_renewals) do
      primary_key :id, null: false
      foreign_key :a_user_id, :auth_users, null: false
      foreign_key :mbr_id, :members, null: false
      foreign_key :renewal_event_type_id, :renewal_event_types, null: false
      String :notes
      DateTime :ts, null: false
    end
    alter_table(:logs) do
      add_foreign_key :mbr_renewal_id, :mbr_renewals, null: true
    end
  end
  down do
    drop_column :logs, :mbr_renewal_id
    drop_table(:mbr_renewals)
    drop_table(:renewal_event_types)
  end
end
