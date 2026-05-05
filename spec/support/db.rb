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

    # Seed all action types used throughout the app.
    # mbr_renew_check must be present so GET /home can find the latest renewal check log.
    # mbr_call_me, member_general_note, member_not_renew_followup are used by /m/* routes.
    %w[login mbr_edit mbr_renew auth_u unit event donation volunteer_hrs general_log
       mbr_renew_check mbr_call_me member_general_note member_not_renew_followup].each do |t|
      DB[:actions].insert(type: t) unless DB[:actions].where(type: t).count > 0
    end

    # Seed member_action_types. Migration 0044 seeds call_member and organize_event, but
    # the truncation above wipes them. non_renew_followup and referral are never in migrations
    # but are required by /m/followup/show and /m/member/create routes.
    %w[call_member organize_event non_renew_followup referral].each do |n|
      DB[:member_action_types].insert(name: n) unless DB[:member_action_types].where(name: n).count > 0
    end

    # Seed renewal_event_types (migration 0043 seeds these but truncation wipes them).
    # "1st reminder sent" and "2nd reminder sent" are referenced by MbrRenewal.get2ndNotice
    # but are absent from the migration — they exist only in production data.
    # Without them, RenewalEventType.getID returns '' which causes a PG integer cast error.
    ['unsubscribe', 'remind later', 'verbal assurance', 'bogus email',
     'reminder sent', 'other', 'missing email', 'no response',
     '1st reminder sent', '2nd reminder sent'].each do |n|
      DB[:renewal_event_types].insert(name: n) unless DB[:renewal_event_types].where(name: n).count > 0
    end

    # Seed payment_types and payment_methods — not present in any migration seed, only in
    # production data. Insertion order matches production ids (1-4 Donations, 5 Dues).
    # GET /m/payment/new/:id hardcodes payment_type_id: 5 for the last-dues-payment query.
    ['Donation ARRL Spectrum Defense Fund', 'Donation Tower Defense Fund',
     'Donation Repeater Fund', 'Donation Other'].each do |t|
      DB[:payment_types].insert(type: t) unless DB[:payment_types].where(type: t).count > 0
    end
    DB[:payment_types].insert(type: 'Dues') unless DB[:payment_types].where(type: 'Dues').count > 0
    ['Cash', 'Personal Check', 'online'].each do |m|
      DB[:payment_methods].insert(mode: m) unless DB[:payment_methods].where(mode: m).count > 0
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

    # Seed a renewal-check log so GET /home doesn't crash on nil[:ts].
    renew_check_action_id = DB[:actions].where(type: 'mbr_renew_check').get(:id)
    DB[:logs].insert(mbr_id: admin_mbr_id, a_user_id: 22, ts: Time.now,
                     action_id: renew_check_action_id, notes: 'seed renewal check')
  end
end
