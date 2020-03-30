Sequel.migration do
  up do
    drop_column :members, :apt
  end
  down do
    add_column :members, :apt, String
  end
end
