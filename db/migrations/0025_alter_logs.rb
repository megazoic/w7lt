Sequel.migration do
  up do
    drop_column :logs, :hours
  end
  down do
    add_column :logs, :hours, Float
  end
end
