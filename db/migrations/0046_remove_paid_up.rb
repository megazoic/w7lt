Sequel.migration do
  up do
    drop_column :members, :paid_up
  end

  down do
    add_column :members, :paid_up, Integer, default: 0
  end
end
