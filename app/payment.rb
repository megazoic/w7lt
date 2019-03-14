require_relative '../config/sequel'
module MemberTracker
  class Payment < Sequel::Model
    many_to_one :log, :class=>Log, key: :log_id
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :paymentType, :class=>"MemberTracker::PaymentType", key: :payment_type_id
    many_to_one :paymentMethod, :class=>"MemberTracker::PaymentMethod", key: :payment_method_id
  end
end