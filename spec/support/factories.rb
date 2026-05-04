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
end
