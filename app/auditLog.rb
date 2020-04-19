require_relative '../config/sequel'
module MemberTracker
  class AuditLog < Sequel::Model
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :payment, :class=>Payment, key: :pay_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :unit, :class=>Unit, key: :unit_id
  end
end
