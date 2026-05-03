require_relative 'factories'

RSpec.configure do |c|
  c.include Factories, :db

  c.around(:example, :db) do |example|
    DB.transaction(rollback: :always) { example.run }
  end

  c.before(:suite) do
    # Truncate all tables in leaf-to-root order so FK constraints don't block.
    # RESTART IDENTITY resets serial sequences between runs.
    [
      :member_actions,
      :mbr_renewals,
      :audit_logs,
      :payments,
      :logs,
      :members_events,
      :roles_users,
      :events,
      :units_members,
      :units,
      :members,
      :auth_users,
      :actions,
      :roles,
      :unit_types,
      :event_types,
      :payment_types,
      :payment_methods,
      :refer_types,
      :renewal_event_types,
      :member_action_types
    ].each do |table|
      DB[table].truncate(cascade: true, restart: true) if DB.table_exists?(table)
    end

    # Seed the four standard roles that the rest of the app depends on.
    Factories.seed_roles

    # Seed the action types used throughout the app for logging.
    %w[login mbr_edit mbr_renew auth_u unit event donation volunteer_hrs general_log].each do |t|
      DB[:actions].insert(type: t) unless DB[:actions].where(type: t).count > 0
    end

    # The dev/test before-filter in api.rb hard-codes session[:auth_user_id] = 22.
    # Insert a committed admin auth_user with that id so route tests don't blow up
    # on Auth_user[22].mbr_id inside the /m/* before filter.
    admin_mbr_id = DB[:members].insert(fname: 'Dev', lname: 'Admin',
                                       email: 'dev_admin@example.com')
    admin_role_id = DB[:roles].where(name: 'auth_u').get(:id)
    DB[:auth_users].insert(id: 22, mbr_id: admin_mbr_id,
                           password: BCrypt::Password.create('Dev@dmin1').to_s,
                           role_id: admin_role_id, new_login: 0,
                           last_login: Time.now, time_pwd_set: Time.now)
  end
end
