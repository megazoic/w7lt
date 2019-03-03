
RSpec.configure do |c|
  c.around(:example, :db) do |example|
    DB.transaction(rollback: :always) {example.run}
  end
  c.before(:suite) do
    Sequel::Model.plugin :validation_helpers
    Sequel.extension :migration
    Sequel::Migrator.run(DB, './db/migrations')
    DB[:members].truncate
    DB[:authUsers].truncate
  end
end