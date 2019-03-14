require_relative '../config/sequel'

module MemberTracker
  class PaymentType < Sequel::Model
    one_to_many :payments, :class=>"MemberTracker::Payment", key: :payment_type_id
  end
end