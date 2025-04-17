Sequel.migration do
  change do
    alter_table(:logs) do
      add_foreign_key :mbr_action_id, :member_actions, null: true
    end
  end
end
