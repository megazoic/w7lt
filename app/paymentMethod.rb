require_relative '../config/sequel'

module MemberTracker
  class PaymentMethod < Sequel::Model
    one_to_many :payments, :class=>"MemberTracker::Payment", key: :payment_method_id
  end
end