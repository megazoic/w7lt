Sequel.migration do
  up do
    drop_table(:logs_actions)
    alter_table :logs do
      add_foreign_key :action_id, :actions, null: false
    end
  end
  down do
    drop_column :logs, :action_id
    create_table :logs_actions do
      foreign_key :action_id, :actions
      foreign_key :log_id, :logs
    end
  end
end
