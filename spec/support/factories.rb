require 'bcrypt'
require 'securerandom'

# Lightweight factory helpers for building test records.
# Include this module in specs via: include Factories
# Or configure it globally in spec_helper with config.include Factories, :db
#
# Usage:
#   member      = create_member(fname: 'Jane', lname: 'Smith')
#   auth_user   = create_auth_user(member: member, role_name: 'auth_u')
#   auth_user   = create_auth_user(member: member, role_name: 'mbr_mgr', password: 'P@ssw0rd1')

module Factories
  SEED_ROLES = [
    { name: 'auth_u',    rank: 1 },
    { name: 'mbr_mgr',   rank: 2 },
    { name: 'read_only', rank: 3 },
    { name: 'inactive',  rank: 99 },
  ].freeze

  def self.seed_roles
    SEED_ROLES.each do |r|
      DB[:roles].insert(r) unless DB[:roles].where(name: r[:name]).count > 0
    end
  end

  # Inserts a member row and returns the Sequel model instance.
  def create_member(overrides = {})
    defaults = {
      fname: 'Test',
      lname: "Member_#{SecureRandom.hex(4)}",
      email: "test_#{SecureRandom.hex(4)}@example.com"
    }
    id = DB[:members].insert(defaults.merge(overrides))
    MemberTracker::Member[id]
  end

  # Inserts an auth_user row tied to an existing member and returns the model instance.
  # role_name must match a name in SEED_ROLES.
  # password must satisfy BCrypt (plain text; will be hashed).
  def create_auth_user(member:, role_name: 'auth_u', password: 'P@ssw0rd1')
    rid = DB[:roles].where(name: role_name).get(:id)
    raise "Role '#{role_name}' not found — did seed_roles run?" if rid.nil?
    encrypted = BCrypt::Password.create(password).to_s
    id = DB[:auth_users].insert(
      mbr_id:       member.id,
      password:     encrypted,
      role_id:      rid,
      new_login:    0,
      last_login:   Time.now,
      time_pwd_set: Time.now
    )
    MemberTracker::AuthUser[id]
  end

  # Returns the integer id for a role by name.
  def role_id(name)
    DB[:roles].where(name: name).get(:id)
  end

  # Inserts a log row and returns the Sequel model instance.
  def create_log(overrides = {})
    defaults = {
      mbr_id:    22,
      a_user_id: 22,
      ts:        Time.now,
      action_id: DB[:actions].where(type: 'general_log').get(:id),
      notes:     'test log entry'
    }
    id = DB[:logs].insert(defaults.merge(overrides))
    MemberTracker::Log[id]
  end

  # Inserts a unit_type row and returns the Sequel model instance.
  def create_unit_type(**overrides)
    attrs = { a_user_id: 22, type: "test_#{SecureRandom.hex(4)}", descr: 'test unit type' }.merge(overrides)
    id = DB[:unit_types].insert(attrs)
    MemberTracker::UnitType[id]
  end

  # Inserts a unit row and returns the Sequel model instance.
  def create_unit(unit_type:, **overrides)
    attrs = { unit_type_id: unit_type.id, a_user_id: 22, active: 1, ts: Time.now }.merge(overrides)
    id = DB[:units].insert(attrs)
    MemberTracker::Unit[id]
  end

  # Inserts an event_type row and returns the Sequel model instance.
  def create_event_type(**overrides)
    attrs = { a_user_id: 22, name: "Test Event Type #{SecureRandom.hex(4)}", descr: 'test' }.merge(overrides)
    id = DB[:event_types].insert(attrs)
    MemberTracker::EventType[id]
  end

  # Inserts an event row and returns the Sequel model instance.
  def create_event(member:, event_type:, **overrides)
    attrs = {
      a_user_id:     22,
      mbr_id:        member.id,
      event_type_id: event_type.id,
      ts:            Time.now
    }.merge(overrides)
    id = DB[:events].insert(attrs)
    MemberTracker::Event[id]
  end

  # Inserts an mbr_renewals record and returns the Sequel model instance.
  def create_mbr_renewal(member:, **overrides)
    attrs = {
      a_user_id:             22,
      mbr_id:                member.id,
      renewal_event_type_id: DB[:renewal_event_types].where(name: 'reminder sent').get(:id),
      notes:                 'test renewal note',
      ts:                    Time.now
    }.merge(overrides)
    id = DB[:mbr_renewals].insert(attrs)
    MemberTracker::MbrRenewal[id]
  end

  # Inserts a member_actions record and returns the Sequel model instance.
  def create_member_action(member:, **overrides)
    type_id = DB[:member_action_types].where(name: 'non_renew_followup').get(:id)
    attrs = {
      a_user_id:             22,
      member_target:         member.id,
      member_action_type_id: type_id,
      completed:             false,
      notes:                 'test followup note',
      ts:                    Time.now
    }.merge(overrides)
    id = DB[:member_actions].insert(attrs)
    MemberTracker::MemberAction[id]
  end

  # Inserts a donation payment (with an associated log) and returns the model instance.
  def create_payment(member:, **overrides)
    log = create_log(mbr_id: member.id)
    attrs = {
      mbr_id:            member.id,
      a_user_id:         22,
      payment_type_id:   DB[:payment_types].where(type: 'Donation Other').get(:id),
      payment_method_id: DB[:payment_methods].where(mode: 'Cash').get(:id),
      payment_amount:    10.0,
      ts:                Time.now,
      log_id:            log.id
    }.merge(overrides)
    id = DB[:payments].insert(attrs)
    MemberTracker::Payment[id]
  end
end
